# Commit Message Rewriting Reference

Guide for analyzing and improving commit messages using Claude's own intelligence — no external API calls needed.

## Quality Assessment

Before rewriting, assess existing commit quality. A commit message is well-formed if it scores 7+ on this scale:

| Criteria | Points | Description |
|---|---|---|
| Conventional format | +4 | Matches `type(scope): description` |
| Appropriate length | +2 | First line between 10-72 characters |
| Descriptive content | +2 | Not generic ("update", "fix", "changes") |
| Present tense | +1 | Uses imperative ("add" not "added") |
| No trailing period | +1 | First line doesn't end with `.` |

**Total: 10 points. Skip commits scoring ≥ 7.**

### Generic messages that always need improvement:
`update`, `fix`, `change`, `modify`, `commit`, `initial`, `test`, `wip`, `stuff`, `things`, `misc`, `temp`, `asdf`, `...`, `done`, `save`, `.`, `_`, `-`

## Generating Better Messages

When analyzing a commit's diff, follow this process:

### Step 1: Understand the change
```bash
# Get the full diff for a commit
git diff-tree --no-commit-id -p <hash>

# Get just the files changed
git diff-tree --no-commit-id --name-status -r <hash>

# Get stats
git diff-tree --no-commit-id --stat <hash>
```

### Step 2: Determine the type
Look at what changed:
- New files with functionality → `feat`
- Bug fix, error handling, edge case → `fix`
- README, comments, JSDoc → `docs`
- Formatting, whitespace, semicolons → `style`
- Restructuring without behavior change → `refactor`
- Test files → `test`
- Build config, CI, dependencies → `chore`, `ci`, `build`
- Performance improvement → `perf`
- Reverting a previous commit → `revert`

### Step 3: Determine the scope
Look at the primary directory or module affected:
- `src/auth/` → `auth`
- `src/api/users.ts` → `api` or `users`
- `components/Button/` → `ui` or `button`
- Multiple areas → omit scope or use the most significant one

### Step 4: Write the description
- Start with a lowercase verb in imperative mood
- Describe WHAT changed, not HOW
- Be specific: "add JWT validation" not "add validation"
- Stay under 72 characters for the first line
- No trailing period

### Examples

**Diff shows**: New file `src/auth/jwt.ts` with token validation logic
**Message**: `feat(auth): add JWT token validation middleware`

**Diff shows**: Fixed null check in `src/api/users.ts` line 42
**Message**: `fix(api): handle null user ID in profile endpoint`

**Diff shows**: Updated README with installation steps
**Message**: `docs: add installation instructions to README`

**Diff shows**: Moved utility functions from `src/helpers.ts` to `src/utils/`
**Message**: `refactor: reorganize utility functions into dedicated modules`

**Diff shows**: Added `.github/workflows/ci.yml`
**Message**: `ci: add GitHub Actions workflow for automated testing`

## Rewriting Methods

### Method A: Interactive Rebase (for ≤ 20 commits)

Best for selective rewriting where you want to review each change.

```bash
# Rewrite last N commits
git rebase -i HEAD~N

# In the editor, change 'pick' to 'reword' for commits to fix
# Save and close — git will pause at each 'reword' commit
# Enter the new message, save, and continue
```

To automate this with Claude:

```bash
# 1. Generate a rebase script
GIT_SEQUENCE_EDITOR="sed -i 's/^pick/reword/'" git rebase -i HEAD~N

# 2. For each commit, Claude provides the new message
# The GIT_EDITOR can be set to a script that writes the message
```

### Method B: filter-branch (for bulk rewriting)

Best for rewriting many or all commits. More dangerous — always backup first.

```bash
# Create backup
git tag git-recall-backup-$(date +%s)

# Rewrite all commits using a message map
git filter-branch -f --msg-filter 'cat' HEAD
```

Use `scripts/safe-rewrite.sh` for the full automated workflow.

### Method C: Amend (for the last commit only)

```bash
# Change the last commit's message
git commit --amend -m "feat(auth): add JWT validation"

# Or open editor
git commit --amend
```

### Method D: Fixup commits (for staged changes that belong to an earlier commit)

```bash
# Stage your fix
git add <files>

# Create a fixup commit targeting the original
git commit --fixup=<original-hash>

# Auto-squash during rebase
git rebase -i --autosquash HEAD~N
```

## Custom Templates

Users may want specific formats. Common patterns:

| Template | Example |
|---|---|
| `type(scope): message` | `feat(auth): add login page` |
| `[JIRA-123] type: message` | `[JIRA-456] fix: resolve timeout` |
| `emoji type: message` | `✨ feat: add dark mode` |
| `type: message` | `fix: handle null pointer` |

When a user specifies a template, extract the structure and apply it consistently.

## Multi-Language Support

When the user requests messages in a language other than English, generate the description portion in that language while keeping the type/scope in English (conventional commits standard):

- `feat(auth): añadir validación de token JWT` (Spanish)
- `fix(api): résoudre le pointeur null` (French)
- `docs: ドキュメントを更新する` (Japanese)

## Batch Processing Strategy

When rewriting many commits:

1. **Assess all commits first** — show the user a summary of what needs improvement
2. **Generate all new messages** — compute them before starting the rewrite
3. **Show a preview** — let the user review and approve before applying
4. **Apply atomically** — use filter-branch or a scripted rebase so it's all-or-nothing
5. **Verify the result** — `git log --oneline` to confirm

## Sensitive Data in Diffs

When analyzing diffs, be aware of and ignore:
- `.env` files and variants
- API keys, tokens, passwords
- Private keys and certificates
- Database connection strings

Never include sensitive data in commit messages. If a commit touches sensitive files, describe the change generically: `chore: update environment configuration`

## COMMIT_MESSAGE.md Support

Check if the repository has a `COMMIT_MESSAGE.md` file (in root, `.git/`, or `.github/`) that defines project-specific conventions. If present, follow those guidelines in addition to the standard rules.
