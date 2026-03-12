# Undo Operations Reference

Complete playbook for undoing any git operation. This is the Retcon replacement — every operation mapped to its undo.

## The Universal Recovery Tool: git reflog

`git reflog` shows every place HEAD has pointed to. It's the ultimate safety net. Entries expire after 90 days by default (30 days for orphaned commits). When in doubt, start here.

```bash
# Show reflog with timestamps
git reflog --date=relative

# Show reflog for a specific branch
git reflog show <branch>

# Find a specific operation
git reflog | grep -i "rebase\|merge\|reset\|checkout"
```

## Undo Scenarios

### Undo: Created a Commit

**Situation**: You just committed and want to undo it.

```bash
# Keep changes staged (undo the commit only)
git reset --soft HEAD~1

# Keep changes in working directory (unstage too)
git reset --mixed HEAD~1    # or just: git reset HEAD~1

# Discard everything (nuclear option)
git reset --hard HEAD~1
```

**For undoing multiple commits**: Replace `HEAD~1` with `HEAD~N` where N is the number of commits.

**If already pushed**: See "Undo: Pushed to Remote" below.

---

### Undo: Deleted/Lost a Commit

**Situation**: You did a `git reset --hard` or otherwise lost commits.

```bash
# 1. Find the lost commit in reflog
git reflog

# 2. Look for the commit hash before the destructive operation
#    Example output:
#    abc1234 HEAD@{0}: reset: moving to HEAD~3
#    def5678 HEAD@{1}: commit: feat: the commit you want back  <-- this one

# 3. Recover it
git reset --hard def5678

# Or create a new branch pointing to it (safer)
git branch recovered-work def5678

# Or cherry-pick just that one commit
git cherry-pick def5678
```

---

### Undo: Amended a Commit

**Situation**: You used `git commit --amend` and want the pre-amend version back.

```bash
# The original commit is in the reflog
git reflog
# Find the entry before "commit (amend)"

git reset --soft HEAD@{1}
# Now you have the pre-amend state staged
```

---

### Undo: Rebased a Branch

**Situation**: Interactive rebase went wrong — rewrote, moved, deleted, or squashed commits incorrectly.

```bash
# 1. Find the pre-rebase HEAD in reflog
git reflog
# Look for the last entry before "rebase" entries started
# Example:
#   abc1234 HEAD@{0}: rebase (finish): ...
#   ...
#   xyz9876 HEAD@{5}: rebase (start): checkout main
#   WANTED  HEAD@{6}: commit: your last real commit  <-- this one

# 2. Reset to pre-rebase state
git reset --hard WANTED

# Or if rebase is still in progress:
git rebase --abort
```

**ORIG_HEAD shortcut**: Immediately after a rebase (before any other operation), `ORIG_HEAD` points to the pre-rebase HEAD:
```bash
git reset --hard ORIG_HEAD
```

---

### Undo: Merged a Branch

**Situation**: Merge went wrong or was premature.

```bash
# Immediately after merge (before any other operations)
git reset --hard ORIG_HEAD

# Or use reflog if time has passed
git reflog
git reset --hard <pre-merge-hash>

# If merge is in progress with conflicts
git merge --abort
```

**If the merge was already pushed**: You'll need to either revert (creates a new commit) or force-push:
```bash
# Revert the merge commit (safe for shared branches)
git revert -m 1 <merge-commit-hash>

# Or force-push (dangerous on shared branches)
git reset --hard <pre-merge-hash>
git push --force-with-lease
```

---

### Undo: Pulled from Remote

**Situation**: `git pull` brought in unwanted changes.

A pull is a fetch + merge (or rebase if configured). Undo the merge/rebase part:

```bash
# Immediately after pull
git reset --hard ORIG_HEAD

# Or use reflog
git reflog
git reset --hard <pre-pull-hash>
```

---

### Undo: Pushed to Remote

**Situation**: You pushed commits that need to be undone.

**Option A — Revert (safe, creates new commits):**
```bash
# Revert a single commit
git revert <commit-hash>
git push

# Revert multiple commits
git revert <oldest-hash>^..<newest-hash>
git push
```

**Option B — Force push (rewrites remote history):**
```bash
# 1. Find the commit hash you want the remote to point to
git log --oneline

# 2. Reset locally
git reset --hard <target-hash>

# 3. Force push with lease (fails if remote was updated by someone else)
git push --force-with-lease origin <branch>
```

**Warning**: If others have pulled the pushed commits, force-pushing will cause them problems. Always communicate with the team first. Prefer `revert` on shared branches.

---

### Undo: Created a Branch

```bash
git branch -d <branch-name>    # safe delete (fails if unmerged)
git branch -D <branch-name>    # force delete
```

---

### Undo: Deleted a Branch

```bash
# 1. Find the commit the branch pointed to
git reflog | grep <branch-name>
# Or check the output of the delete command — git prints the hash

# 2. Recreate the branch
git branch <branch-name> <commit-hash>
```

---

### Undo: Staged a File

```bash
# Unstage a specific file
git restore --staged <file-path>

# Unstage specific hunks interactively
git reset -p <file-path>

# Unstage everything
git restore --staged .
```

---

### Undo: Unstaged a File

```bash
# Stage the whole file
git add <file-path>

# Stage specific hunks
git add -p <file-path>
```

**Note**: If the staged version had content not in the working directory, that content is gone — staging only captures what's in the working tree.

---

### Undo: Discarded Working Directory Changes

**Situation**: You ran `git checkout -- <file>` or `git restore <file>` and lost uncommitted changes.

If the changes were **never staged or committed**: they are gone. Git cannot recover them.

If they were **staged at some point**:
```bash
# Check the index reflog (may work in some cases)
git fsck --lost-found
ls .git/lost-found/other/
```

---

### Undo: Stash Drop / Stash Clear

```bash
# Find lost stash commits
git fsck --unreachable | grep commit

# For each candidate, check if it looks like your stash
git show <hash>

# Apply the lost stash
git stash apply <hash>
```

---

### Undo: Conflict Resolution (During Rebase)

**Situation**: You resolved a conflict wrong during a rebase.

```bash
# Abort the entire rebase and start over
git rebase --abort

# Then redo the rebase from scratch
git rebase <target>
```

There is no way to undo a single conflict resolution step mid-rebase without aborting. Always abort and restart.

---

### Undo: Cherry-Pick

```bash
# If cherry-pick is in progress with conflicts
git cherry-pick --abort

# If cherry-pick completed
git reset --hard HEAD~1
```

---

### Undo: Tag

```bash
# Delete local tag
git tag -d <tag-name>

# Delete remote tag
git push origin --delete <tag-name>
```

---

## The Reflog Cheat Sheet

```bash
# Full reflog
git reflog

# With dates
git reflog --date=iso

# For a specific branch
git reflog show main

# Search for specific actions
git reflog | grep "commit\|rebase\|merge\|reset\|pull"

# Extend reflog expiry (default 90 days)
git config gc.reflogExpire 180.days

# Reflog entries are per-repository and per-user — they're local only
```

## Emergency Recovery

If everything seems lost:

```bash
# 1. Don't panic. Don't run git gc.

# 2. Find all unreachable objects
git fsck --unreachable --no-reflogs

# 3. Look through dangling commits
git fsck --unreachable | grep commit | while read _ _ hash; do
  echo "=== $hash ==="
  git log --oneline -1 $hash
done

# 4. When you find what you need
git branch recovery <hash>
```
