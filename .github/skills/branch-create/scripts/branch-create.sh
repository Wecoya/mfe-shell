#!/usr/bin/env bash
# .github/skills/branch-create/scripts/branch-create.sh
#
# Create and push a feature branch for the autonomous agent pipeline.
# Works identically in GitHub Actions and in a local terminal.
#
# Usage (all flags optional in local mode — values inferred from git/GH):
#   branch-create.sh --issue <n> --task-id <x.y> --title <text> [--base <ref>] [--dry-run]
#
# Output: branch name on stdout; diagnostics on stderr.

set -euo pipefail

ISSUE=""
TASK_ID=""
TITLE=""
BASE="main"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)    ISSUE="${2:-}";    shift 2 ;;
    --task-id)  TASK_ID="${2:-}";  shift 2 ;;
    --title)    TITLE="${2:-}";    shift 2 ;;
    --base)     BASE="${2:-main}"; shift 2 ;;
    --dry-run)  DRY_RUN=true;      shift   ;;
    -h|--help)
      sed -n 's/^# //p' "$0" | head -10 >&2; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

IS_CI="${GITHUB_ACTIONS:-false}"

# ── Infer missing values in local mode ───────────────────────────────────────
if [[ -z "$ISSUE" ]]; then
  if [[ "$IS_CI" == "true" ]]; then
    echo "Error: --issue is required in CI mode." >&2; exit 1
  fi
  if [[ -t 0 ]]; then
    read -rp "[branch-create] GitHub issue number (blank = date-based): " ISSUE
  fi
  ISSUE="${ISSUE:-0}"
fi

if [[ -z "$TITLE" && "$ISSUE" != "0" ]] && command -v gh >/dev/null 2>&1; then
  echo "[branch-create] Fetching issue #${ISSUE} title..." >&2
  TITLE=$(gh issue view "$ISSUE" --json title --jq '.title' 2>/dev/null || true)
fi
[[ -z "$TITLE" ]] && TITLE="issue-${ISSUE}"

if [[ -z "$TASK_ID" ]]; then
  TASK_ID=$(printf '%s' "$TITLE" | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
fi

# ── Build branch name ─────────────────────────────────────────────────────────
slug=$(printf '%s' "$TITLE" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g' \
  | sed -E 's/^-+|-+$//g' \
  | sed -E 's/-+/-/g' \
  | cut -c1-60)
[[ -z "$slug" ]] && slug="issue-${ISSUE}"

if [[ -n "$TASK_ID" ]]; then
  BRANCH="feature/${TASK_ID}-${slug}"
else
  BRANCH="feature/${slug}"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[dry-run] branch: ${BRANCH}" >&2
  echo "$BRANCH"
  exit 0
fi

# ── Create / checkout / push ──────────────────────────────────────────────────
git fetch origin "$BASE" >/dev/null 2>&1

if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  echo "[branch-create] Reusing local branch: ${BRANCH}" >&2
  git checkout "$BRANCH" >/dev/null 2>&1
elif git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  echo "[branch-create] Reusing remote branch: ${BRANCH}" >&2
  git checkout -b "$BRANCH" "origin/$BRANCH" >/dev/null 2>&1
else
  echo "[branch-create] Creating from ${BASE}: ${BRANCH}" >&2
  git checkout -b "$BRANCH" "origin/$BASE" >/dev/null 2>&1
fi

git push -u origin "$BRANCH" >/dev/null 2>&1
echo "[branch-create] Pushed: ${BRANCH}" >&2
echo "$BRANCH"
