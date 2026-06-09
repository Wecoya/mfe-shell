---
name: task-start
description: Move a task to "In Progress" status in both the repository (docs/tasks/) and GitHub Project Board. Idempotent - safe to call multiple times.
---

# task-start Skill

**Description:** Move a task to "In Progress" status in both the repository (docs/tasks/) and GitHub Project Board. Idempotent - safe to call multiple times.

**Use when:** Starting work on a task via `iac:execute` or any other workflow that begins task implementation.

---

## Skill Overview

This skill automates the task lifecycle transition to "In Progress" per TASKING_RULES.md:

1. ✅ Move task file from Backlog/Ready → `docs/tasks/In Progress/`
2. ✅ Assign GitHub Issue to current user
3. ✅ Update GitHub Project Board to "In progress" status
4. ✅ Update `github_issue_mapping.md` with new path
5. ✅ Commit the status change
6. ✅ Verify all updates succeeded

**Critical:** This skill is **idempotent** - it checks current state before each action and skips operations already completed.

---

## Usage

```bash
# From any prompt that starts task work:
@task-start --task-id={{task_id}}

# Or with task file name:
@task-start --task-file="2.4.5_refactor_id_passing.md"
```

---

## Implementation Steps

### Step 1: Identify Task File (Idempotent Discovery)

```bash
# Find task file in any status folder (Backlog, Ready, In Progress, Done)
TASK_FILE=$(find docs/tasks/ -name "*{{task_id}}*.md" -o -name "{{task_file}}" 2>/dev/null | head -1)

if [ -z "$TASK_FILE" ]; then
  echo "❌ ERROR: Task file not found for {{task_id}}"
  exit 1
fi

TASK_BASENAME=$(basename "$TASK_FILE")
CURRENT_DIR=$(dirname "$TASK_FILE")

echo "📋 Found task: $TASK_FILE"
echo "📂 Current location: $CURRENT_DIR"
```

### Step 2: Check Current State (Idempotency Check)

```bash
# Check if already in "In Progress"
if [[ "$CURRENT_DIR" == *"In Progress"* ]]; then
  echo "✅ Task already in 'In Progress' - skipping file move"
  SKIP_FILE_MOVE=true
else
  echo "📦 Task needs to be moved to In Progress"
  SKIP_FILE_MOVE=false
fi
```

### Step 3: Move Task File (Conditional)

```bash
if [ "$SKIP_FILE_MOVE" = false ]; then
  # Ensure In Progress folder exists
  mkdir -p "docs/tasks/In Progress/"

  # Move task to In Progress
  mv "$TASK_FILE" "docs/tasks/In Progress/$TASK_BASENAME"

  echo "✅ Moved task to In Progress: docs/tasks/In Progress/$TASK_BASENAME"
  TASK_FILE="docs/tasks/In Progress/$TASK_BASENAME"
else
  echo "⏭️  File already in correct location"
fi
```

### Step 4: Assign GitHub Issue to Current User + Update Board (Idempotent)

> Uses **[`gh-issue` skill](../gh-issue/SKILL.md)** scripts for all GitHub operations.

```bash
GH_ISSUE_SCRIPTS=".github/skills/gh-issue/scripts"

# Read GitHub issue number from mapping
if [ -f docs/tasks/github_issue_mapping.md ]; then
  ISSUE_NUM=$(grep "$TASK_BASENAME" docs/tasks/github_issue_mapping.md | \
    grep -oE '(issues/[0-9]+|\[#([0-9]+)\])' | head -1 | grep -oE '[0-9]+')
fi

if [ -n "${ISSUE_NUM:-}" ]; then
  echo "🔗 Found GitHub Issue: #$ISSUE_NUM"

  # Assign to current user (@me)
  CURRENT_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")
  CURRENT_ASSIGNEE=$(gh issue view "$ISSUE_NUM" \
    --repo Wecoya/private-sovereign-cloud \
    --json assignees \
    --jq '.assignees[0].login' 2>/dev/null || echo "")

  if [ "$CURRENT_ASSIGNEE" != "$CURRENT_USER" ]; then
    gh issue edit "$ISSUE_NUM" \
      --add-assignee @me \
      --repo Wecoya/private-sovereign-cloud
    echo "✅ Assigned issue #$ISSUE_NUM to @me ($CURRENT_USER)"
  else
    echo "✅ Issue already assigned to current user"
  fi
else
  echo "⚠️  No GitHub issue found in mapping for $TASK_BASENAME"
fi
```

### Step 5: Update GitHub Project Board (Idempotent)

```bash
if [ -n "${ISSUE_NUM:-}" ]; then
  # Ensure issue is on the board, then move to "In progress" column
  $GH_ISSUE_SCRIPTS/board-add.sh    --issue "$ISSUE_NUM"
  $GH_ISSUE_SCRIPTS/board-status.sh --issue "$ISSUE_NUM" --status "In progress"
fi
```

### Step 6: Update Mapping File (Conditional)

```bash
if [ -f docs/tasks/github_issue_mapping.md ]; then
  # Check if mapping already shows In Progress path
  CURRENT_MAPPING=$(grep "$TASK_BASENAME" docs/tasks/github_issue_mapping.md)

  if [[ "$CURRENT_MAPPING" != *"In Progress"* ]]; then
    # Update path to In Progress
    sed -i.bak "s|docs/tasks/[^/]*/\"$TASK_BASENAME\"|docs/tasks/In Progress/\"$TASK_BASENAME\"|g" \
      docs/tasks/github_issue_mapping.md
    rm docs/tasks/github_issue_mapping.md.bak 2>/dev/null || true

    echo "✅ Updated github_issue_mapping.md with In Progress path"
  else
    echo "✅ Mapping already shows In Progress path"
  fi
fi
```

### Step 7: Commit Changes (Conditional)

```bash
# Check if there are changes to commit
if git diff --quiet docs/tasks/ && git diff --cached --quiet docs/tasks/; then
  echo "✅ No changes to commit - task already in desired state"
else
  # Commit task status change
  git add docs/tasks/
  git add docs/tasks/github_issue_mapping.md 2>/dev/null || true

  git commit -m "chore(tasks): move {{task_id}} to In Progress

Starting work on task {{task_id}}: $TASK_BASENAME

GitHub Issue: #${ISSUE_NUM:-N/A}"

  git push

  echo "✅ Committed and pushed task status change"
fi
```

### Step 8: Verification

```bash
echo ""
echo "═══════════════════════════════════════════"
echo "✅ Task Start Complete - Verification"
echo "═══════════════════════════════════════════"
echo ""

# Verify task file location
if [ -f "docs/tasks/In Progress/$TASK_BASENAME" ]; then
  echo "✅ Task file: docs/tasks/In Progress/$TASK_BASENAME"
else
  echo "❌ Task file not found in In Progress!"
fi

# Verify GitHub issue status
if [ -n "$ISSUE_NUM" ]; then
  ISSUE_STATE=$(gh issue view "$ISSUE_NUM" --repo Wecoya/<your-repo> --json state,assignees --jq '.state + " | Assignee: " + .assignees[0].login' 2>/dev/null)
  echo "✅ GitHub Issue #$ISSUE_NUM: $ISSUE_STATE"

  # Verify project board status
  PROJECT_STATUS=$(gh project item-list 2 --owner Wecoya --format json --limit 100 2>/dev/null | \
    jq -r ".items[] | select(.content.number == $ISSUE_NUM) | .status")
  echo "✅ GitHub Project status: $PROJECT_STATUS"
fi

echo ""
echo "🚀 Ready to start implementation!"
```

---

## Error Handling

- **Task file not found:** Exit with error message
- **GitHub CLI not available:** Continue with file operations only, warn about GitHub sync skipped
- **GitHub API errors:** Log warning but don't fail (file operations are source of truth)
- **Already in desired state:** Skip operations, report success

---

## Integration with Prompts

In `iac:execute.prompt.md`:

```markdown
### 1.3 Move Task to In Progress (when user confirms start)

**Use the task-start skill:**

```bash
@task-start --task-id={{task_id}}
```

This skill is idempotent - safe to call multiple times.
```

---

## Dependencies

- Git repository with docs/tasks/ structure
- GitHub CLI (`gh`) installed and authenticated (optional)
- docs/tasks/github_issue_mapping.md file (optional)
- GitHub Project #2 configured per TASKING_RULES.md (optional)

**Note:** GitHub operations are optional. The skill will work with file operations only if GitHub CLI is unavailable.
