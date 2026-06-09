---
name: branch-create
description: Create a feature branch from main for an issue-driven autonomous agent run.
---

# branch-create Skill

Creates a deterministic feature branch for an issue and prints the branch name for downstream steps.

## Responsibilities

1. Validate required inputs (`--issue`, `--task-id`, `--title`)
2. Slugify title and build branch name: `feature/<task-id>-<slug>`
3. Fetch latest `origin/main`
4. Create branch from `origin/main` or reuse existing local/remote branch
5. Push branch to origin and set upstream
6. Print branch name to stdout

## Script Interface

```bash
.github/skills/branch-create/scripts/branch-create.sh \
  --issue 443 \
  --task-id "9.29" \
  --title "Autonomous Coding Agent Workflow"
```

Output:

```text
feature/9.29-autonomous-coding-agent-workflow
```

## Notes

- Safe to re-run: existing branch is reused.
- Designed for CI usage in `agent-run.yml`.
