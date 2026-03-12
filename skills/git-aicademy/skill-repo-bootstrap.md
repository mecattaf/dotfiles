---
name: repo-bootstrap
description: >-
  Set up a professional GitHub-native workflow for any repository. Creates CI/CD workflows,
  release automation, issue templates, PR templates, conventional commit enforcement,
  and Claude Code Action integration. Use when the user says: "set up this repo",
  "make this production-ready", "add CI/CD", "add release automation",
  "bootstrap", "git utility belt", "add GitHub Actions", "set up conventional commits",
  "add issue templates", "add PR template", or any request to standardize a repo's
  development workflow.
---

# repo-bootstrap: Professional Repository Setup

Set up a complete GitHub-native development workflow in one pass. No local npm installs, no pre-commit hooks — everything runs in GitHub's cloud infrastructure.

## Philosophy

A repo should be production-ready from day one. That means: CI that runs on every PR, releases that bump automatically from commit messages, issue templates that give Claude (and humans) enough context to work, and PR templates that enforce linking to issues. This skill creates all of it.

## Before Starting

1. **Confirm the project type** — detect package manager, language, test framework
2. **Check what already exists** — `ls .github/` to avoid overwriting custom workflows
3. **Ask about deployment** — some repos need deploy workflows, most don't at bootstrap time
4. **Confirm the main branch name** — `main` vs `master` vs something else

## What Gets Created

### Tier 1: Always Created

These files form the minimum viable professional workflow:

#### `.github/workflows/ci.yml`
Runs lint, test, and build on every PR and push to main.
Detect the project's package manager and test framework first.

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4  # adjust for language
        with:
          node-version: 20
      - run: npm ci          # or pnpm install --frozen-lockfile
      - run: npm run lint    # if lint script exists
      - run: npm test        # if test script exists
      - run: npm run build   # if build script exists
```

#### `.github/workflows/release-please.yml`
Automated semantic versioning from conventional commits.

```yaml
name: Release Please
on:
  push:
    branches: [main]

permissions:
  contents: write
  pull-requests: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        with:
          release-type: node  # adjust per project
```

#### `.github/ISSUE_TEMPLATE/bug_report.yml`
Structured bug reports with fields for reproduction steps, expected behavior, and environment.

#### `.github/ISSUE_TEMPLATE/feature_request.yml`
Feature requests with fields for problem statement, proposed solution, acceptance criteria, and technical context (for Claude).

#### `.github/pull_request_template.md`
```markdown
## Description
<!-- What does this PR do? -->

## Related Issue
<!-- Closes #N -->

## Type of Change
- [ ] Bug fix (patch)
- [ ] New feature (minor)
- [ ] Breaking change (major)

## Checklist
- [ ] Tests pass
- [ ] Conventional commit format used
- [ ] Documentation updated (if applicable)
```

#### `CLAUDE.md` (if not present)
Minimal project-specific instructions for Claude Code.

```markdown
# CLAUDE.md

## Project Overview
<!-- Brief description -->

## Commands
<!-- Key commands: build, test, lint, dev -->

## Conventions
- Use conventional commits: type(scope): description
- Reference issues in commits: Closes #N
- Branch naming: type/issue-number-description
```

### Tier 2: Created on Request

These are offered but not created by default:

#### `.github/workflows/claude-pr-assistant.yml`
Claude Code Action for AI-assisted PR review and implementation.
**Requires**: `ANTHROPIC_API_KEY` repository secret.

```yaml
name: Claude PR Assistant
on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened, assigned]

jobs:
  claude:
    if: contains(github.event.comment.body, '@claude') || contains(github.event.issue.body, '@claude')
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: read
      issues: read
      id-token: write
    steps:
      - uses: anthropics/claude-code-action@beta
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          custom_instructions: |
            Follow the repository's CLAUDE.md for project-specific guidelines.
            Use conventional commit messages for all commits.
```

#### `.github/semantic.yml`
Conventional commit enforcement on PR titles.

#### `.github/workflows/deploy.yml`
Deployment workflow (Vercel, Cloudflare Pages, etc.) — only if the user specifies a platform.

### Tier 3: Changelog Website (Starlight)

If the user wants a public changelog site, scaffold the starlight-changelogs integration:

```
docs/
├── astro.config.ts        # Starlight + changelogs plugin
├── package.json
├── src/
│   └── content.config.ts  # changelogsLoader configuration
└── tsconfig.json
```

The content config connects to GitHub releases:
```typescript
changelogsLoader([
  {
    provider: 'github',
    base: 'changelog',
    owner: '<detected-from-git-remote>',
    repo: '<detected-from-git-remote>',
    title: 'Version History',
    process: ({ title }) => title.replace(/^v/, '')
  }
])
```

## How to Handle Requests

**"Set up this repo"** → Run full Tier 1. Offer Tier 2.

**"Add CI/CD"** → Create `ci.yml` only. Mention release-please as a natural next step.

**"Add release automation"** → Create `release-please.yml`. Check if CI exists; if not, suggest it.

**"Make this production-ready"** → Full Tier 1 + Tier 2. Offer Tier 3.

**"Add the Claude GitHub Action"** → Create `claude-pr-assistant.yml`. Remind about the API key secret.

**"I want a changelog website"** → Tier 3. Requires Tier 1 release-please to be in place.

## Detection Logic

Before creating files, detect:

```bash
# Package manager
[ -f "pnpm-lock.yaml" ] && echo "pnpm"
[ -f "yarn.lock" ] && echo "yarn"
[ -f "bun.lockb" ] && echo "bun"
[ -f "package-lock.json" ] && echo "npm"

# Language / framework
[ -f "package.json" ] && echo "node"
[ -f "Cargo.toml" ] && echo "rust"
[ -f "go.mod" ] && echo "go"
[ -f "pyproject.toml" ] && echo "python"

# Existing scripts (from package.json)
node -e "const p=require('./package.json'); console.log(Object.keys(p.scripts||{}).join(','))"

# Main branch
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'

# Remote owner/repo
git remote get-url origin | sed -E 's#.+github\.com[:/](.+)/(.+?)(\.git)?$#\1/\2#'
```

## What This Skill Does NOT Do

- Does not install local dependencies (no `npm install`, no husky)
- Does not create pre-commit hooks (enforcement happens in CI, not locally)
- Does not set up deployment (unless explicitly asked)
- Does not modify existing workflows (warns and asks first)
- Does not add repository secrets (tells the user how to do it)

## Post-Setup Checklist

After creating files, remind the user:

1. **Add secrets** if Claude Action was created: Settings → Secrets → `ANTHROPIC_API_KEY`
2. **Create initial labels**: `type:feat`, `type:fix`, `type:chore`, `priority:high/medium/low`
3. **Create first milestone**: aligned with the next semantic version
4. **Push and verify**: the CI workflow should trigger on the next PR
