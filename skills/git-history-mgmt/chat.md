

f/git-rewrite-commits
master

GITHUB

there is this product called 
https://retcon.app/

on their landing page they have The cheatsheet you won’t need.
Retcon frees you to quickly experiment by making it easy to undo mistakes. So easy, in fact, that you already know exactly how.
How to undo in RetconHow to undo through the Git CLICreated a commitPress ⌘Z.Run git reset --soft HEAD~.Deleted a commitPress ⌘Z.Run git reflog to display the list of recent head commits. Copy the first one’s hash. Run git reset, then git stash to set changes aside. Run git reset --hard COPIED_HASH to revert to the previous head commit. Run git stash pop to restore stashed changes.Rebased a branch (reword, move, delete, fixup)Press ⌘Z.See above.Pulled from a remotePress ⌘Z.See above.Pushed to a remotePress ⌘Z.Find the output of the git push command to undo. On the last line of the output, copy the first commit hash. Run git push force COPIED_HASH. If the remote branch was changed since your push, the new changes will silently be overwritten.Created a branchPress ⌘Z.Run git branch -d BRANCH_NAME.Deleted a branchPress ⌘Z.Find the output of the git branch -d command to undo. Copy the commit hash. Run git branch BRANCH_NAME COPIED_HASH.Staged a filePress ⌘Z.To unstage the whole file, run git restore --staged FILE_PATH. To unstage specific hunks, instead run git reset -p FILE_PATH, and manually select the hunks.Unstaged a filePress ⌘Z.To stage the whole file, run git add FILE_PATH. To stage specific hunks, instead run git add -p FILE_PATH, and manually select the hunks. If some of the staged changes were not in the working directory, they cannot be recovered.Confirmed a conflict resolutionPress ⌘Z.Abort the current rebase by running git rebase --abort. Restart the rebase from scratch. Recreate the same rebase list, perform the same message edits, and redo every conflict resolution yourself.

---
there is also 
https://github.com/f/git-rewrite-commits which is a repo i included as many items ads i could

---

here's the kicker now: claude code skills are the new big thing and i want to create a mechanism to remplace these tools completely with the  custom functionality of a claude code skill
read up on how to create new claude code cli skills. in my case i wsant ot instead of "recall": git history editing and improving.

Show less
Mar 1

Synthesized git tools into unified Claude Code skill concept
Synthesized git tools into unified Claude Code skill concept
Let me first read up on how to create Claude Code skills properly, then design your comprehensive git history skill.


Investigated Claude Code skill implementation for git workflow automation
Investigated Claude Code skill implementation for git workflow automation
Now let me search for current info on Claude Code custom skills to make sure I have the latest approach.


Architected comprehensive git-recall skill merging undo, rewriting, and history editing
Architected comprehensive git-recall skill merging undo, rewriting, and history editing
Now I have a thorough understanding of both the tools you want to replace and how Claude Code skills work. Let me build this comprehensive skill.


Synthesized git tools into unified Claude code skill concept
Synthesized git tools into unified Claude code skill concept
Here's your git-recall skill — a single Claude Code skill that replaces both Retcon and git-rewrite-commits.

What it does
Retcon replacement — every undo operation from their cheatsheet (undo commit, undo rebase, undo push, undo branch delete, undo staging, undo conflict resolution) is covered in references/undo-operations.md with the full reflog recovery playbook.

git-rewrite-commits replacement — instead of piping diffs to OpenAI/Ollama through npm, Claude is the AI. It reads the diffs directly, generates conventional commit messages, and applies them via interactive rebase or filter-branch. No API keys, no npm install, no rate limiting.

Plus — interactive rebase automation, commit splitting, transplanting, author changes, bisect, pre-PR cleanup workflows, and emergency recovery from any state.

Structure
git-recall/
├── SKILL.md                          # Core instructions + safety protocol
├── references/
│   ├── undo-operations.md            # Every undo scenario (Retcon replacement)
│   ├── commit-rewriting.md           # AI message generation guide
│   └── history-editing.md            # Complex rebase/reorder/squash procedures
└── scripts/
    ├── assess-commits.sh             # Scan & score commit quality
    └── safe-rewrite.sh               # Batch rewrite with backup & recovery
Installation
Drop the git-recall folder into either location:

bash
# Personal (all projects)
~/.claude/skills/git-recall/

# Per-project
.claude/skills/git-recall/
Then in Claude Code, it triggers automatically when you say things like "undo my last commit", "fix my commit messages", "clean up my branch", or explicitly with /git-recall.

Git recall
ZIP 
Skill
Document · MD 
Undo operations
Document · MD 
Commit rewriting
Document · MD 
History editing
Document · MD 
Assess commits
SH 
Safe rewrite
SH 





Claude is AI and can make mistakes. Please double-check cited sources.


