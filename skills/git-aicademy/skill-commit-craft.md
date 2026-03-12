---
name: commit-craft
description: >-
  Generate high-quality conventional commit messages from staged changes. Analyzes diffs,
  determines type/scope, writes descriptive messages, and links to issues automatically.
  Complementary to git-recall (which rewrites history after the fact — this skill writes
  it right the first time). Use when the user says: "commit", "commit this",
  "write a commit message", "stage and commit", "what should I commit",
  "conventional commit", "good commit message", or any request to commit staged work
  with a well-formed message.
---

# commit-craft: Write Commits Right the First Time

Generate conventional commit messages by analyzing what actually changed, not by asking the developer to describe it.

## Philosophy

A good commit message is a gift to your future self, your teammates, and your automation. Release-please parses them to bump versions. Changelogs are generated from them. `git log --oneline` becomes useful documentation. This skill makes every commit count.

**Complementary to git-recall**: git-recall rewrites bad history. commit-craft prevents bad history from being written.

## Before Committing

1. **Check staging area**: `git diff --cached --stat` to see what's staged
2. **Check for unstaged changes**: `git status` to warn about forgotten files
3. **Check branch name**: extract issue number and type if present

## Message Generation Workflow

### Step 1: Analyze the Diff

```bash
# What files changed
git diff --cached --name-status

# Full diff for analysis
git diff --cached

# Stats for scope detection
git diff --cached --stat
```

### Step 2: Determine the Type

| Signal in diff | Type |
|----------------|------|
| New files with functionality | `feat` |
| Bug fix, null check, error handling, edge case | `fix` |
| README, comments, JSDoc, docstrings | `docs` |
| Formatting, whitespace, semicolons only | `style` |
| Restructuring without behavior change | `refactor` |
| Test files added or modified | `test` |
| Build config, CI, dependencies, tooling | `chore` / `ci` / `build` |
| Performance improvement (benchmarked or obvious) | `perf` |
| Reverting a previous commit | `revert` |

### Step 3: Determine the Scope

Look at the primary directory or module:
- `src/auth/` → `auth`
- `src/api/users.ts` → `api` or `users`
- `components/Button/` → `ui` or `button`
- Multiple unrelated areas → omit scope
- Root config files → omit scope or use `config`

### Step 4: Write the Description

Rules:
- Imperative mood ("add" not "added", "fix" not "fixed")
- Lowercase first letter
- No trailing period
- Under 72 characters for the first line
- Describe WHAT changed, not HOW
- Be specific: "add JWT validation" not "add validation"

### Step 5: Add Body and Footer (When Warranted)

**Body** (optional): explain WHY the change was made if not obvious from the description.

**Footer**:
- `Closes #N` if the branch name or context indicates an issue
- `BREAKING CHANGE: description` if the change breaks existing behavior
- `Co-authored-by: Name <email>` if applicable

### Step 6: Quality Score

Score the message before committing (same rubric as git-recall):

| Criteria | Points |
|----------|--------|
| Conventional format `type(scope): description` | +4 |
| First line 10-72 characters | +2 |
| Descriptive (not generic like "update", "fix", "changes") | +2 |
| Imperative mood | +1 |
| No trailing period | +1 |

**Minimum score: 7/10.** If below 7, revise before committing.

## Issue Detection

Extract issue references automatically:

```bash
# From branch name
BRANCH=$(git branch --show-current)

# Pattern: type/123-description or type/issue-123-description
ISSUE=$(echo "$BRANCH" | grep -oE '[0-9]+' | head -1)

# If found, add to footer
if [ -n "$ISSUE" ]; then
  echo "Closes #$ISSUE"
fi
```

## Atomic Commit Splitting

When the staging area contains logically separate changes, offer to split into atomic commits:

```bash
# Check if multiple logical groups exist
git diff --cached --name-only | sort

# If files span multiple concerns:
# 1. Unstage everything: git reset HEAD
# 2. Stage group 1: git add src/auth/*
# 3. Commit group 1: feat(auth): add token validation
# 4. Stage group 2: git add src/api/*
# 5. Commit group 2: fix(api): handle null user ID
```

**When to split**:
- Changes touch 3+ unrelated directories
- Both a feature and a fix are staged together
- Test files AND implementation are staged (sometimes worth separating)

**When NOT to split**:
- Changes are tightly coupled (implementation + its tests)
- Small refactor across files for the same reason
- Config changes that only make sense together

## Project Convention Detection

Before generating messages, check for project-specific conventions:

```bash
# Check for COMMIT_MESSAGE.md
[ -f "COMMIT_MESSAGE.md" ] || [ -f ".github/COMMIT_MESSAGE.md" ]

# Check recent commit format
git log --oneline -20

# Check for scope patterns already in use
git log --oneline -50 | grep -oE '\([a-z-]+\)' | sort | uniq -c | sort -rn
```

If the project has established patterns (specific scopes, ticket prefixes like `[JIRA-123]`), follow them.

## Common Patterns

**Single file changed**:
```
fix(api): handle null user ID in profile endpoint
```

**Multiple related files**:
```
feat(auth): add JWT token validation middleware

Add token verification for protected routes. Includes
refresh token rotation and expiry handling.

Closes #234
```

**Breaking change**:
```
feat(api)!: change user endpoint response format

BREAKING CHANGE: User endpoint now returns `data` wrapper.
Clients must update to read `response.data.user` instead
of `response.user`.
```

**Dependency update**:
```
chore(deps): update react to 19.1
```

**CI change**:
```
ci: add Node 22 to test matrix
```

## How to Handle Requests

**"Commit this"** → Analyze staging area, generate message, commit.

**"Commit with message X"** → Quality-score the provided message. If ≥7, use it. If <7, suggest improvement.

**"What should I commit?"** → Show staging area, suggest grouping and messages.

**"Stage and commit everything"** → `git add -A`, then analyze. Warn if the staging area is too diverse for one commit.

**"Commit and push"** → Generate message, commit, push. Use `--force-with-lease` only if the user explicitly asked to rewrite history.

## Sensitive Data Guard

Before committing, scan the diff for:
- `.env` files or environment variable assignments
- Patterns matching API keys: `sk-`, `pk_`, `AKIA`, `ghp_`
- Hardcoded passwords or connection strings
- Private keys or certificates

If detected: **STOP. Warn the user. Do not commit.** Suggest `.gitignore` additions and `git reset HEAD <file>`.

## Integration Points

- **git-recall**: If the user wants to fix a message after committing, hand off to git-recall
- **repo-bootstrap**: Follows the conventional commit format that repo-bootstrap's release-please is configured to parse
- **issue-to-pr**: Called by issue-to-pr for each commit during implementation
- **verification-loop**: Run verification before committing to catch broken builds
