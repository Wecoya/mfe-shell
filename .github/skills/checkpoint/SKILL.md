---
name: checkpoint
description: Save session state and progress when context window is full, work is blocked, or you need to hand off. Use before switching contexts, when blocked, or after significant progress milestones.
---

# Checkpoint Skill

## When to Use This Skill

Use this skill when you need to preserve work state:

- ✅ **Context window approaching limit** (>150k tokens used)
- ✅ **Work is blocked** by external dependency or bug
- ✅ **Switching to different task** or role
- ✅ **Significant milestone reached** (e.g., 25%, 50%, 75% complete)
- ✅ **Handing off to another agent** or session
- ✅ **End of work session** with incomplete work
- ✅ **Before risky operation** (large refactor, breaking change)

**DO NOT use if:**
- ❌ Task is complete and ready to merge (use ship workflow instead)
- ❌ Just made one small change (commit is sufficient)
- ❌ Context window is still healthy (<100k tokens)

---

## Checkpoint Discipline Principle

> **Rule:** Preserve all discoveries, progress, and blockers so any session can pick up exactly where you left off.

**Why checkpoints matter:**
- Prevents loss of work due to context window overflow
- Enables seamless handoff between agents or sessions
- Documents decision rationale and technical discoveries
- Creates audit trail of implementation progress
- Allows graceful handling of blockers

---

## Workflow

### Step 1: Assess Checkpoint Need

Before creating a checkpoint, verify:

```yaml
Why am I checkpointing?
  - Context window full? → Checkpoint + continue in new session
  - Work blocked? → Checkpoint + report blocker
  - Natural breakpoint? → Checkpoint + continue or stop
  - Switching contexts? → Checkpoint + switch

What is the current state?
  - Tasks completed since last checkpoint: {{count}}
  - Active blockers: {{count}}
  - Files changed: {{count}}
  - Tests passing: {{percentage}}%

Is work in a safe state?
  - No syntax errors? YES → Continue
  - Tests that exist are passing? YES → Continue
  - Can build (even if incomplete)? OPTIONAL → Continue
```

### Step 2: Invoke Checkpoint Prompt

Call the `checkpoint` prompt to generate full session state:

```
@checkpoint --feature={{feature_name}}
```

This will:
1. Update `tasks.json` with current status
2. Generate `SESSION_STATE-{{feature}}.md`
3. Create checkpoint commit
4. Calculate progress metrics

### Step 3: Verify Checkpoint Completeness

After checkpoint prompt completes, verify:

```bash
# 1. SESSION_STATE exists and is complete
test -f docs/context/SESSION_STATE-{{feature}}.md && echo "✅ Session state created"

# 2. tasks.json has timestamps for completed tasks
jq '.tasks[] | select(.status == "completed" and .completedAt == null)' docs/context/tasks.json
# Expected: Empty output

# 3. Git commit was created
git log -1 --oneline | grep "checkpoint"
# Expected: Shows checkpoint commit

# 4. All work is committed or documented
git status --short
# Expected: Empty or only untracked temp files
```

### Step 4: Decide Next Action

**Based on why you checkpointed:**

```
Context Window Full?
  → Report to user: "Context window full. Created checkpoint. Ready to continue in new session."
  → User starts new session, agent reads SESSION_STATE to resume

Work Blocked?
  → Report blocker details
  → Ask user: "Fix blocker first, or skip to next task?"
  → Wait for decision

Natural Breakpoint?
  → Report progress
  → Ask user: "Continue with next phase, or stop here?"
  → Wait for decision

Switching Contexts?
  → Report: "Checkpoint created. Switching to {{new_context}}."
  → Load new context and continue

End of Session?
  → Report: "Work saved. Resume with: @{{execution_prompt}} --resume"
  → Stop
```

---

## Checkpoint Triggers (Auto-Detection)

Agents should proactively suggest checkpoints when:

### Trigger 1: Context Window Threshold

```yaml
Token Count > 150k:
  action: "Suggest checkpoint to user"
  message: "Context window at {{percentage}}% capacity. Recommend checkpoint before continuing."

Token Count > 180k:
  action: "Force checkpoint"
  message: "Context window critical. Creating checkpoint now to prevent data loss."
```

### Trigger 2: Blocker Detected

```yaml
Task Status → Blocked:
  action: "Auto-checkpoint"
  message: "Task blocked by {{blocker}}. Creating checkpoint and stopping."
  next_step: "Report blocker to user, ask for guidance"
```

### Trigger 3: Progress Milestone

```yaml
Tasks Completed % ∈ {25, 50, 75}:
  action: "Suggest checkpoint"
  message: "{{percentage}}% complete. Good time for a checkpoint?"

Checkpoint Task (checkpoint: true in tasks.json):
  action: "Mandatory checkpoint"
  message: "Reached checkpoint task {{id}}. Creating checkpoint as specified in plan."
```

### Trigger 4: Before Risky Operation

```yaml
About to:
  - Rename core module
  - Change database schema
  - Refactor cross-cutting concern
  - Delete significant code

action: "Suggest checkpoint"
message: "About to {{operation}}. Checkpoint first to enable easy rollback?"
```

---

## Resume After Checkpoint

When resuming from a checkpoint in a new session:

### Step 1: Load Session State

```bash
# Find latest checkpoint for feature
ls -t docs/context/SESSION_STATE-*.md | head -1

# Read entire file
cat docs/context/SESSION_STATE-{{feature}}.md
```

### Step 2: Verify Git State

```bash
# Check branch
git branch --show-current
# Expected: feature/{{feature-name}}

# Check for uncommitted changes
git status --short
# Expected: Clean or only temp files

# Find checkpoint commit
git log --oneline --grep="checkpoint" | head -1
```

### Step 3: Understand Context

From SESSION_STATE, extract:

```yaml
What was completed:
  - Read "Completed Work" section
  - Note which files were created/modified
  - Review test results

What is blocked:
  - Read "Active Blockers" section
  - Understand root cause and proposed fixes

What is next:
  - Read "Next Actions" section
  - Identify next 3-5 tasks
  - Check dependencies

Technical discoveries:
  - Read "Technical Discoveries" section
  - Note patterns, IDs, API contracts established
```

### Step 4: Validate Environment

```bash
# Verify dependencies installed
{{package_manager}} install

# Run tests to confirm state
{{test_command}}

# Check database migrations (if applicable)
{{migration_status_command}}

# Verify services running (if needed)
{{service_status_command}}
```

### Step 5: Resume Execution

Report to user:

```
📊 Session Resumed from Checkpoint

Last Checkpoint: {{timestamp}}
Progress: {{percentage}}% ({{completed}}/{{total}} tasks)

✅ Completed Since Last Session:
   - {{list of completed work}}

⚠️ Active Blockers:
   - {{list of blockers with status}}

📋 Next Tasks:
   - {{next 3 task titles}}

Ready to continue? (yes/no)
```

---

## Checkpoint Quality Standards

Every checkpoint MUST include:

### Required in SESSION_STATE.md

```yaml
✅ Progress Metrics:
   - Overall completion percentage
   - Phase-wise breakdown
   - Task counts by status

✅ Completed Work:
   - List of completed tasks with IDs
   - Files created/modified
   - Test results

✅ Active Blockers:
   - Severity (High/Medium/Low)
   - Root cause analysis
   - Proposed fix
   - Affected tasks

✅ Technical Discoveries:
   - Database schemas
   - API contracts
   - Code patterns
   - Environment variables
   - Dependencies added

✅ Next Actions:
   - Next 5 tasks prioritized
   - Dependencies identified
   - Estimated effort

✅ Requirements Coverage:
   - ADR requirements status
   - PRP acceptance criteria status
```

### Required in Git

```yaml
✅ Checkpoint Commit:
   prefix: "checkpoint({{feature}})"
   body: |
     - Progress summary
     - Completed work list
     - Active blockers
     - Next actions
     - Requirements status
   trailer: "Session State: docs/context/SESSION_STATE-{{feature}}.md"
```

### Required in tasks.json

```yaml
✅ Task Status Updates:
   completed_tasks:
     - status: "completed"
     - completedAt: "{{ISO8601_timestamp}}"

   blocked_tasks:
     - status: "blocked"
     - blocker: "{{description}}"

   in_progress_tasks:
     - status: "in-progress"
     - notes: "{{current_state}}"
```

---

## Integration with Bug Creation Skill

When checkpoint is triggered by a blocker that is a bug:

### Combined Workflow

```
1. Discover bug outside scope
   → Use bug-create skill

2. Bug blocks current task?
   YES:
     → Update tasks.json: current task status = "blocked"
     → Trigger checkpoint skill
     → Report blocker to user
   NO:
     → Document in SESSION_STATE
     → Continue work
     → Checkpoint at natural breakpoint
```

### Example: Blocked by Platform Bug

**Developer implementing user profile feature:**

```bash
# 1. Discover platform bug
"KafkaTopic Claim never becomes Ready - Composition missing"

# 2. Create bug ticket
@bug:create \
  --title="KafkaTopic Claims stuck in Creating" \
  --severity=critical \
  --area=platform

# 3. Mark task as blocked
jq '.tasks |= map(
  if .id == "user-profile-events"
  then . + {"status": "blocked", "blocker": "Bug #67 - KafkaTopic Composition"}
  else . end
)' docs/context/tasks.json > tmp.json && mv tmp.json docs/context/tasks.json

# 4. Checkpoint
@checkpoint --reason="blocked by Bug #67"

# 5. Report
echo "⚠️ BLOCKED: Cannot proceed without working KafkaTopic Claims."
echo "Created Bug #67 and checkpoint."
echo "Recommend: Platform Engineer fixes Bug #67, then Developer resumes from checkpoint."
```

---

## Anti-Patterns (DO NOT DO)

❌ **Checkpoint every 5 minutes**
→ Only checkpoint at meaningful milestones or blockers

❌ **Checkpoint without committing code**
→ All code MUST be committed in the checkpoint commit

❌ **Checkpoint with failing unit tests for completed work**
→ Fix tests first, or mark task as "in-progress" not "completed"

❌ **Checkpoint without updating tasks.json**
→ Session state and tasks.json MUST be in sync

❌ **Checkpoint with vague "Next Actions"**
→ Next actions must be specific, prioritized, with dependencies

❌ **Resume without reading SESSION_STATE**
→ You'll lose all context and discoveries

❌ **Checkpoint on main branch**
→ Always on feature branch; checkpoint is part of WIP, not final state

---

## Success Criteria

✅ Any agent can resume work from SESSION_STATE alone
✅ No context is lost (discoveries, decisions, blockers)
✅ Progress is accurately measured
✅ Blockers are clearly documented with proposed fixes
✅ Next steps are actionable and prioritized
✅ Requirements coverage is tracked
✅ Test results are preserved
✅ Git state is clean and documented
✅ Handoff is seamless (human or AI)
