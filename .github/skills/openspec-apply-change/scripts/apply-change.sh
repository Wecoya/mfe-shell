#!/usr/bin/env bash
# .github/skills/openspec-apply-change/scripts/apply-change.sh
#
# Coding step for the autonomous agent pipeline.
# Reads the OpenSpec change (proposal.md + design.md + tasks.md) and calls a
# coding engine to produce real file changes on the current branch.
#
# Engine priority:
#   1. github/copilot-coding-agent@v1  — handled upstream as a 'uses:' step
#   2. GitHub Copilot chat completions API  (non-interactive; CI + local)
#   3. gh copilot suggest              — interactive local session
#   4. Scaffold commit                 — deterministic fallback
#
# This script implements engines 2-4.
#
# Required env vars:
#   CHANGE_NAME    openspec change directory name under openspec/changes/
#   ISSUE_NUMBER   GitHub issue number
#   TASK_ID        task identifier (x.y)
#   GH_TOKEN       token with repo write access
#
# Optional:
#   COPILOT_DRY_RUN=true  print the generated script without executing it

set -euo pipefail

CHANGE_NAME="${CHANGE_NAME:-}"
ISSUE_NUMBER="${ISSUE_NUMBER:-}"
TASK_ID="${TASK_ID:-}"
IS_CI="${GITHUB_ACTIONS:-false}"
DRY_RUN="${COPILOT_DRY_RUN:-false}"

# ── Validate inputs ────────────────────────────────────────────────────────────
if [[ -z "$CHANGE_NAME" && -n "$TASK_ID" ]]; then
  CHANGE_NAME=$(find openspec/changes -maxdepth 1 -type d -name "task-${TASK_ID}-*" 2>/dev/null \
    | head -1 | xargs basename 2>/dev/null || true)
fi

if [[ -z "$CHANGE_NAME" ]]; then
  echo "[apply-change] Error: CHANGE_NAME not set and no matching change dir found." >&2
  exit 1
fi

CHANGE_DIR="openspec/changes/${CHANGE_NAME}"
TASKS_FILE="${CHANGE_DIR}/tasks.md"

if [[ ! -f "$TASKS_FILE" ]]; then
  echo "[apply-change] Error: tasks.md not found at ${TASKS_FILE}" >&2
  exit 1
fi

# ── Build structured prompt ────────────────────────────────────────────────────
PROPOSAL=$(cat "${CHANGE_DIR}/proposal.md" 2>/dev/null || echo "No proposal.")
DESIGN=$(cat "${CHANGE_DIR}/design.md"   2>/dev/null || echo "No design.")
TASKS=$(cat "$TASKS_FILE")

read -r -d '' SYSTEM_PROMPT << 'SYS' || true
You are a senior software engineer working on a GitOps platform project (NestJS, TypeScript, YAML, Kubernetes).
Your output must be ONLY a valid bash script, no markdown fences, no explanations.
The script will be executed directly. It must:
  - Start with #!/usr/bin/env bash and set -euo pipefail
  - Create or modify files using heredocs (cat > path/to/file <<'EOF' ... EOF)
  - Run existing test commands when possible (npm test, jest, etc.)
  - Use conventional commit messages in any git commit calls
  - NOT push, NOT create PRs, NOT call GitHub APIs
SYS

USER_PROMPT="Implement the following tasks for issue #${ISSUE_NUMBER} (task ${TASK_ID}).

## Proposal
${PROPOSAL}

## Design
${DESIGN}

## Tasks (implement every unchecked item)
${TASKS}

Output a complete bash implementation script."

# ── Helper: authenticated git push ────────────────────────────────────────────
# Injects the token into the remote URL before pushing so the push succeeds
# even when npm/node tooling flushes the actions/checkout credential store.
_inject_git_token() {
  if [[ -n "${GITHUB_REPOSITORY:-}" && -n "${GH_TOKEN:-}" ]]; then
    git remote set-url origin \
      "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
  else
    echo "[apply-change] WARNING: GH_TOKEN or GITHUB_REPOSITORY unset — push may fail with 403" >&2
  fi
}

# ── Engine 2: GitHub Copilot API (non-interactive) ────────────────────────────
_call_copilot_api() {
  local token
  token=$(gh auth token 2>/dev/null || true)
  [[ -z "$token" ]] && return 1

  local payload
  payload=$(jq -cn \
    --arg sys "$SYSTEM_PROMPT" \
    --arg usr "$USER_PROMPT" \
    '{
      "model": "gpt-4o",
      "temperature": 0.2,
      "messages": [
        {"role": "system", "content": $sys},
        {"role": "user",   "content": $usr}
      ]
    }')

  local response
  # Try GitHub Copilot API first, then GitHub Models as fallback
  for endpoint in \
      "https://api.githubcopilot.com/chat/completions" \
      "https://models.inference.ai.azure.com/chat/completions"; do
    response=$(curl -sf \
      --max-time 120 \
      -X POST "$endpoint" \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      -d "$payload" 2>/dev/null || true)

    if [[ -n "$response" ]]; then
      local content
      content=$(printf '%s' "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null || true)
      if [[ -n "$content" ]]; then
        printf '%s' "$content"
        return 0
      fi
    fi
  done
  return 1
}

_apply_generated_script() {
  local raw_script="$1"

  # Strip markdown code fences if Copilot wrapped the output
  local clean_script
  if printf '%s' "$raw_script" | grep -q '```'; then
    clean_script=$(printf '%s' "$raw_script" \
      | sed -n '/^```\(bash\|sh\)\?/,/^```/p' \
      | grep -v '^```')
  else
    clean_script="$raw_script"
  fi

  # Must look like a real bash script
  if ! printf '%s' "$clean_script" | head -1 | grep -qE '^#!'; then
    # Prepend shebang if missing
    clean_script=$'#!/usr/bin/env bash\nset -euo pipefail\n'"$clean_script"
  fi

  local impl_script="${CHANGE_DIR}/implement.sh"
  printf '%s\n' "$clean_script" > "$impl_script"
  chmod +x "$impl_script"
  echo "[apply-change] Implementation script written: ${impl_script}" >&2

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[apply-change] DRY_RUN=true — printing script, not executing:" >&2
    cat "$impl_script"
    return 0
  fi

  echo "[apply-change] Executing implementation script..." >&2
  bash "$impl_script"

  # Mark all tasks as done
  sed -i -E 's/^- \[ \] /- [x] /' "$TASKS_FILE" 2>/dev/null || true

  git config user.email "github-actions[bot]@users.noreply.github.com" 2>/dev/null || true
  git config user.name  "github-actions[bot]" 2>/dev/null || true
  git add -A
  if ! git diff --cached --quiet; then
    git commit -m "feat(agent): implement task ${TASK_ID} via Copilot (issue #${ISSUE_NUMBER})"
  fi
  _inject_git_token
  git push origin HEAD

  if [[ -n "$ISSUE_NUMBER" ]]; then
    gh issue comment "$ISSUE_NUMBER" \
      --body "🤖 **Coding step completed via GitHub Copilot API**

Implementation script: \`${impl_script}\`

All tasks checked off. PR will be created momentarily." >/dev/null 2>&1 || true
  fi
}

echo "[apply-change] Trying GitHub Copilot API..." >&2
if generated=$(_call_copilot_api); then
  _apply_generated_script "$generated"
  exit 0
fi
echo "[apply-change] Copilot API unavailable or returned empty." >&2
if [[ -n "$ISSUE_NUMBER" ]]; then
  gh issue comment "$ISSUE_NUMBER" \
    --body "⚠️ **Copilot API unavailable** — falling through to scaffold mode.

The coding step attempted the GitHub Copilot completions API but received no usable response.
The agent will proceed with a scaffold commit. Re-trigger with \`/agent-start\` once a coding engine is configured." \
    >/dev/null 2>&1 || true
fi

# ── Engine 3: gh copilot suggest (interactive local sessions) ─────────────────
if [[ -t 0 && "$IS_CI" != "true" ]] \
    && command -v gh >/dev/null 2>&1 \
    && gh extension list 2>/dev/null | grep -q 'copilot'; then

  echo "" >&2
  echo "══════════════════════════════════════════════════════" >&2
  echo " Interactive: gh copilot suggest" >&2
  echo " Review the suggestion and apply the commands manually." >&2
  echo "══════════════════════════════════════════════════════" >&2
  echo "" >&2

  gh copilot suggest -t shell \
    "Implement the following tasks in this git repo: ${TASKS}"

  echo "" >&2
  read -rp "[apply-change] Apply the suggestion above? (y/N): " answer
  if [[ "${answer,,}" == "y" ]]; then
    echo "Copy the commands into your terminal and run them manually." >&2
  fi
  exit 0
fi

# ── Engine 4: Scaffold fallback ────────────────────────────────────────────────
# ── STUB: begin replacement block ─────────────────────────────────────────────
# Replace everything from this comment to "STUB: end replacement block" with a
# real LLM coding engine. The scaffold below lets the full pipeline run today
# without an LLM; it commits the openspec change directory as-is so pr-create
# can open a PR and the human can fill in the implementation.
#
# To wire in a real engine, replace this block with one of:
#   a) GitHub Copilot completions API (see _call_copilot_api above)
#   b) GitHub Models REST endpoint — same shape as Copilot API
#   c) Any other LLM that returns a bash implementation script
#   Pattern: generate script → write to tmp file → call _apply_generated_script
echo "[apply-change] No coding engine available — committing scaffold (STUB)." >&2

git config user.email "github-actions[bot]@users.noreply.github.com" 2>/dev/null || true
git config user.name  "github-actions[bot]" 2>/dev/null || true
git add "${CHANGE_DIR}/"
if ! git diff --cached --quiet; then
  git commit -m "feat(agent): scaffold openspec change for task ${TASK_ID} (issue #${ISSUE_NUMBER})"
fi
_inject_git_token
git push origin HEAD

if [[ -n "$ISSUE_NUMBER" ]]; then
  gh issue comment "$ISSUE_NUMBER" \
    --body "🤖 **Agent ran in scaffold mode**

No LLM coding engine was available (Copilot API unreachable, no interactive session).
The OpenSpec change has been scaffolded:

\`\`\`
${CHANGE_DIR}/
  proposal.md   ← what & why
  design.md     ← architecture (TODO: fill in)
  tasks.md      ← checklist
\`\`\`

**To continue:**  implement the tasks locally, or wait for the coding agent and re-trigger with \`/agent-start\`." \
    >/dev/null 2>&1 || true
fi
# ── STUB: end replacement block ───────────────────────────────────────────────

exit 0
