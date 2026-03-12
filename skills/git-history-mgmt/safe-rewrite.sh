#!/usr/bin/env bash
#
# safe-rewrite.sh — Safely rewrite commit messages with backup and recovery
#
# Usage:
#   bash safe-rewrite.sh <message-map-file> [commit-range]
#
# The message map file is a JSON array where each entry maps an old message
# to a new message. Claude generates this file before calling the script.
#
# Example message-map.json:
#   [
#     {"hash": "abc1234", "old": "update", "new": "feat(auth): add login flow"},
#     {"hash": "def5678", "old": "fix", "new": "fix(api): handle null user ID"}
#   ]
#
# This script:
#   1. Creates a backup tag
#   2. Validates the message map
#   3. Performs the rewrite using git filter-branch
#   4. Reports results
#   5. Provides recovery instructions

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

MAP_FILE="${1:-}"
RANGE="${2:-HEAD}"

if [ -z "$MAP_FILE" ]; then
  echo -e "${RED}Error: Message map file required${NC}"
  echo "Usage: $0 <message-map.json> [commit-range]"
  exit 1
fi

if [ ! -f "$MAP_FILE" ]; then
  echo -e "${RED}Error: File not found: $MAP_FILE${NC}"
  exit 1
fi

# Verify git repo
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo -e "${RED}Error: Not a git repository${NC}"
  exit 1
fi

# Check for uncommitted changes
if ! git diff --quiet HEAD 2>/dev/null; then
  echo -e "${RED}Error: You have uncommitted changes. Please commit or stash them first.${NC}"
  exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
BACKUP_TAG="git-recall-backup-$(date +%s)"

echo -e "${CYAN}${BOLD}🔄 git-recall: Safe Commit Rewrite${NC}"
echo -e "${BLUE}Branch: $BRANCH${NC}"
echo -e "${BLUE}Range: $RANGE${NC}"
echo ""

# Step 1: Create backup
echo -e "${GREEN}📌 Creating backup tag: $BACKUP_TAG${NC}"
git tag "$BACKUP_TAG"

# Step 2: Check if branch is shared
REMOTE_BRANCHES=$(git branch -r --contains HEAD 2>/dev/null || true)
if [ -n "$REMOTE_BRANCHES" ]; then
  echo -e "${YELLOW}${BOLD}⚠️  Warning: HEAD exists on remote branches:${NC}"
  echo "$REMOTE_BRANCHES" | sed 's/^/  /'
  echo -e "${YELLOW}Rewriting will require force-push and may affect collaborators.${NC}"
  echo ""
fi

# Step 3: Build the filter script
FILTER_SCRIPT=$(mktemp /tmp/git-recall-filter-XXXXXX.sh)
GIT_DIR=$(git rev-parse --git-dir)

# Parse JSON and build sed-like replacements
# We use a simple approach: create a mapping file and look up each commit
MAPPING_FILE=$(mktemp /tmp/git-recall-mapping-XXXXXX.txt)

# Extract hash-to-message mappings using basic tools (no jq dependency)
python3 -c "
import json, sys
with open('$MAP_FILE') as f:
    entries = json.load(f)
for entry in entries:
    h = entry.get('hash', '')[:40]
    msg = entry.get('new', '').replace('\n', '\\\\n')
    print(f'{h}\t{msg}')
" > "$MAPPING_FILE" 2>/dev/null || {
  # Fallback if python3 not available — try node
  node -e "
    const fs = require('fs');
    const entries = JSON.parse(fs.readFileSync('$MAP_FILE', 'utf8'));
    entries.forEach(e => {
      const h = (e.hash || '').slice(0, 40);
      const msg = (e.new || e['new'] || '').replace(/\n/g, '\\\\n');
      console.log(h + '\t' + msg);
    });
  " > "$MAPPING_FILE" 2>/dev/null || {
    echo -e "${RED}Error: Could not parse message map. Need python3 or node.${NC}"
    rm -f "$FILTER_SCRIPT" "$MAPPING_FILE"
    exit 1
  }
}

ENTRY_COUNT=$(wc -l < "$MAPPING_FILE" | tr -d ' ')
echo -e "${BLUE}📝 Found $ENTRY_COUNT commits to rewrite${NC}"
echo ""

# Show preview
echo -e "${BOLD}Preview of changes:${NC}"
while IFS=$'\t' read -r hash new_msg; do
  short="${hash:0:8}"
  old_msg=$(git log -1 --format="%s" "$hash" 2>/dev/null || echo "???")
  echo -e "  ${YELLOW}$short${NC}: \"$old_msg\""
  echo -e "       → ${GREEN}\"$new_msg\"${NC}"
done < "$MAPPING_FILE"
echo ""

# Create the filter script
cat > "$FILTER_SCRIPT" << 'SCRIPT_EOF'
#!/usr/bin/env bash
MAPPING_FILE="__MAPPING_FILE__"
COMMIT_HASH="$GIT_COMMIT"

# Read the original message from stdin
OLD_MSG=$(cat)

# Look up this commit in the mapping
NEW_MSG=$(grep "^${COMMIT_HASH:0:40}" "$MAPPING_FILE" 2>/dev/null | cut -f2-)

if [ -n "$NEW_MSG" ]; then
  # Unescape newlines
  echo -e "$NEW_MSG"
else
  # No mapping found — keep original
  echo "$OLD_MSG"
fi
SCRIPT_EOF

sed -i "s|__MAPPING_FILE__|$MAPPING_FILE|g" "$FILTER_SCRIPT"
chmod +x "$FILTER_SCRIPT"

# Step 4: Execute the rewrite
echo -e "${CYAN}🔄 Rewriting commits...${NC}"

if git filter-branch -f --msg-filter "bash '$FILTER_SCRIPT'" "$RANGE" 2>/dev/null; then
  echo -e "${GREEN}${BOLD}✅ Successfully rewrote $ENTRY_COUNT commit messages!${NC}"
else
  echo -e "${RED}${BOLD}❌ Rewrite failed. Restoring from backup...${NC}"
  git reset --hard "$BACKUP_TAG"
  echo -e "${GREEN}Restored to backup state.${NC}"
  rm -f "$FILTER_SCRIPT" "$MAPPING_FILE"
  exit 1
fi

# Cleanup
rm -f "$FILTER_SCRIPT" "$MAPPING_FILE"

# Step 5: Report
echo ""
echo -e "${BOLD}Results:${NC}"
echo -e "  ${GREEN}✓ Commits rewritten: $ENTRY_COUNT${NC}"
echo -e "  ${BLUE}📌 Backup tag: $BACKUP_TAG${NC}"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo -e "  1. Review: ${CYAN}git log --oneline -$((ENTRY_COUNT + 5))${NC}"
echo -e "  2. Push:   ${CYAN}git push --force-with-lease origin $BRANCH${NC}"
echo -e "  3. If something went wrong:"
echo -e "     ${CYAN}git reset --hard $BACKUP_TAG${NC}"
echo -e "  4. Clean up backup when satisfied:"
echo -e "     ${CYAN}git tag -d $BACKUP_TAG${NC}"
