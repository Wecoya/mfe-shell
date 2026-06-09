#!/usr/bin/env bash
# .github/skills/push-session-metrics/scripts/push-session-metrics.sh
#
# Push Copilot session token usage metrics to the Prometheus Pushgateway.
#
# IMPORTANT — two calling modes:
#
# 1. LIVE mode (called during finalize, session still active):
#    --session-id <uuid>          Auto-reads outputTokens from events.jsonl
#                                 inputTokens will be 0 (not yet synced to cloud)
#
# 2. RETROACTIVE mode (called by agent after session_store_sql returns data):
#    --input-tokens <N>           Full per-turn totals from session_store_sql
#    --output-tokens <N>
#    These override the auto-read from events.jsonl.
#
# Usage:
#   push-session-metrics.sh [--task-id <x.y>] [--model <name>] \
#                           [--input-tokens <N>] [--output-tokens <N>] \
#                           [--credits <N>] \
#                           [--repo <owner/name>] \
#                           [--user <github-handle>] \
#                           [--reason <issue:#N|description>] \
#                           [--session-id <uuid>]
#
# Token resolution order:
#   outputTokens → (1) --output-tokens flag  (2) events.jsonl auto-read  (3) 0
#   inputTokens  → (1) --input-tokens flag   (2) 0
#   cacheReadTokens, nanoAiu → compaction events in events.jsonl
#   model        → events.jsonl session.start event
#
# Environment:
#   PUSHGATEWAY_URL  — resolved via: gh variable get PUSHGATEWAY_URL --org Wecoya
#
# Metrics pushed (PUT — idempotent):
#   copilot_session_output_tokens, copilot_session_input_tokens,
#   copilot_session_total_tokens, copilot_session_cache_read_tokens,
#   copilot_session_cost_nano_aiu, copilot_session_credits,
#   copilot_session_timestamp_seconds
#
# Pushgateway job key: copilot_<repo_slug>

set -uo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
TASK_ID="unknown"
MODEL="unknown"
INPUT_TOKENS=""
OUTPUT_TOKENS=""
CREDITS=""
REPO="${GITHUB_REPOSITORY:-}"
GIT_USER=""
REASON=""
SESSION_ID="${COPILOT_SESSION_ID:-}"

# ── Argument parsing ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id)       TASK_ID="${2:-unknown}";  shift 2 ;;
    --model)         MODEL="${2:-unknown}";     shift 2 ;;
    --input-tokens)  INPUT_TOKENS="${2:-}";     shift 2 ;;
    --output-tokens) OUTPUT_TOKENS="${2:-}";    shift 2 ;;
    --credits)       CREDITS="${2:-}";          shift 2 ;;
    --repo)          REPO="${2:-}";             shift 2 ;;
    --user)          GIT_USER="${2:-}";         shift 2 ;;
    --reason)        REASON="${2:-}";           shift 2 ;;
    --session-id)    SESSION_ID="${2:-}";       shift 2 ;;
    -h|--help)       sed -n 's/^# //p' "$0" | head -35 >&2; exit 0 ;;
    *)               echo "[push-session-metrics] Unknown argument: $1" >&2; shift ;;
  esac
done

# ── Resolve PUSHGATEWAY_URL ────────────────────────────────────────────────────
if [[ -z "${PUSHGATEWAY_URL:-}" ]]; then
  if command -v gh >/dev/null 2>&1; then
    PUSHGATEWAY_URL=$(gh variable get PUSHGATEWAY_URL --org Wecoya 2>/dev/null || true)
  fi
fi
if [[ -z "${PUSHGATEWAY_URL:-}" ]]; then
  echo "[push-session-metrics] PUSHGATEWAY_URL not set — skipping." >&2
  exit 0
fi
PUSHGATEWAY_URL="${PUSHGATEWAY_URL%/}"

# ── Resolve repo ───────────────────────────────────────────────────────────────
if [[ -z "$REPO" ]] && command -v gh >/dev/null 2>&1; then
  REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)
fi
[[ -z "$REPO" ]] && REPO="unknown/unknown"

# ── Resolve user ───────────────────────────────────────────────────────────────
if [[ -z "$GIT_USER" ]]; then GIT_USER="${GITHUB_ACTOR:-}"; fi
if [[ -z "$GIT_USER" ]] && command -v gh >/dev/null 2>&1; then
  GIT_USER=$(gh api user --jq '.login' 2>/dev/null || true)
fi
if [[ -z "$GIT_USER" ]]; then GIT_USER=$(git config user.name 2>/dev/null || true); fi
[[ -z "$GIT_USER" ]] && GIT_USER="unknown"

# ── Resolve reason ─────────────────────────────────────────────────────────────
if [[ -z "$REASON" && "$TASK_ID" != "unknown" ]] && command -v gh >/dev/null 2>&1; then
  ISSUE_NUMBER=$(gh issue list --search "\"${TASK_ID}\"" --json number --jq '.[0].number' 2>/dev/null || true)
  [[ -n "$ISSUE_NUMBER" ]] && REASON="issue:#${ISSUE_NUMBER}"
fi
[[ -z "$REASON" ]] && REASON="${TASK_ID}"

# ── Auto-read from events.jsonl (outputTokens, cacheReadTokens, nanoAiu, model) ──
# NOTE: inputTokens are NOT in events.jsonl — they only become available in the
# cloud session store after session sync (post-session-end). The agent calling
# this script should query session_store_sql first and pass --input-tokens if
# the session has already synced (see SKILL.md agent workflow).
_read_events() {
  local session_id="$1"
  local events_file="$HOME/.copilot/session-state/${session_id}/events.jsonl"
  [[ ! -f "$events_file" ]] && echo "0 0 0 unknown" && return

  python3 - "$events_file" <<'EOF'
import sys, json

output_tokens = 0
input_tokens_compaction = 0  # proxy: sum of compaction call inputTokens
cache_read_tokens = 0
nano_aiu = 0
model = "unknown"

with open(sys.argv[1]) as f:
    for line in f:
        try:
            e = json.loads(line)
            t = e.get("type", "")
            d = e.get("data", {})
            if t == "assistant.message":
                output_tokens += d.get("outputTokens", 0) or 0
            elif t == "session.compaction_complete":
                u = d.get("compactionTokensUsed", {}) or {}
                # compaction inputTokens = context compressed during this compaction call
                # used as a proxy for session input (not full per-request, but better than 0)
                input_tokens_compaction += u.get("inputTokens", 0) or 0
                cache_read_tokens += u.get("cacheReadTokens", 0) or 0
                nano_aiu += (u.get("copilotUsage", {}) or {}).get("totalNanoAiu", 0) or 0
            elif t == "session.start":
                m = d.get("selectedModel", "")
                if m:
                    model = m
        except Exception:
            pass

print(output_tokens, cache_read_tokens, nano_aiu, model, input_tokens_compaction)
EOF
}

if [[ -n "$SESSION_ID" ]]; then
  read -r _out _cache _nano _model _in_compaction < <(_read_events "$SESSION_ID")
  echo "[push-session-metrics] events.jsonl: output=${_out} cache_read=${_cache} nano_aiu=${_nano} model=${_model} input_compaction=${_in_compaction}" >&2
  [[ -z "$OUTPUT_TOKENS" ]]         && OUTPUT_TOKENS="$_out"
  [[ -z "${CACHE_READ_TOKENS:-}" ]] && CACHE_READ_TOKENS="$_cache"
  [[ -z "${COST_NANO_AIU:-}" ]]     && COST_NANO_AIU="$_nano"
  [[ "$MODEL" == "unknown" && "$_model" != "unknown" ]] && MODEL="$_model"
  # Use compaction inputTokens as proxy only if --input-tokens was not explicitly passed
  if [[ -z "$INPUT_TOKENS" && "$_in_compaction" != "0" ]]; then
    INPUT_TOKENS="$_in_compaction"
  fi
fi

# ── Normalise ──────────────────────────────────────────────────────────────────
INPUT_TOKENS=$(printf '%d'  "${INPUT_TOKENS:-0}"          2>/dev/null || echo 0)
OUTPUT_TOKENS=$(printf '%d' "${OUTPUT_TOKENS:-0}"         2>/dev/null || echo 0)
CREDITS=$(printf '%d'       "${CREDITS:-0}"               2>/dev/null || echo 0)
CACHE_READ_TOKENS=$(printf '%d' "${CACHE_READ_TOKENS:-0}" 2>/dev/null || echo 0)
COST_NANO_AIU=$(printf '%d' "${COST_NANO_AIU:-0}"         2>/dev/null || echo 0)
TOTAL_TOKENS=$(( INPUT_TOKENS + OUTPUT_TOKENS ))
TIMESTAMP=$(date +%s)

REPO_SLUG=$(printf '%s' "$REPO" | tr '/-' '_')

# ── Derive a stable per-task instance key ─────────────────────────────────────
# Each task gets its own Pushgateway grouping key (job + instance). This ensures
# that consecutive finalize calls for different tasks do NOT overwrite each other.
# Without a unique instance, PUT /metrics/job/<job> would replace ALL prior task
# data with the latest push, making the "All Sessions" table and history panels
# appear empty.
#
# Retention: one entry per unique (repo, task_id) pair in the Pushgateway.
# Re-running finalize for the same task overwrites only that task's group —
# which is the desired "latest snapshot per task" semantics.
if [[ "$TASK_ID" == "unknown" ]]; then
  # No stable task ID — fall back to session ID (or current timestamp) so we
  # still get a unique key rather than colliding with every other "unknown" push.
  INSTANCE_KEY="${SESSION_ID:-${TIMESTAMP}}"
else
  # Sanitise task ID for use in a URL path segment (e.g. "5.1" → "5__1").
  INSTANCE_KEY=$(printf '%s' "${TASK_ID}" | tr -cs 'A-Za-z0-9_-' '_')
fi

BASE_JOB_URL="${PUSHGATEWAY_URL}/metrics/job/copilot_${REPO_SLUG}"
PUSH_URL="${BASE_JOB_URL}/instance/${INSTANCE_KEY}"

# ── One-time migration: remove the legacy job-level group ─────────────────────
# Before per-instance routing was introduced, every push replaced the single
# job-level group. Delete it once so stale data doesn't skew totals.
# This is idempotent (404 on an already-deleted group is silently ignored).
curl --silent --max-time 5 -X DELETE "${BASE_JOB_URL}" >/dev/null 2>&1 || true

LABELS="task=\"${TASK_ID}\",model=\"${MODEL}\",repo=\"${REPO}\",user=\"${GIT_USER}\",reason=\"${REASON}\""

# ── Build & push ───────────────────────────────────────────────────────────────
echo "[push-session-metrics] Pushing to ${PUSH_URL}" >&2
echo "[push-session-metrics] task=${TASK_ID} model=${MODEL} user=${GIT_USER} reason=${REASON}" >&2
echo "[push-session-metrics] output=${OUTPUT_TOKENS} input=${INPUT_TOKENS} total=${TOTAL_TOKENS} cache_read=${CACHE_READ_TOKENS} nano_aiu=${COST_NANO_AIU} credits=${CREDITS}" >&2

METRIC_BODY="# TYPE copilot_session_output_tokens gauge
copilot_session_output_tokens{${LABELS}} ${OUTPUT_TOKENS}
# TYPE copilot_session_input_tokens gauge
copilot_session_input_tokens{${LABELS}} ${INPUT_TOKENS}
# TYPE copilot_session_total_tokens gauge
copilot_session_total_tokens{${LABELS}} ${TOTAL_TOKENS}
# TYPE copilot_session_cache_read_tokens gauge
copilot_session_cache_read_tokens{${LABELS}} ${CACHE_READ_TOKENS}
# TYPE copilot_session_cost_nano_aiu gauge
copilot_session_cost_nano_aiu{${LABELS}} ${COST_NANO_AIU}
# TYPE copilot_session_credits gauge
copilot_session_credits{${LABELS}} ${CREDITS}
# TYPE copilot_session_timestamp_seconds gauge
copilot_session_timestamp_seconds{${LABELS}} ${TIMESTAMP}"

if printf '%s\n' "${METRIC_BODY}" | curl \
    --silent --show-error --fail \
    --max-time 15 --retry 2 --retry-delay 3 \
    -X PUT -H "Content-Type: text/plain" \
    --data-binary @- "${PUSH_URL}" 2>&1 | sed 's/^/[push-session-metrics] /' >&2; then
  echo "[push-session-metrics] Metrics pushed successfully." >&2
else
  echo "[push-session-metrics] WARNING: curl failed — metrics not pushed (non-fatal)." >&2
fi

exit 0
