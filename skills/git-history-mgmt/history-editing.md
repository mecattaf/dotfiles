# History Editing Reference

Detailed procedures for complex git history manipulation.

## Interactive Rebase Master Guide

Interactive rebase (`git rebase -i`) is the Swiss Army knife of history editing. It operates on a sequence of commits and lets you reorder, edit, squash, split, or drop any of them.

### Starting an Interactive Rebase

```bash
# Last N commits
git rebase -i HEAD~N

# From a specific commit (exclusive — that commit stays as-is)
git rebase -i <commit-hash>

# From the root (all commits)
git rebase -i --root
```

### Rebase Commands

Each line in the rebase todo list starts with a command:

| Command | Short | Effect |
|---|---|---|
| `pick` | `p` | Keep the commit as-is |
| `reword` | `r` | Keep changes, edit the message |
| `edit` | `e` | Pause to amend the commit |
| `squash` | `s` | Combine with previous, edit combined message |
| `fixup` | `f` | Combine with previous, discard this message |
| `drop` | `d` | Remove the commit entirely |
| `exec` | `x` | Run a shell command |
| `break` | `b` | Pause here (for inspection) |

### Reorder Commits

Simply rearrange the lines in the todo list. Commits are applied top-to-bottom.

```
# Original:
pick abc1234 commit A
pick def5678 commit B
pick ghi9012 commit C

# Reordered (B before A):
pick def5678 commit B
pick abc1234 commit A
pick ghi9012 commit C
```

**Warning**: Reordering can cause conflicts if commits depend on each other.

### Squash Commits

Combine multiple commits into one:

```
# Squash B and C into A:
pick abc1234 commit A
squash def5678 commit B
squash ghi9012 commit C
```

This opens an editor with all three messages — edit to create the final message.

**Quick squash** (keep only the first message):
```
pick abc1234 commit A
fixup def5678 commit B
fixup ghi9012 commit C
```

**Squash last N commits without interactive rebase**:
```bash
git reset --soft HEAD~N
git commit
```

### Split a Commit

Turn one commit into multiple:

```bash
# 1. Start interactive rebase
git rebase -i HEAD~N

# 2. Change 'pick' to 'edit' for the commit to split

# 3. When rebase stops at that commit:
git reset HEAD~1            # Undo the commit, keep changes in working dir

# 4. Stage and commit selectively
git add src/auth.ts
git commit -m "feat(auth): add authentication module"

git add src/utils.ts
git commit -m "refactor(utils): extract helper functions"

# 5. Continue the rebase
git rebase --continue
```

### Edit a Past Commit's Content

Change the actual files in a past commit:

```bash
# 1. Start interactive rebase
git rebase -i HEAD~N

# 2. Change 'pick' to 'edit' for the target commit

# 3. When rebase stops, make your changes
vim src/api.ts

# 4. Stage and amend
git add src/api.ts
git commit --amend --no-edit  # --no-edit keeps the message

# 5. Continue
git rebase --continue
```

### Drop a Commit

Remove a commit from history:

```bash
# Via interactive rebase — change 'pick' to 'drop' or delete the line

# Or use revert to undo a commit's changes without rewriting history
git revert <commit-hash>
```

### Exec: Run Commands During Rebase

```
pick abc1234 feat: add feature
exec npm test
pick def5678 fix: bug fix
exec npm test
```

This runs `npm test` after each commit is applied. If the command fails, the rebase pauses.

## Advanced Operations

### Transplant Commits Between Branches

```bash
# Cherry-pick specific commits onto current branch
git cherry-pick <hash1> <hash2> <hash3>

# Cherry-pick a range (exclusive start, inclusive end)
git cherry-pick <start-hash>..<end-hash>

# Cherry-pick without committing (stage the changes)
git cherry-pick --no-commit <hash>
```

### Graft a Branch onto a Different Base

```bash
# Rebase feature-branch onto main (from the point where it diverged)
git rebase main feature-branch

# Rebase onto a specific commit
git rebase --onto <new-base> <old-base> <branch>

# Example: Move commits from feature that were based on develop, onto main
git rebase --onto main develop feature-branch
```

### Flatten/Linearize History

Turn a messy merge-heavy history into a clean linear one:

```bash
# Rebase current branch onto target (replays commits linearly)
git rebase main

# If you want to squash everything into one commit
git reset --soft main
git commit -m "feat: complete feature implementation"
```

### Remove a File from All History

```bash
# Using git filter-repo (recommended over filter-branch)
# Install: pip install git-filter-repo
git filter-repo --path <file-to-remove> --invert-paths

# Using filter-branch (older method)
git filter-branch --force --index-filter \
  'git rm --cached --ignore-unmatch <file>' \
  --prune-empty -- --all
```

### Change Author on Commits

```bash
# For the last commit
git commit --amend --author="Name <email>"

# For multiple commits via interactive rebase
git rebase -i HEAD~N
# Change 'pick' to 'edit', then at each stop:
git commit --amend --author="Name <email>" --no-edit
git rebase --continue

# For all commits (nuclear option)
git filter-branch --env-filter '
  export GIT_AUTHOR_NAME="Name"
  export GIT_AUTHOR_EMAIL="email"
  export GIT_COMMITTER_NAME="Name"
  export GIT_COMMITTER_EMAIL="email"
' -- --all
```

### Bisect: Find Which Commit Introduced a Bug

```bash
# Start bisect
git bisect start

# Mark current as bad
git bisect bad

# Mark a known good commit
git bisect good <old-commit-hash>

# Git checks out a middle commit — test it and mark:
git bisect good   # or
git bisect bad

# Repeat until git identifies the culprit
# When done:
git bisect reset
```

**Automated bisect:**
```bash
git bisect start HEAD <good-hash>
git bisect run npm test
```

## Pre-PR Branch Cleanup Workflow

A complete workflow for cleaning up a feature branch before creating a PR:

```bash
# 1. Ensure you're on the feature branch
git checkout feature-branch

# 2. Fetch latest and rebase onto target
git fetch origin
git rebase origin/main

# 3. Review commits
git log --oneline origin/main..HEAD

# 4. Interactive rebase to clean up
git rebase -i origin/main
# - Squash WIP commits
# - Reword vague messages
# - Reorder for logical flow
# - Drop debug/temp commits

# 5. Verify the result
git log --oneline origin/main..HEAD
git diff origin/main --stat

# 6. Force push the cleaned branch
git push --force-with-lease origin feature-branch
```

## Handling Conflicts During Rebase

```bash
# See which files conflict
git status

# After resolving conflicts
git add <resolved-files>
git rebase --continue

# Skip this commit if it's no longer needed
git rebase --skip

# Give up and go back to pre-rebase state
git rebase --abort
```

## Automation with GIT_SEQUENCE_EDITOR

For scripted rebases without manual editor interaction:

```bash
# Reword all commits
GIT_SEQUENCE_EDITOR="sed -i 's/^pick/reword/'" git rebase -i HEAD~N

# Drop all commits matching a pattern
GIT_SEQUENCE_EDITOR="sed -i '/WIP/s/^pick/drop/'" git rebase -i HEAD~N

# Squash everything into the first commit
GIT_SEQUENCE_EDITOR="sed -i '2,\$s/^pick/fixup/'" git rebase -i HEAD~N
```

## Recovery from Any Failed Edit

No matter what went wrong:

```bash
# 1. Check reflog for the pre-operation state
git reflog

# 2. Reset to the safe point
git reset --hard <pre-operation-hash>

# 3. If backup tags exist
git tag | grep git-recall-backup
git reset --hard <backup-tag>
```
