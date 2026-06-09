---
name: task-complete
description: Move a task to "Done" status and close the corresponding GitHub Issue. Idempotent - safe to call multiple times.
---

# task-complete Skill

**Description:** Move a task to "Done" status and close the corresponding GitHub Issue. Idempotent - safe to call multiple times.

**Use when:** Finalizing a completed feature via `finalize` prompt or any workflow that marks work as complete.

---

## Skill Overview

This skill automates the task lifecycle completion per TASKING_RULES.md:

1. ✅ Move task file to `docs/tasks/Done/`
2. ✅ Close GitHub Issue with completion comment
3. ✅ Update GitHub Project Board to "Done" status
4. ✅ Update `github_issue_mapping.md` with new path
5. ✅ Commit the status change
6. ✅ Verify all updates succeeded

**Critical:** This skill is **idempotent** - it checks current state before each action and skips operations already completed.

---

## Usage

```bash
# From finalize prompt or completion workflow:
@task-complete --task-id={{task_id}} --feature={{feature_name}}

# Or with task file name:
@task-complete --task-file="2.4.5_refactor_id_passing.md" --feature="id-passing-refactor"
```

---

## Implementation Steps

### Step 1: Identify Task File (Idempotent Discovery)

```bash
# Find task file in any status folder (prioritize In Progress, Ready, Backlog)
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
# Check if already in "Done"
if [[ "$CURRENT_DIR" == *"Done"* ]]; then
  echo "✅ Task already in 'Done' - skipping file move"
  SKIP_FILE_MOVE=true
else
  echo "📦 Task needs to be moved to Done"
  SKIP_FILE_MOVE=false
fi
```

### Step 3: Move Task File to Done (Conditional)

```bash
if [ "$SKIP_FILE_MOVE" = false ]; then
  # Ensure Done folder exists
  mkdir -p "docs/tasks/Done/"

  # Move task to Done
  mv "$TASK_FILE" "docs/tasks/Done/$TASK_BASENAME"

  echo "✅ Moved task to Done: docs/tasks/Done/$TASK_BASENAME"
  TASK_FILE="docs/tasks/Done/$TASK_BASENAME"
else
  echo "⏭️  File already in correct location"
fi
```

### Step 4: Close GitHub Issue (Idempotent)

```bash
# Read GitHub issue number from mapping
if [ -f docs/tasks/github_issue_mapping.md ]; then
  ISSUE_NUM=$(grep "$TASK_BASENAME" docs/tasks/github_issue_mapping.md | \
    grep -oE '#[0-9]+' | sed 's/#//' | head -1)

  if [ -n "$ISSUE_NUM" ]; then
    echo "🔗 Found GitHub Issue: #$ISSUE_NUM"

    # Check current issue state
    ISSUE_STATE=$(gh issue view "$ISSUE_NUM" --repo Wecoya/<your-repo> --json state --jq '.state' 2>/dev/null)

    if [ "$ISSUE_STATE" != "CLOSED" ]; then
      # Prepare completion comment
      COMPLETION_COMMENT="✅ Completed and finalized.

Implementation summary: docs/implementations/{{feature}}-summary.md
Documentation updated: docs/ARCHITECTURE.md

All tests passing. Ready for deployment."

      # Close the issue
      gh issue close "$ISSUE_NUM" \
        --repo Wecoya/<your-repo> \
        --comment "$COMPLETION_COMMENT" 2>/dev/null

      echo "✅ Closed GitHub Issue #$ISSUE_NUM"
    else
      echo "✅ Issue already closed"
    fi
  else
    echo "⚠️  No GitHub issue found in mapping for $TASK_BASENAME"
    ISSUE_NUM=""
  fi
else
  echo "⚠️  github_issue_mapping.md not found - skipping GitHub sync"
  ISSUE_NUM=""
fi
```

### Step 5: Update GitHub Project Board to Done (Idempotent)

```bash
if [ -n "$ISSUE_NUM" ]; then
  # Get project item ID
  ITEM_ID=$(gh project item-list 2 --owner Wecoya --format json --limit 100 2>/dev/null | \
    jq -r ".items[] | select(.content.number == $ISSUE_NUM) | .id")

  if [ -n "$ITEM_ID" ]; then
    # Check current status
    CURRENT_STATUS=$(gh project item-list 2 --owner Wecoya --format json --limit 100 2>/dev/null | \
      jq -r ".items[] | select(.content.number == $ISSUE_NUM) | .status")

    if [ "$CURRENT_STATUS" != "Done" ]; then
      # Move to "Done" column (ID: 98236657)
      gh project item-edit \
        --id "$ITEM_ID" \
        --project-id "PVT_kwDODad2uc4BDObK" \
        --field-id "PVTSSF_lADODad2uc4BDObKzg1NL2w" \
        --single-select-option-id "98236657" 2>/dev/null

      echo "✅ Moved GitHub Project item to 'Done'"
    else
      echo "✅ Project item already in 'Done'"
    fi
  else
    echo "⚠️  Issue #$ISSUE_NUM not found in GitHub Project"
  fi
fi
```

### Step 6: Update Mapping File (Conditional)

```bash
if [ -f docs/tasks/github_issue_mapping.md ]; then
  # Check if mapping already shows Done path
  CURRENT_MAPPING=$(grep "$TASK_BASENAME" docs/tasks/github_issue_mapping.md)

  if [[ "$CURRENT_MAPPING" != *"Done"* ]]; then
    # Update path to Done
    sed -i.bak "s|docs/tasks/[^/]*/\"$TASK_BASENAME\"|docs/tasks/Done/\"$TASK_BASENAME\"|g" \
      docs/tasks/github_issue_mapping.md
    rm docs/tasks/github_issue_mapping.md.bak 2>/dev/null || true

    echo "✅ Updated github_issue_mapping.md with Done path"
  else
    echo "✅ Mapping already shows Done path"
  fi
fi
```

### Step 7: Commit Changes (Conditional)

```bash
# Check if there are changes to commit
if git diff --quiet docs/tasks/ && git diff --cached --quiet docs/tasks/; then
  echo "✅ No changes to commit - task already in desired state"
else
  # Commit task completion
  git add docs/tasks/
  git add docs/tasks/github_issue_mapping.md 2>/dev/null || true

  git commit -m "chore(tasks): move {{task_id}} to Done

Completed task {{task_id}}: $TASK_BASENAME

GitHub Issue: #${ISSUE_NUM:-N/A}
Feature: {{feature}}"

  git push

  echo "✅ Committed and pushed task completion"
fi
```

### Step 8: Verification

```bash
echo ""
echo "═══════════════════════════════════════════"
echo "✅ Task Complete - Verification"
echo "═══════════════════════════════════════════"
echo ""

# Verify task file location
if [ -f "docs/tasks/Done/$TASK_BASENAME" ]; then
  echo "✅ Task file: docs/tasks/Done/$TASK_BASENAME"
else
  echo "❌ Task file not found in Done!"
fi

# Verify GitHub issue status
if [ -n "$ISSUE_NUM" ]; then
  ISSUE_INFO=$(gh issue view "$ISSUE_NUM" --repo Wecoya/<your-repo> --json state,closedAt --jq '.state + " | Closed: " + .closedAt' 2>/dev/null)
  echo "✅ GitHub Issue #$ISSUE_NUM: $ISSUE_INFO"

  # Verify project board status
  PROJECT_STATUS=$(gh project item-list 2 --owner Wecoya --format json --limit 100 2>/dev/null | \
    jq -r ".items[] | select(.content.number == $ISSUE_NUM) | .status")
  echo "✅ GitHub Project status: $PROJECT_STATUS"
fi

echo ""
echo "🎉 Task successfully completed and closed!"
```

---

## Error Handling

- **Task file not found:** Exit with error message
- **GitHub CLI not available:** Continue with file operations only, warn about GitHub sync skipped
- **GitHub API errors:** Log warning but don't fail (file operations are source of truth)
- **Already in desired state:** Skip operations, report success
- **Issue already closed:** Skip close operation, still update project board if needed

---

## Integration with Prompts

In `finalize.prompt.md`:

```markdown
### 6.4 Move Tasks to Done & Close GitHub Issues

**Use the task-complete skill:**

```bash
@task-complete --task-id={{task_id}} --feature={{feature_name}}
```

This skill is idempotent - safe to call multiple times. It will:
- Move task file to Done folder
- Close GitHub Issue
- Update Project Board
- Commit changes
```

---

## Success Criteria

After running this skill:

- ✅ Task file located in `docs/tasks/Done/`
- ✅ GitHub Issue state: CLOSED
- ✅ GitHub Project Board column: "Done"
- ✅ Mapping file updated with Done path
- ✅ Changes committed to Git
- ✅ All verifications passed

---

## Dependencies

- Git repository with docs/tasks/ structure
- GitHub CLI (`gh`) installed and authenticated (optional)
- docs/tasks/github_issue_mapping.md file (optional)
- GitHub Project #2 configured per TASKING_RULES.md (optional)
- Implementation summary at docs/implementations/{{feature}}-summary.md (recommended)

**Note:** GitHub operations are optional. The skill will work with file operations only if GitHub CLI is unavailable.
