#!/usr/bin/env bash
#
# assess-commits.sh — Analyze commit quality and suggest improvements
#
# Usage:
#   bash assess-commits.sh [N]           # Assess last N commits (default: 20)
#   bash assess-commits.sh --all         # Assess all commits
#   bash assess-commits.sh --branch main # Assess commits since branching from main

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'
BOLD='\033[1m'

# Parse arguments
COUNT=20
RANGE=""

case "${1:-}" in
  --all)
    RANGE="HEAD"
    COUNT=0
    ;;
  --branch)
    BASE="${2:-main}"
    RANGE="$BASE..HEAD"
    COUNT=0
    ;;
  [0-9]*)
    COUNT="$1"
    ;;
  "")
    ;;
  *)
    echo "Usage: $0 [N | --all | --branch <base>]"
    exit 1
    ;;
esac

# Verify we're in a git repo
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo -e "${RED}Error: Not a git repository${NC}"
  exit 1
fi

# Get commits
if [ "$COUNT" -gt 0 ]; then
  COMMITS=$(git log --format="%H" -n "$COUNT" --reverse)
  TITLE="Last $COUNT commits"
else
  COMMITS=$(git rev-list --reverse "$RANGE")
  TITLE="Commits in range $RANGE"
fi

TOTAL=$(echo "$COMMITS" | wc -l | tr -d ' ')

echo -e "${CYAN}${BOLD}📊 Commit Quality Assessment${NC}"
echo -e "${GRAY}$TITLE ($TOTAL commits)${NC}"
echo ""

# Conventional commit pattern
CONV_PATTERN='^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert)(\([^)]+\))?: .+'

# Generic messages
GENERIC_WORDS="update|fix|change|modify|commit|initial|test|wip|stuff|things|misc|temp|save|done|checkpoint"

GOOD=0
NEEDS_WORK=0
BAD=0

echo -e "${BOLD}Score  Hash      Message${NC}"
echo -e "${GRAY}───────────────────────────────────────────────────────────────${NC}"

while IFS= read -r hash; do
  [ -z "$hash" ] && continue
  
  msg=$(git log -1 --format="%s" "$hash")
  short=$(echo "$hash" | cut -c1-8)
  score=0
  issues=""
  
  # Check conventional format (+4)
  if echo "$msg" | grep -qE "$CONV_PATTERN"; then
    score=$((score + 4))
  else
    issues="${issues}no-conv "
  fi
  
  # Check length (+2)
  len=${#msg}
  if [ "$len" -ge 10 ] && [ "$len" -le 72 ]; then
    score=$((score + 2))
  elif [ "$len" -lt 10 ]; then
    issues="${issues}too-short "
  else
    issues="${issues}too-long "
  fi
  
  # Check for generic messages (+2)
  if ! echo "$msg" | grep -qiE "^($GENERIC_WORDS)\.?$"; then
    score=$((score + 2))
  else
    issues="${issues}generic "
  fi
  
  # Check present tense lowercase (+1)
  if echo "$msg" | grep -qE '^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert)?(\([^)]+\))?: [a-z]'; then
    score=$((score + 1))
  else
    issues="${issues}tense/case "
  fi
  
  # Check no trailing period (+1)
  first_line=$(echo "$msg" | head -1)
  if ! echo "$first_line" | grep -qE '\.$'; then
    score=$((score + 1))
  else
    issues="${issues}trailing-period "
  fi
  
  # Determine status
  if [ "$score" -ge 7 ]; then
    color="$GREEN"
    symbol="✓"
    GOOD=$((GOOD + 1))
  elif [ "$score" -ge 4 ]; then
    color="$YELLOW"
    symbol="~"
    NEEDS_WORK=$((NEEDS_WORK + 1))
  else
    color="$RED"
    symbol="✗"
    BAD=$((BAD + 1))
  fi
  
  # Truncate message for display
  display_msg="$msg"
  if [ ${#display_msg} -gt 50 ]; then
    display_msg="${display_msg:0:47}..."
  fi
  
  echo -e "${color}${symbol} ${score}/10${NC}  ${GRAY}${short}${NC}  ${display_msg}"
  
  if [ -n "$issues" ] && [ "$score" -lt 7 ]; then
    echo -e "         ${GRAY}Issues: ${issues}${NC}"
  fi
  
done <<< "$COMMITS"

echo ""
echo -e "${GRAY}───────────────────────────────────────────────────────────────${NC}"
echo -e "${BOLD}Summary:${NC}"
echo -e "  ${GREEN}✓ Good (7+):${NC}       $GOOD"
echo -e "  ${YELLOW}~ Needs work (4-6):${NC} $NEEDS_WORK"
echo -e "  ${RED}✗ Poor (0-3):${NC}      $BAD"
echo -e "  ${BLUE}Total:${NC}             $TOTAL"

PCTGOOD=0
if [ "$TOTAL" -gt 0 ]; then
  PCTGOOD=$((GOOD * 100 / TOTAL))
fi

echo ""
if [ "$PCTGOOD" -ge 80 ]; then
  echo -e "${GREEN}${BOLD}✨ Great commit hygiene! $PCTGOOD% of commits are well-formed.${NC}"
elif [ "$PCTGOOD" -ge 50 ]; then
  echo -e "${YELLOW}${BOLD}📝 Room for improvement — $((NEEDS_WORK + BAD)) commits could use better messages.${NC}"
else
  echo -e "${RED}${BOLD}🔧 Commit messages need attention — consider rewriting with: /git-recall${NC}"
fi
