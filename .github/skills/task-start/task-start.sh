#!/bin/bash
# Task Start - Move task to In Progress
# Usage: ./task-start.sh <task-id-or-filename>
#
# This script implements the task-start skill from .github/skills/task-start/SKILL.md
# It is IDEMPOTENT - safe to run multiple times.

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
TASK_INPUT="${1:-}"

if [ -z "$TASK_INPUT" ]; then
  echo -e "${RED}❌ ERROR: Task ID or filename required${NC}"
  echo "Usage: $0 <task-id-or-filename>"
  echo "Example: $0 2.4.5"
  echo "Example: $0 2.4.5_refactor_id_passing.md"
  exit 1
fi

echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}Task Start - Move to In Progress${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""

# Step 1: Find task file
echo -e "${BLUE}📋 Step 1: Finding task file...${NC}"
TASK_FILE=$(find docs/tasks/ -name "*${TASK_INPUT}*.md" 2>/dev/null | head -1)

if [ -z "$TASK_FILE" ]; then
  echo -e "${RED}❌ ERROR: Task file not found for '${TASK_INPUT}'${NC}"
  exit 1
fi

TASK_BASENAME=$(basename "$TASK_FILE")
CURRENT_DIR=$(dirname "$TASK_FILE")

echo -e "${GREEN}✅ Found task: $TASK_FILE${NC}"
echo -e "${GREEN}✅ Current location: $CURRENT_DIR${NC}"
echo ""

# Step 2: Check current state (idempotency)
echo -e "${BLUE}📦 Step 2: Checking current state...${NC}"
if [[ "$CURRENT_DIR" == *"In Progress"* ]]; then
  echo -e "${GREEN}✅ Task already in 'In Progress' - skipping file move${NC}"
  SKIP_FILE_MOVE=true
else
  echo -e "${YELLOW}📦 Task needs to be moved to In Progress${NC}"
  SKIP_FILE_MOVE=false
fi
echo ""

# Step 3: Move task file (conditional)
echo -e "${BLUE}📂 Step 3: Moving task file...${NC}"
if [ "$SKIP_FILE_MOVE" = false ]; then
  mkdir -p "docs/tasks/In Progress/"
  mv "$TASK_FILE" "docs/tasks/In Progress/$TASK_BASENAME"
  echo -e "${GREEN}✅ Moved task to In Progress: docs/tasks/In Progress/$TASK_BASENAME${NC}"
  TASK_FILE="docs/tasks/In Progress/$TASK_BASENAME"
else
  echo -e "${GREEN}⏭️  File already in correct location${NC}"
fi
echo ""

# Step 4: Update GitHub Issue (idempotent)
echo -e "${BLUE}🔗 Step 4: Updating GitHub Issue...${NC}"
if [ -f docs/tasks/github_issue_mapping.md ]; then
  ISSUE_NUM=$(grep "$TASK_BASENAME" docs/tasks/github_issue_mapping.md | \
    grep -oE '#[0-9]+' | sed 's/#//' | head -1)

  if [ -n "$ISSUE_NUM" ]; then
    echo -e "${GREEN}✅ Found GitHub Issue: #$ISSUE_NUM${NC}"

    # Check if gh CLI is available
    if ! command -v gh &> /dev/null; then
      echo -e "${YELLOW}⚠️  GitHub CLI not installed - skipping GitHub sync${NC}"
      ISSUE_NUM=""
    else
      # Check current assignees
      CURRENT_ASSIGNEE=$(gh issue view "$ISSUE_NUM" --repo ${GH_REPO:-${GITHUB_REPOSITORY:-Wecoya/private-sovereign-cloud}} --json assignees --jq '.assignees[].login' 2>/dev/null | head -1)
      CURRENT_USER=$(gh api user --jq '.login' 2>/dev/null)

      if [ "$CURRENT_ASSIGNEE" != "$CURRENT_USER" ]; then
        gh issue edit "$ISSUE_NUM" \
          --add-assignee @me \
          --repo ${GH_REPO:-${GITHUB_REPOSITORY:-Wecoya/private-sovereign-cloud}} 2>/dev/null

        echo -e "${GREEN}✅ Assigned GitHub Issue #$ISSUE_NUM to $CURRENT_USER${NC}"
      else
        echo -e "${GREEN}✅ Issue already assigned to current user${NC}"
      fi
    fi
  else
    echo -e "${YELLOW}⚠️  No GitHub issue found in mapping for $TASK_BASENAME${NC}"
    ISSUE_NUM=""
  fi
else
  echo -e "${YELLOW}⚠️  github_issue_mapping.md not found - skipping GitHub sync${NC}"
  ISSUE_NUM=""
fi
echo ""

# Step 5: Update GitHub Project Board (idempotent)
echo -e "${BLUE}📊 Step 5: Updating GitHub Project Board...${NC}"
if [ -n "$ISSUE_NUM" ] && command -v gh &> /dev/null; then
  ITEM_ID=$(gh project item-list 2 --owner Wecoya --format json --limit 100 2>/dev/null | \
    jq -r ".items[] | select(.content.number == $ISSUE_NUM) | .id")

  if [ -n "$ITEM_ID" ]; then
    CURRENT_STATUS=$(gh project item-list 2 --owner Wecoya --format json --limit 100 2>/dev/null | \
      jq -r ".items[] | select(.content.number == $ISSUE_NUM) | .status")

    if [ "$CURRENT_STATUS" != "In progress" ]; then
      gh project item-edit \
        --id "$ITEM_ID" \
        --project-id "PVT_kwDODad2uc4BDObK" \
        --field-id "PVTSSF_lADODad2uc4BDObKzg1NL2w" \
        --single-select-option-id "47fc9ee4" 2>/dev/null

      echo -e "${GREEN}✅ Moved GitHub Project item to 'In progress'${NC}"
    else
      echo -e "${GREEN}✅ Project item already in 'In progress'${NC}"
    fi
  else
    echo -e "${YELLOW}⚠️  Adding issue to GitHub Project...${NC}"
    gh project item-add 2 --owner Wecoya \
      --url "https://github.com/${GH_REPO:-${GITHUB_REPOSITORY:-Wecoya/private-sovereign-cloud}}/issues/$ISSUE_NUM" 2>/dev/null

    sleep 1
    ITEM_ID=$(gh project item-list 2 --owner Wecoya --format json --limit 100 2>/dev/null | \
      jq -r ".items[] | select(.content.number == $ISSUE_NUM) | .id")

    if [ -n "$ITEM_ID" ]; then
      gh project item-edit \
        --id "$ITEM_ID" \
        --project-id "PVT_kwDODad2uc4BDObK" \
        --field-id "PVTSSF_lADODad2uc4BDObKzg1NL2w" \
        --single-select-option-id "47fc9ee4" 2>/dev/null

      echo -e "${GREEN}✅ Added to project and moved to 'In progress'${NC}"
    fi
  fi
else
  echo -e "${YELLOW}⏭️  Skipping project board update (no GitHub CLI or issue)${NC}"
fi
echo ""

# Step 6: Update mapping file (conditional)
echo -e "${BLUE}📝 Step 6: Updating mapping file...${NC}"
if [ -f docs/tasks/github_issue_mapping.md ]; then
  CURRENT_MAPPING=$(grep "$TASK_BASENAME" docs/tasks/github_issue_mapping.md)

  if [[ "$CURRENT_MAPPING" != *"In Progress"* ]]; then
    sed -i.bak "s|docs/tasks/[^/]*/$TASK_BASENAME|docs/tasks/In Progress/$TASK_BASENAME|g" \
      docs/tasks/github_issue_mapping.md
    rm docs/tasks/github_issue_mapping.md.bak 2>/dev/null || true

    echo -e "${GREEN}✅ Updated github_issue_mapping.md with In Progress path${NC}"
  else
    echo -e "${GREEN}✅ Mapping already shows In Progress path${NC}"
  fi
fi
echo ""

# Step 7: Commit changes (conditional)
echo -e "${BLUE}💾 Step 7: Committing changes...${NC}"
if git diff --quiet docs/tasks/ && git diff --cached --quiet docs/tasks/; then
  echo -e "${GREEN}✅ No changes to commit - task already in desired state${NC}"
else
  git add docs/tasks/
  git add docs/tasks/github_issue_mapping.md 2>/dev/null || true

  git commit -m "chore(tasks): move ${TASK_INPUT} to In Progress

Starting work on task: $TASK_BASENAME

GitHub Issue: #${ISSUE_NUM:-N/A}"

  echo -e "${GREEN}✅ Committed task status change${NC}"

  # Ask about pushing
  read -p "Push changes to remote? (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    git push
    echo -e "${GREEN}✅ Pushed to remote${NC}"
  else
    echo -e "${YELLOW}⚠️  Changes committed locally only${NC}"
  fi
fi
echo ""

# Step 8: Verification
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}✅ Task Start Complete - Verification${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""

if [ -f "docs/tasks/In Progress/$TASK_BASENAME" ]; then
  echo -e "${GREEN}✅ Task file: docs/tasks/In Progress/$TASK_BASENAME${NC}"
else
  echo -e "${RED}❌ Task file not found in In Progress!${NC}"
fi

if [ -n "$ISSUE_NUM" ] && command -v gh &> /dev/null; then
  ISSUE_STATE=$(gh issue view "$ISSUE_NUM" --repo ${GH_REPO:-${GITHUB_REPOSITORY:-Wecoya/private-sovereign-cloud}} --json state,assignees --jq '.state + " | Assignee: " + .assignees[0].login' 2>/dev/null)
  echo -e "${GREEN}✅ GitHub Issue #$ISSUE_NUM: $ISSUE_STATE${NC}"

  PROJECT_STATUS=$(gh project item-list 2 --owner Wecoya --format json --limit 100 2>/dev/null | \
    jq -r ".items[] | select(.content.number == $ISSUE_NUM) | .status")
  echo -e "${GREEN}✅ GitHub Project status: $PROJECT_STATUS${NC}"
fi

echo ""
echo -e "${GREEN}🚀 Ready to start implementation!${NC}"
