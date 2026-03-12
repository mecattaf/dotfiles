---
name: release-flow
description: >-
  Manage the full release pipeline: release-please configuration, changelog enhancement,
  and public changelog websites via starlight-changelogs. Use when the user mentions:
  "release", "version bump", "changelog", "release notes", "cut a release",
  "publish version", "release-please", "starlight-changelogs", "changelog website",
  "public changelog", "version history page", or any request to automate versioning,
  generate release notes, or display changelogs on a documentation site.
---

# release-flow: Releases and Public Changelogs

Automate the path from merged PR to published release with human-readable notes and an optional public changelog website.

## Philosophy

Releases should be boring. Conventional commits drive version bumps. Changelogs write themselves. The only human decision is "merge the release PR or not." This skill makes that happen and optionally publishes the result as a browsable website.

## Three Modes

### Mode 1: Setup

**Trigger**: "set up releases", "add release automation", "configure release-please"

1. Check if `release-please.yml` workflow exists (may already exist from `repo-bootstrap`)
2. If not, create it with appropriate `release-type` for the project
3. Configure changelog sections:

```yaml
changelog-sections: |
  {"type":"feat","section":"Features","hidden":false},
  {"type":"fix","section":"Bug Fixes","hidden":false},
  {"type":"perf","section":"Performance","hidden":false},
  {"type":"docs","section":"Documentation","hidden":false},
  {"type":"refactor","section":"Under the Hood","hidden":true},
  {"type":"chore","section":"Maintenance","hidden":true},
  {"type":"test","section":"Testing","hidden":true},
  {"type":"ci","section":"CI/CD","hidden":true}
```

4. Verify conventional commits are being used: `git log --oneline -20`
5. If not, warn and suggest `commit-craft` skill

### Mode 2: Enhancement

**Trigger**: "improve release notes", "make the changelog readable", "enhance the release PR"

When release-please creates a release PR, its changelog is raw commit messages. This mode rewrites them:

**Before** (auto-generated):
```
## Features
* add JWT token validation middleware (abc1234)
* implement user profile endpoint (def5678)

## Bug Fixes
* handle null user ID in profile endpoint (ghi9012)
```

**After** (enhanced):
```
## Features
* **Authentication**: Added JWT token validation for protected API routes,
  including automatic refresh token rotation
* **User Profiles**: New `/api/users/:id` endpoint for retrieving and
  updating user profile data

## Bug Fixes
* **API**: Fixed a crash when accessing user profiles with missing IDs —
  now returns a proper 404 response
```

Enhancement process:
1. Read the release PR diff
2. For each changelog entry, fetch the original commit diff: `git diff-tree -p <hash>`
3. Rewrite in plain language: what does the user get, not what files changed
4. Add migration notes for any `BREAKING CHANGE` footers
5. Update the release PR

### Mode 3: Publish (Starlight Changelogs)

**Trigger**: "changelog website", "public changelog", "display releases on site"

Scaffold a starlight-changelogs site that pulls from GitHub releases:

#### Minimal Setup

```bash
# In project root or docs/ directory
npm create astro@latest -- --template starlight docs
cd docs
npm install starlight-changelogs
```

#### Content Config

```typescript
// docs/src/content.config.ts
import { docsLoader } from '@astrojs/starlight/loaders'
import { docsSchema } from '@astrojs/starlight/schema'
import { defineCollection } from 'astro:content'
import { changelogsLoader } from 'starlight-changelogs/loader'

export const collections = {
  docs: defineCollection({ loader: docsLoader(), schema: docsSchema() }),
  changelogs: defineCollection({
    loader: changelogsLoader([
      {
        provider: 'github',
        base: 'changelog',
        owner: '<owner>',      // detected from git remote
        repo: '<repo>',        // detected from git remote
        title: 'Version History',
        process: ({ title }) => title.replace(/^v/, '')
      }
    ])
  })
}
```

#### Astro Config

```typescript
// docs/astro.config.ts
import starlight from '@astrojs/starlight'
import { defineConfig } from 'astro/config'
import starlightChangelogs, { makeChangelogsSidebarLinks } from 'starlight-changelogs'

export default defineConfig({
  integrations: [
    starlight({
      plugins: [starlightChangelogs()],
      title: '<Project Name>',
      sidebar: [
        // ... existing sidebar items
        {
          label: 'Changelog',
          items: [
            ...makeChangelogsSidebarLinks([
              { type: 'all', base: 'changelog', label: 'All Versions' },
              { type: 'latest', base: 'changelog', label: 'Latest' }
            ])
          ]
        }
      ]
    })
  ]
})
```

#### Provider Options

| Source | Provider | When to Use |
|--------|----------|-------------|
| GitHub Releases | `'github'` | Most repos — release-please creates these automatically |
| Changesets CHANGELOG.md | `'changeset'` | Monorepos using changesets |
| Keep a Changelog format | `'keep-a-changelog'` | Manual changelogs following keepachangelog.com |
| Gitea Releases | `'gitea'` | Self-hosted Gitea/Codeberg |

#### Deployment

Add a deploy workflow for the docs site:

```yaml
# .github/workflows/deploy-docs.yml
name: Deploy Docs
on:
  release:
    types: [published]
  push:
    branches: [main]
    paths: ['docs/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - run: cd docs && npm ci && npm run build
      # Deploy to Cloudflare Pages, Vercel, Netlify, etc.
```

## Release Workflow End-to-End

```
Developer merges PR with conventional commits
        │
        ▼
release-please Action triggers
        │
        ▼
Analyzes commits since last release
        │
        ▼
Creates/updates release PR:
  - Bumps version in package.json (or equivalent)
  - Generates CHANGELOG.md entries
  - PR title: "chore(release): vX.Y.Z"
        │
        ▼
[Optional] release-flow enhances changelog text
        │
        ▼
Developer reviews and merges release PR
        │
        ▼
GitHub Release published with tag
        │
        ▼
[Optional] Starlight site rebuilds, shows new version
```

## Version Bump Rules

| Commit Type | Version Bump | Example |
|-------------|-------------|---------|
| `fix:` | Patch (0.0.X) | `1.2.3` → `1.2.4` |
| `feat:` | Minor (0.X.0) | `1.2.3` → `1.3.0` |
| `feat!:` or `BREAKING CHANGE:` | Major (X.0.0) | `1.2.3` → `2.0.0` |
| `docs:`, `style:`, `refactor:`, `test:`, `chore:` | No bump (hidden) | — |
| `perf:` | Patch | `1.2.3` → `1.2.4` |

## Safety Rules

1. **Never manually edit CHANGELOG.md** — release-please manages it
2. **Don't rewrite commits on main** after release-please has parsed them
3. **Review the release PR** before merging — automated ≠ correct
4. **Use `process` option** in starlight-changelogs to filter monorepo noise
5. **Set up a GitHub token** for the changelog site if the repo is private

## Integration Points

- **repo-bootstrap**: Creates the initial `release-please.yml` workflow
- **commit-craft**: Ensures commits follow the format release-please expects
- **git-recall**: Can clean up branch history before merge, but NOT after release-please has parsed main
- **docs-drift**: Can verify changelog entries match what was actually shipped
