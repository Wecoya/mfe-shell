---
name: pr-create
description: Create a structured GitHub Pull Request from an autonomous agent feature branch.
---

# pr-create Skill

Creates a Pull Request from a feature branch to `main`, links the source issue, and prints the PR number.

## Responsibilities

1. Validate required inputs (`--branch`, `--issue`; optional: `--title`, `--draft`)
2. Generate a standardized PR description
3. Create PR with `gh pr create`
4. Assign current user (`@me`)
5. Comment on source issue with PR link
6. Print PR number to stdout

## Script Interface

```bash
.github/skills/pr-create/scripts/pr-create.sh \
  --branch "feature/9.29-autonomous-coding-agent-workflow" \
  --issue 443 \
  --title "feat(agent): autonomous coding agent workflow" \
  --draft false
```

Output:

```text
500
```

## Notes

- PR body always includes Summary, Related Issue, Changes, and Checklist sections.
- `--draft true` creates a draft PR.
