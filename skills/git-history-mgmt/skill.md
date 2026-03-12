---
name: git-recall
description: >-
  Git history editing, undoing, rewriting, and improving — all through Claude Code.
  Replaces tools like Retcon, git-rewrite-commits, and manual git reflog gymnastics.
  Use this skill whenever the user mentions: undoing a commit, rewriting commit messages,
  cleaning up git history, improving commit messages with AI, undoing a rebase, undoing a push,
  undoing a branch deletion, interactive rebase, squashing commits, fixing commit messages,
  conventional commits, git reflog, git reset, git revert, "undo my last", "fix my commits",
  "clean up history", "rewrite history", "better commit messages", amend, fixup,
  or any git history manipulation. Also trigger when the user says "recall" in a git context.
---

# git-recall: Git History Editing & Improvement

A comprehensive skill for editing, undoing, rewriting, and improving git history — directly through Claude Code. No external tools, no npm packages, no API keys needed.

## Philosophy

Every git operation is undoable. This skill makes Claude the safety net. Instead of memorizing arcane reflog commands or installing GUI tools, the user just describes what they want in plain language and Claude handles it.

## Before Any Destructive Operation

**Always** follow this safety protocol:

1. **Confirm the current state** — run `git status`, `git log --oneline -10`, and `git branch -v` to understand where things stand
2. **Create a safety ref** — before any history rewrite, run:
   ```bash
   git tag git-recall-backup-$(date +%s)
   ```
3. **Explain what will happen** — tell the user exactly which commits/refs will change and what the recovery path is
4. **Ask for confirmation** on destructive operations (force push, history rewrite affecting shared branches)

## Core Capabilities

### 1. Undo Operations (Retcon-style)

For any "undo" request, identify the operation type and apply the right fix. Read `references/undo-operations.md` for the complete playbook of every undo scenario.

**Quick reference for the most common undos:**

| What happened | How to undo |
|---|---|
| Created a commit | `git reset --soft HEAD~1` (keeps changes staged) |
| Deleted a commit | Use `git reflog` → `git reset --hard <hash>` |
| Bad rebase | `git reflog` → find pre-rebase HEAD → `git reset --hard <hash>` |
| Bad merge | `git reset --hard ORIG_HEAD` or reflog |
| Bad push | `git push --force-with-lease origin <branch> <pre-push-hash>:<branch>` |
| Deleted branch | `git reflog` → `git branch <name> <hash>` |
| Staged wrong file | `git restore --staged <file>` |
| Lost stash | `git fsck --unreachable \| grep commit` → `git stash apply <hash>` |

### 2. Commit Message Improvement (AI-powered)

When the user wants better commit messages, Claude analyzes the diffs and generates conventional commit messages directly — no external AI API needed because **Claude is the AI**.

**Workflow:**
1. Get the commit(s) to improve: `git log --oneline -N`
2. For each commit, get the diff: `git diff-tree --no-commit-id -p <hash>`
3. Analyze the diff and generate a conventional commit message
4. Apply via interactive rebase with `reword`

**Conventional commit format:**
```
<type>(<scope>): <description>

[optional body]
[optional footer]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `ci`, `build`, `revert`

Read `references/commit-rewriting.md` for the full rewriting guide including templates, multi-language support, and quality scoring.

### 3. History Editing

For complex history manipulation (reorder, squash, split, edit), read `references/history-editing.md` for detailed procedures.

**Common operations:**
- **Squash last N commits**: `git reset --soft HEAD~N && git commit`
- **Split a commit**: Interactive rebase with `edit`, then `git reset HEAD~1`, stage selectively, commit multiple times
- **Reorder commits**: Interactive rebase, rearrange the pick lines
- **Drop a commit**: Interactive rebase, delete or change `pick` to `drop`
- **Edit a past commit**: Interactive rebase with `edit`, amend, continue

### 4. Branch Operations

- **Rename**: `git branch -m <old> <new>`
- **Recover deleted**: `git reflog` → `git branch <name> <hash>`
- **Clean up merged**: `git branch --merged main | grep -v main | xargs git branch -d`

## How to Handle Requests

**"Undo my last commit"** → `git reset --soft HEAD~1` (suggest `--mixed` or `--hard` based on whether they want to keep changes)

**"Fix my commit messages"** → Analyze recent commits, generate better messages, offer to rewrite via interactive rebase

**"Clean up my branch before PR"** → Assess commit quality, suggest squashing/rewording, execute the cleanup

**"I messed up a rebase"** → Check `git reflog`, find the pre-rebase state, offer to reset

**"Undo my push"** → Warn about shared branch implications, use `--force-with-lease`, explain the risks

**"Make my commits conventional"** → Read all commit diffs, generate conventional messages, batch-apply via `git filter-branch` or interactive rebase

## Important Safety Rules

1. **Never force-push to main/master without explicit confirmation** and a warning about team impact
2. **Always use `--force-with-lease`** instead of `--force` when pushing rewritten history
3. **Always create a backup tag** before destructive operations
4. **Check if the branch is shared** (`git branch -r --contains HEAD`) before rewriting
5. **Warn about commit hash changes** — anything downstream (PRs, CI references, other branches) will be affected

## Scripts

The `scripts/` directory contains helper scripts for common operations:
- `scripts/assess-commits.sh` — Analyze commit quality and suggest improvements
- `scripts/safe-rewrite.sh` — Safely rewrite commit messages with backup and recovery

Run these scripts when performing batch operations for reliability and consistency.

## When NOT to Use This Skill

- For understanding git concepts (just explain them normally)
- For basic `git add`/`git commit`/`git push` (no skill needed)
- For repository setup or clone operations
- For git configuration that doesn't involve history
