## Context

Back in summer 2025 I had started writing/ideating about a workflow where lots of the open-source developer activities are automated. Now revisiting that almost a year later, I find that this is now more feasible than ever. in the aicademy-2025 folder you will find what i had previously written.

### Recent chat

Below find a recent llm chat which produced some sample skills. I aim to expand on that more:

---




--- name: git-recall description: >- Git history editing, undoing, rewriting, and improving — all through Claude Code. Replaces tools like Retcon, git-rewrite-commits, and manual git reflog gymnastics. Use this skill whenever the user mentions: undoing a commit, rewriting commit messages, cl

pasted


# Undo Operations Reference Complete playbook for undoing any git operation. This is the Retcon replacement — every operation mapped to its undo. ## The Universal Recovery Tool: git reflog `git reflog` shows every place HEAD has pointed to. It's the ultimate safety net. Entries expire after 90 da

pasted


# Commit Message Rewriting Reference Guide for analyzing and improving commit messages using Claude's own intelligence — no external API calls needed. ## Quality Assessment Before rewriting, assess existing commit quality. A commit message is well-formed if it scores 7+ on this scale: | Criteria

pasted


# History Editing Reference Detailed procedures for complex git history manipulation. ## Interactive Rebase Master Guide Interactive rebase (`git rebase -i`) is the Swiss Army knife of history editing. It operates on a sequence of commits and lets you reorder, edit, squash, split, or drop any of

pasted


# History Editing Reference Detailed procedures for complex git history manipulation. ## Interactive Rebase Master Guide Interactive rebase (`git rebase -i`) is the Swiss Army knife of history editing. It operates on a sequence of commits and lets you reorder, edit, squash, split, or drop any of

pasted

mecattaf/aicademy.so
main

GITHUB

peruse all the contents of what was a blog i was preparing back in 2025 on how to code using ai
the key ideas are how we "keep the old school dev workflows" like convensional commits, commit please and others
these are normally .github/workflows or .git items ; i believe so whether claude code has the ability to use them directly or not i m not too sure these days
and some comments on how to leverage nvim modules to make that happen. those have become way less relevant becuase i no longer need specialized tui tools with shortcuts - skills lets us do things in separate way.

in 2026 this game has changed. we instead use claude code skills to make these things happen.
i already started a skill to make "retcon" (a git history edititng tool) so you can use taht as maybe inspiration for this module.

Show less
Mar 1

Synthesized legacy workflows' evolution from Neovim tooling toward Claude Code skills architecture
Synthesized legacy workflows' evolution from Neovim tooling toward Claude Code skills architecture
This is a fascinating time capsule. Having read through everything, here's my read on where things stand:

What aged well
The core philosophy is more relevant than ever. The ideas that held up:

Conventional commits as the spine of automation — still true. Release-please, changelogs, and semantic versioning all still flow from well-structured commit messages. The difference is Claude Code now writes those commits natively rather than needing commitlint hooks to enforce them.
Issue-driven development (1 issue → 1 task) — this maps perfectly to how Claude Code works today. An issue is essentially a prompt with context. Your 2025 insight that "issues are prompts for Claude" was prescient.
Documentation drift detection — the back-and-forth between docs and code is still a real problem. Skills could automate this scanning.
The "3-strike rule" and context window management from the Reddit post — still practical advice for anyone using AI coding tools.
What's been superseded
The entire Neovim plugin stack for GitHub interaction (Octo.nvim, Neogit keybindings, Diffview for PR review, custom branch creation functions). You nailed it — skills replace all of this. Instead of memorizing b c → prompt → type → description, you just say "create a feature branch for issue 234 about user auth."
Local git hooks for commit validation — Claude Code already knows conventional commit format. The git-recall skill you started handles the rewriting side. A complementary skill could handle the creation side (always writing good commits from the start).
The elaborate Neogit + Octo "full flow cheat sheet" — that 11-step workflow collapses to maybe 3 steps with skills: "implement issue #234", "clean up and PR", "merge."
What could become skills
Looking at your git-recall skill as the template, here's what I see as natural skill candidates from your old material:

1. A "git-utility-belt" skill — the repo setup/standardization piece. When someone says "set up this repo for conventional commits and release-please," the skill knows the exact .github/workflows/ files to create, the semantic.yml config, issue templates, PR templates. This is your "reproducible process to set up each repo" idea, but as a skill instead of a CLI script.

2. A "commit-craft" skill (complementary to git-recall) — git-recall handles rewriting history, but you also need a skill for creating commits well the first time. Analyzing staged changes, generating conventional commit messages, linking to issues automatically.

3. A "release-flow" skill — wrapping release-please configuration, changelog enhancement, and the review/merge of release PRs. Your 2025 notes about Claude enhancing changelogs with "user-friendly descriptions" and "migration guides" is exactly what a skill could do.

4. A "docs-drift" skill — your documentation back-and-forth idea. Periodically scan for gaps between CLAUDE.md / architecture docs and actual implementation. The prompt you had ("please thoroughly evaluate everything you see...") could be the core of this skill.

The key shift
Your 2025 architecture was: Neovim plugins → GitHub API → GitHub Actions → Claude (as one actor among many)

The 2026 architecture is: Claude Code (with skills) → git directly + GitHub API — Claude becomes the orchestrator rather than one node in a pipeline. The .github/workflows still run in CI, but the local development loop no longer needs specialized TUI tooling as an intermediary.

The GitHub Actions themselves (release-please, CI, conventional commit enforcement) are still valuable as guardrails in CI — they catch things on the server side. But the local workflow is now just "talk to Claude." Your insight about "cloud-first, laptops become just editors" was right, it just turned out the "editor" is Claude Code rather than a heavily configured Neovim.

Want me to draft any of these as actual skill files, using your git-recall structure as the pattern?

you correctly identified the desired skills. those and things like release-please and the ability to have better "build in public" best practices like maintaining achangelog that immeidately gets shown on the dedicdaed website like https://github.com/HiDeoo/starlight-changelogs

the idea here is that we would observe the same consistency in building code as what a top 1% oss controbutour would have done in 2023 but without all the effort. i use as reference te everything-claude-code project which has gained a lot of popularity these days. it's a dev's full toolkit

i include both repo contents (as much as i can) so you can get a sense of what's already there. this is the methodolofgy, and may correspond to your "what could become skills" section

Mar 1

Synthesized blog ideas into concrete Claude Code skills using existing project patterns
Synthesized blog ideas into concrete Claude Code skills using existing project patterns
Looking at everything together — your 2025 blog content, the git-recall skill structure, ECC's methodology, and the starlight-changelogs pattern — I can now map this precisely. Let me produce the concrete plan.


Prioritized foundational skills to scaffold professional development practices
Prioritized foundational skills to scaffold professional development practices
Now let me draft the two highest-priority skill files:

Oss workflow skills plan
Document · MD 
Skill
Document · MD 
Skill
Document · MD 
Skill
Document · MD 

Prepared outputs for delivery
Prepared outputs for delivery
Claude's response could not be fully generated


continue

Claude is AI and can make mistakes. Please double-check responses.












