#!/usr/bin/env bash
# .github/skills/finalize/scripts/finalize.sh
#
# Post-merge finalization for the autonomous agent pipeline.
# Triggered by pull_request.closed (merged) in agent-run.yml.
# Also runnable locally after a branch is merged.
#
# Steps:
#   1. Detect the merged PR context (branch, task ID, issue number)
#   2. Archive the openspec change directory -> openspec/archived/<name>/
#   3. Move the task file from In Progress/ -> Done/ (if docs/tasks exists)
#   4. Close the GitHub Issue with a completion comment
#   5. Commit and push all docs changes back to the base branch
#
# Usage (all values auto-detected in GHA; pass flags for local use):
#   finalize.sh [--pr <n>] [--issue <n>] [--task-id <x.y>] [--base <ref>]

set -euo pipefail

PR_NUMBER="${PR_NUMBER:-}"
ISSUE_NUMBER="${ISSUE_NUMBER:-}"
TASK_ID="${TASK_ID:-}"
BASE="main"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)       PR_NUMBER="${2:-}";    shift 2 ;;
    --issue)    ISSUE_NUMBER="${2:-}"; shift 2 ;;
    --task-id)  TASK_ID="${2:-}";      shift 2 ;;
    --base)     BASE="${2:-main}";     shift 2 ;;
    -h|--help)  sed -n 's/^# //p' "$0" | head -15 >&2; exit 0 ;;
    *)          echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

IS_CI="${GITHUB_ACTIONS:-false}"

# ── Step 0: Resolve context ───────────────────────────────────────────────────
echo "[finalize] Starting finalization..." >&2

# In GHA the PR event populates these env vars:
if [[ -z "$PR_NUMBER" ]]; then
  PR_NUMBER="${GITHUB_REF_NAME:-}"
  PR_NUMBER=$(printf '%s' "${GITHUB_REF:-}" | grep -oE '[0-9]+' | head -1 || true)
fi

# If ISSUE_NUMBER not provided, extract from PR body ("Closes #N")
if [[ -z "$ISSUE_NUMBER" && -n "$PR_NUMBER" ]]; then
  ISSUE_NUMBER=$(gh pr view "$PR_NUMBER" --json body --jq '.body' 2>/dev/null \
    | grep -oiE 'closes? #[0-9]+' | grep -oE '[0-9]+' | head -1 || true)
fi

# Get the head branch of the merged PR
MERGED_BRANCH=""
if [[ -n "$PR_NUMBER" ]]; then
  MERGED_BRANCH=$(gh pr view "$PR_NUMBER" --json headRefName --jq '.headRefName' 2>/dev/null || true)
fi
[[ -z "$MERGED_BRANCH" ]] && MERGED_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)

# Extract task ID from branch name if not already known
if [[ -z "$TASK_ID" ]]; then
  TASK_ID=$(printf '%s' "$MERGED_BRANCH" | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
fi

echo "[finalize] PR:${PR_NUMBER:-?} Issue:${ISSUE_NUMBER:-?} Task:${TASK_ID:-?} Branch:${MERGED_BRANCH:-?}" >&2

# ── Git config for commits ────────────────────────────────────────────────────
git config user.email "github-actions[bot]@users.noreply.github.com" 2>/dev/null || true
git config user.name  "github-actions[bot]" 2>/dev/null || true

# Ensure we are on the base branch (in GHA the finalize job checks out at merge SHA)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
if [[ "$CURRENT_BRANCH" != "$BASE" && "$IS_CI" == "true" ]]; then
  git checkout "$BASE" >/dev/null 2>&1 || true
  git pull origin "$BASE" >/dev/null 2>&1 || true
fi

# ── Step 1: Archive openspec change ──────────────────────────────────────────
_finalize_manual_archive() {
  local dir="$1"
  local name
  name=$(basename "$dir")
  local archive_dir="openspec/changes/archive/$(date +%Y-%m-%d)-${name}"
  mkdir -p "openspec/changes/archive"
  mv "$dir" "$archive_dir"
  echo "[finalize] Archived (manual): ${dir} -> ${archive_dir}" >&2
}

CHANGE_DIR=""
CHANGE_NAME=""
if [[ -n "$TASK_ID" ]]; then
  CHANGE_DIR=$(find openspec/changes -maxdepth 1 -type d -name "task-${TASK_ID}-*" 2>/dev/null | head -1 || true)
fi
if [[ -z "$CHANGE_DIR" && -n "$MERGED_BRANCH" ]]; then
  SLUG=$(printf '%s' "$MERGED_BRANCH" | sed 's|feature/||' | tr '/' '-')
  CHANGE_DIR=$(find openspec/changes -maxdepth 1 -type d -name "*${SLUG}*" 2>/dev/null | head -1 || true)
fi

if [[ -n "$CHANGE_DIR" && -d "$CHANGE_DIR" ]]; then
  CHANGE_NAME=$(basename "$CHANGE_DIR")

  if command -v openspec >/dev/null 2>&1; then
    # Preferred: use openspec CLI — archives to openspec/changes/archive/<date>-<name>/
    # --yes skips interactive prompts; --skip-specs avoids main-spec sync in CI context
    if openspec archive --yes --skip-specs "$CHANGE_NAME" 2>&1 | sed 's/^/[finalize:openspec] /' >&2; then
      echo "[finalize] openspec archive complete: ${CHANGE_NAME}" >&2
    else
      echo "[finalize] openspec archive failed for ${CHANGE_NAME}, falling back to manual move" >&2
      _finalize_manual_archive "$CHANGE_DIR"
    fi
  else
    # Fallback: openspec CLI not available (e.g. CI without Node install step)
    _finalize_manual_archive "$CHANGE_DIR"
  fi

  git add "openspec/" 2>/dev/null || git add -A openspec/ 2>/dev/null || true
else
  echo "[finalize] No openspec change found to archive (task-id: ${TASK_ID:-none})" >&2
fi

# ── Step 2: Move task file to Done ────────────────────────────────────────────
if [[ -d "docs/tasks" && -n "$TASK_ID" ]]; then
  TASK_FILE=$(find docs/tasks/In\ Progress docs/tasks/Ready docs/tasks/Backlog \
    -maxdepth 1 -type f -name "${TASK_ID}*.md" 2>/dev/null | head -1 || true)

  if [[ -n "$TASK_FILE" ]]; then
    mkdir -p "docs/tasks/Done"
    DEST="docs/tasks/Done/$(basename "$TASK_FILE")"
    mv "$TASK_FILE" "$DEST"
    echo "[finalize] Moved task: ${TASK_FILE} -> ${DEST}" >&2
    git add "docs/tasks/" 2>/dev/null || true
  else
    echo "[finalize] No task file found in In Progress/Ready/Backlog for ${TASK_ID}" >&2
  fi
fi

# ── Step 3: Update GitHub Issue ───────────────────────────────────────────────
if [[ -n "$ISSUE_NUMBER" ]] && command -v gh >/dev/null 2>&1; then
  PR_URL=""
  [[ -n "$PR_NUMBER" ]] && PR_URL=$(gh pr view "$PR_NUMBER" --json url --jq '.url' 2>/dev/null || true)

  COMMENT="✅ **Task completed and finalized.**

| Field | Value |
|---|---|
| Task | \`${TASK_ID:-unknown}\` |
| PR | ${PR_URL:-merged} |
| Branch | \`${MERGED_BRANCH:-unknown}\` |

Docs synced. OpenSpec change archived. Task moved to Done."

  gh issue comment "$ISSUE_NUMBER" --body "$COMMENT" >/dev/null 2>&1 || true
  gh issue close "$ISSUE_NUMBER" --reason completed 2>/dev/null || true
  echo "[finalize] Closed issue #${ISSUE_NUMBER}" >&2
fi

# ── Step 4: Domain cards update (if domain-orchestrator changes exist) ────────
if [[ -x ".github/skills/domains-update/scripts/domains-update.sh" ]]; then
  if git diff HEAD --name-only 2>/dev/null | grep -q 'domain-orchestrator/' ; then
    echo "[finalize] Updating domain wiki cards..." >&2
    bash ".github/skills/domains-update/scripts/domains-update.sh" || true
  fi
fi

# ── Step 5: Commit and push docs changes ─────────────────────────────────────
git add -A 2>/dev/null || true

if ! git diff --cached --quiet 2>/dev/null; then
  MSG="docs(finalize): archive change, close task ${TASK_ID:-unknown}, sync docs"
  [[ -n "$ISSUE_NUMBER" ]] && MSG+=" [closes #${ISSUE_NUMBER}]"
  git commit -m "$MSG"
  # Explicitly inject token into remote URL so push succeeds even when the
  # actions/checkout credential store was flushed by npm/node tool installs.
  if [[ -n "${GITHUB_REPOSITORY:-}" && -n "${GH_TOKEN:-}" ]]; then
    git remote set-url origin \
      "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
  else
    echo "[finalize] WARNING: GH_TOKEN or GITHUB_REPOSITORY unset — push may fail with 403" >&2
  fi
  git push origin HEAD
  echo "[finalize] Docs committed and pushed." >&2
else
  echo "[finalize] No doc changes to commit." >&2
fi

# ── Step 6: Push session usage metrics ───────────────────────────────────────
# COPILOT_INPUT_TOKENS / COPILOT_OUTPUT_TOKENS / COPILOT_MODEL may be set by
# the agent wrapper before calling this script (see push-session-metrics SKILL.md).
METRICS_SCRIPT=".github/skills/push-session-metrics/scripts/push-session-metrics.sh"
if [[ -x "$METRICS_SCRIPT" ]]; then
  bash "$METRICS_SCRIPT" \
    ${TASK_ID:+--task-id "$TASK_ID"} \
    ${COPILOT_MODEL:+--model "$COPILOT_MODEL"} \
    ${COPILOT_INPUT_TOKENS:+--input-tokens "$COPILOT_INPUT_TOKENS"} \
    ${COPILOT_OUTPUT_TOKENS:+--output-tokens "$COPILOT_OUTPUT_TOKENS"} \
    ${COPILOT_USER:+--user "$COPILOT_USER"} \
    ${COPILOT_REASON:+--reason "$COPILOT_REASON"} \
    ${COPILOT_SESSION_ID:+--session-id "$COPILOT_SESSION_ID"} \
    ${COPILOT_CREDITS:+--credits "$COPILOT_CREDITS"} \
    || true
fi

echo "[finalize] Done." >&2
