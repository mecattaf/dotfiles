distinction between documentation and wiki; for the project, it’s about who the audience is: LLM or human?
All managed from a CLAUDE.md file. see references to stripe and hashicorp gh actions how they do it

Another paradigm to consider is on the project mgmt side of things. How do we blend GH issues (not visible from .git) and items like CHANGELOGs

→ Idea/philosophy is to keep extra-code items in github (reliance:
- wiki (we go back & forth from)
- issues / branch / PR
- workflows is the absolute KEY here, core of any automation...

→ Making sure we have a Reproducible process to set up each repo for a CLI command / PR / simple batch script at least...

→ Convergent coding philosophy revolves around Schema-driven configuration, meaning that we keep a single-source of truth and
keep utilities that convert the json files to functional web apps.
(Philosophy: Minimize work that can be part of LLM and rely on as many Mechanical automations as we can.)

To-do lists should never appear on a markdown file in the repo. For incremental, specific changes that are not implemented yet, we use Gh Issues.
Code changes get moved around in PR/Branches (automatically done by Claude Code Gh Action).
The paradigm goes from 1 chat > 1 goal to 1 issue > 1 task achieved

---
[brought over from mecattaf.dev]


scoping the nvim workflow consists of first making sure that the github `gh` cli is authenticated with the right permissions. 
```
# Verify GitHub CLI authentication
gh auth status

# If not authenticated:
gh auth login

# Add necessary scopes for Octo.nvim
gh auth refresh -s read:project
```
currently i see 
```
gh auth status
github.com
  ✓ Logged in to github.com account mecattaf (keyring)
  - Active account: true
  - Git operations protocol: https
  - Token: gho_************************************
  - Token scopes: 'gist', 'read:org', 'read:project', 'repo', 'workflow'
```


```
Here's a list of all the non-AI automations you'll be using in your Git Utility Belt setup—these are GitHub-native and run entirely in the cloud via GitHub Actions:


---

Non-AI Automations

1. Conventional Commits Enforcement

Tool: Semantic Pull Requests GitHub App

File: .github/semantic.yml

What It Does:

Ensures all PR titles follow Conventional Commits (e.g. feat:, fix:)

Blocks merges of non-conforming PRs

Provides auto-comments on violations




---

2. Release Automation

Tool: release-please

File: .github/workflows/release-please.yml

What It Does:

Scans merged commits for semantic prefixes

Bumps package.json (or similar) version automatically

Creates/updates CHANGELOG.md

Opens release PRs or publishes tags (depending on setup)




---

3. CI/CD Pipeline

Tool: GitHub Actions (ci.yml)

File: .github/workflows/ci.yml

What It Does:

Runs on push/PR

Executes:

Linting (eslint, prettier, etc.)

Testing (vitest, jest, etc.)

Build step (tsc, vite, next build, etc.)





---

4. Optional: Deployment

Tool: Custom deploy.yml

File: .github/workflows/deploy.yml

What It Does:

Runs on push to main or on new release

Deploys to platforms like Vercel, Netlify, or Cloudflare Pages

Authenticated via GitHub Secrets




---

5. Optional: Scheduled Cleanup

Tool: Custom clean.yml

File: .github/workflows/clean.yml

What It Does:

Runs on a schedule (e.g. nightly)

Can clean up:

Preview deployments

Old PR branches

Unused Docker images, etc.





---

6. Issue & PR Templates

Tool: GitHub-native templating system

Files:

.github/ISSUE_TEMPLATE/*.yml

.github/pull_request_template.md


What It Does:

Provides structure for all new issues and PRs

Encourages linking to milestones

Prompts consistent formatting and labels




---

7. Labels & Milestones Management

Tool: Manual with GitHub UI (or optionally via scripts)

Setup:

Standard labels (e.g. type: bug, status: in progress, priority: high)

Milestones aligned with semantic version numbers


What It Enables:

Clear project tracking and planning

Retrospective reporting based on closed milestone issues




---

Seeems like those tools went out of fashion somehow. When were they big? Why did they go out of fashion?
```


some more items:
# Agentic Coding: The GitHub Actions Advantage

**Why everything runs in the cloud, not locally**

The entire workflow operates through GitHub Actions - no local npm installs, no pre-commit hooks, no environment setup required. Every automation (commit validation, versioning, deployments) executes in GitHub's cloud infrastructure when code is pushed or PRs are merged. Laptops become just editors; all heavy lifting happens server-side.

## What Actions Should Handle

• **Parallel Execution**: Frontend tests, backend tests, and documentation checks run simultaneously across different runner environments

• **Conditional Workflows**: Deploy to staging on PR creation, production only on release tags, cleanup on PR closure

• **Cross-Repository Triggers**: Update documentation sites when API schemas change, notify dependent projects of breaking changes

• **Secret Rotation**: Automatically refresh API tokens and deployment keys without manual intervention

• **Matrix Builds**: Test against multiple Node/Python versions or deployment targets in parallel

• **Failure Recovery**: Automatically retry flaky steps, rollback failed deployments, create issues for broken builds

The result: developers write code and open PRs. Everything else - from version bumping to production deployment - happens automatically based on commit messages and merge actions. This cloud-first approach eliminates "works on my machine" problems while maintaining enterprise-grade automation standards.




