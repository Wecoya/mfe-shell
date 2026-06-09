#!/usr/bin/env bash
# .github/skills/pr-create/scripts/pr-create.sh
#
# Create a GitHub Pull Request for the autonomous agent pipeline.
# Works identically in GitHub Actions and in a local terminal.
#
# Usage:
#   pr-create.sh --branch <name> --issue <n> [--title <text>] [--draft true|false] [--base <ref>]
#   pr-create.sh                              # fully interactive local mode
#
# Output: PR number on stdout; diagnostics on stderr.

set -euo pipefail

BRANCH=""
ISSUE=""
TITLE=""
DRAFT="false"
BASE="main"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)  BRANCH="${2:-}";   shift 2 ;;
    --issue)   ISSUE="${2:-}";    shift 2 ;;
    --title)   TITLE="${2:-}";    shift 2 ;;
    --draft)   DRAFT="${2:-false}"; shift 2 ;;
    --base)    BASE="${2:-main}";  shift 2 ;;
    -h|--help) sed -n 's/^# //p' "$0" | head -10 >&2; exit 0 ;;
    *)         echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

IS_CI="${GITHUB_ACTIONS:-false}"

# ── Infer missing values in local mode ───────────────────────────────────────
if [[ -z "$BRANCH" ]]; then
  if [[ "$IS_CI" == "true" ]]; then
    echo "Error: --branch is required in CI mode." >&2; exit 1
  fi
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  echo "[pr-create] Inferred branch from HEAD: ${BRANCH}" >&2
fi

if [[ -z "$ISSUE" ]]; then
  if [[ "$IS_CI" == "true" ]]; then
    echo "Error: --issue is required in CI mode." >&2; exit 1
  fi
  # Try to extract issue number from branch name (feature/X.Y-...-<n> or issue-<n>)
  ISSUE=$(printf '%s' "$BRANCH" | grep -oE '\-([0-9]+)$' | tr -d '-' || true)
  if [[ -z "$ISSUE" && -t 0 ]]; then
    read -rp "[pr-create] GitHub issue number to close: " ISSUE
  fi
  ISSUE="${ISSUE:-}"
fi

# ── Default title from issue or commits ──────────────────────────────────────
if [[ -z "$TITLE" ]]; then
  if [[ -n "$ISSUE" ]] && command -v gh >/dev/null 2>&1; then
    ISSUE_TITLE=$(gh issue view "$ISSUE" --json title --jq '.title' 2>/dev/null || true)
    TASK_ID=$(printf '%s' "$ISSUE_TITLE" | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
    if [[ -n "$TASK_ID" ]]; then
      TITLE="feat(agent): task ${TASK_ID} autonomous implementation"
    else
      TITLE="feat(agent): autonomous implementation (issue #${ISSUE})"
    fi
  else
    TITLE="feat(agent): $(git log --no-merges --pretty=format:'%s' "${BASE}..${BRANCH}" | head -1 2>/dev/null || echo "automated changes")"
  fi
fi

# ── Idempotency: check for existing open PR ───────────────────────────────────
existing=$(gh pr list --head "$BRANCH" --base "$BASE" --state open --json number,url --jq '.[0] // empty' 2>/dev/null || true)
if [[ -n "$existing" ]]; then
  existing_num=$(printf '%s' "$existing" | jq -r '.number')
  existing_url=$(printf '%s' "$existing" | jq -r '.url')
  echo "[pr-create] Reusing existing PR #${existing_num}: ${existing_url}" >&2
  if [[ -n "$ISSUE" ]]; then
    gh issue comment "$ISSUE" --body "🤖 Reusing existing agent PR: ${existing_url}" >/dev/null 2>&1 || true
  fi
  echo "$existing_num"
  exit 0
fi

# ── Build PR body ─────────────────────────────────────────────────────────────
commits=$(git log --no-merges --pretty=format:'- %s' "${BASE}..${BRANCH}" 2>/dev/null || true)
[[ -z "$commits" ]] && commits="- Automated changes committed by coding agent"

# Check if an openspec change dir exists for this branch
task_id_from_branch=$(printf '%s' "$BRANCH" | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
openspec_section=""
if [[ -n "$task_id_from_branch" ]]; then
  change_dir=$(find openspec/changes -maxdepth 1 -type d -name "task-${task_id_from_branch}-*" 2>/dev/null | head -1 || true)
  if [[ -n "$change_dir" && -f "${change_dir}/tasks.md" ]]; then
    openspec_section="
## OpenSpec Change
\`${change_dir}/\`

$(cat "${change_dir}/tasks.md" 2>/dev/null | head -20)"
  fi
fi

closes_line=""
[[ -n "$ISSUE" ]] && closes_line="Closes #${ISSUE}"

body_file=$(mktemp)
trap 'rm -f "$body_file"' EXIT

cat > "$body_file" <<BODY
## Summary

${commits}

## Related Issue
${closes_line}
${openspec_section}

## Checklist
- [ ] Tests pass
- [ ] Docs updated (auto: finalize runs on merge)
- [ ] No plaintext secrets
- [ ] Security scan clean
BODY

# ── Create PR ─────────────────────────────────────────────────────────────────
args=(
  --head "$BRANCH"
  --base "$BASE"
  --title "$TITLE"
  --body-file "$body_file"
  --assignee "@me"
)
[[ "$DRAFT" == "true" ]] && args+=(--draft)

echo "[pr-create] Creating PR: ${TITLE}" >&2
pr_url=$(gh pr create "${args[@]}")
pr_number=$(printf '%s' "$pr_url" | grep -oE '[0-9]+$')

echo "[pr-create] Created PR #${pr_number}: ${pr_url}" >&2

if [[ -n "$ISSUE" ]]; then
  gh issue comment "$ISSUE" \
    --body "🤖 **Autonomous agent opened a PR:** ${pr_url}" >/dev/null 2>&1 || true
fi

echo "$pr_number"
