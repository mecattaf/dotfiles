# OSS Workflow Skills Plan

## The Goal

Reproduce the consistency of a top-1% OSS contributor — conventional commits, automated releases, public changelogs, clean PR hygiene, documentation that stays current — but through Claude Code skills instead of manual discipline or specialized TUI tooling.

## What Already Exists (from ECC)

| ECC Skill | Covers | Gap |
|-----------|--------|-----|
| `coding-standards` | Code quality, naming, immutability | No git workflow or commit standards |
| `tdd-workflow` | Test-driven development | No CI/CD setup |
| `verification-loop` | Build/lint/type/test checks | No release or changelog verification |
| `security-review` | Input validation, secrets, auth | Doesn't cover repo-level security config |
| `eval-harness` | Eval-driven development | No integration with GitHub Issues |
| `strategic-compact` | Context management | — |

**What's missing from ECC**: Everything related to the git/GitHub workflow layer — the stuff your 2025 blog was entirely about. ECC optimizes *how Claude writes code* but doesn't address *how code gets committed, released, documented, and published*.

## Proposed Skills (5 new, 1 existing enhancement)

### 1. `repo-bootstrap` — One command to set up a professional repo

**Maps to 2025 idea**: "Git Utility Belt", "reproducible process to set up each repo", the entire `git-utility-belt/` structure

**What it does**: When someone says "set up this repo" or "make this repo production-ready", it creates the full GitHub-native automation scaffold.

**Creates**:
- `.github/workflows/ci.yml` — lint, test, build on PR
- `.github/workflows/release-please.yml` — automated versioning
- `.github/workflows/claude-pr-assistant.yml` — Claude Code Action
- `.github/ISSUE_TEMPLATE/bug_report.yml`
- `.github/ISSUE_TEMPLATE/feature_request.yml`
- `.github/pull_request_template.md`
- `CLAUDE.md` — project-specific Claude instructions
- `.github/semantic.yml` — conventional commit enforcement on PRs

**Doesn't create** (leaves to user): CI-specific test commands, deployment workflows, project-specific CLAUDE.md content.

---

### 2. `commit-craft` — Generate good commits the first time

**Maps to 2025 idea**: The conventional commits sections, the Neogit commit template workflow, git-recall's "commit message improvement" capability but at creation time

**Complementary to**: `git-recall` (which rewrites history after the fact)

**What it does**: Analyzes staged changes and generates conventional commit messages. Links to issues when branch names follow `type/issue-description` pattern.

**Key behaviors**:
- `git diff --cached` → analyze → suggest `type(scope): description`
- Detect issue references from branch name (`fix/234-cast-user-age` → `Closes #234`)
- Respect `COMMIT_MESSAGE.md` if present in repo
- Quality-score the message before committing (same rubric as git-recall)
- Support batch commits: split large staging areas into atomic conventional commits

---

### 3. `release-flow` — Automated releases with public changelogs

**Maps to 2025 idea**: Release-please setup, changelog creation, the starlight-changelogs display pattern

**What it does**: Sets up and manages the full release pipeline — from conventional commits through to a published changelog website.

**Three modes**:

**Setup mode** ("set up releases for this repo"):
- Configure `release-please` workflow
- Set up changelog sections mapping (feat→Features, fix→Bug Fixes, etc.)
- Optionally scaffold a starlight-changelogs site that pulls from GitHub releases

**Enhancement mode** ("improve the release notes"):
- Read the auto-generated changelog PR from release-please
- Rewrite entries to be user-friendly (not raw commit messages)
- Add migration guides for breaking changes
- Categorize by user impact, not commit type

**Publish mode** ("deploy the changelog"):
- Build the starlight site
- Configure provider (changeset file, GitHub releases, or keep-a-changelog)
- Set up sidebar links using `makeChangelogsSidebarLinks()`

**starlight-changelogs integration** (from the HiDeoo project):
```typescript
// The key config this skill generates
changelogsLoader([
  {
    provider: 'github',
    base: 'changelog',
    owner: 'username',
    repo: 'project',
    title: 'Version History',
    process: ({ title }) => title.replace(/^v/, '')
  }
])
```

---

### 4. `docs-drift` — Detect documentation rot

**Maps to 2025 idea**: "documentation back and forth", the prompt about scanning for gaps/inconsistencies/contradictions, the hashicorp "docs impact assessment" pattern

**What it does**: Scans for drift between documentation and implementation. Runs as an audit, produces actionable findings.

**Scans for**:
- API endpoints documented but not implemented (or vice versa)
- README instructions that reference removed commands or changed paths
- CLAUDE.md conventions that contradict actual code patterns
- Architecture docs that describe components that have been restructured
- Stale TODO comments that reference completed or abandoned issues

**Output**: A structured report with three sections:
1. **Gaps** — things in code but not in docs (or vice versa)
2. **Inconsistencies** — docs say X, code does Y
3. **Stale references** — links, paths, or instructions that no longer work

**Trigger patterns**: "check docs", "audit documentation", "is the README current", "scan for drift"

---

### 5. `issue-to-pr` — Issue-driven development workflow

**Maps to 2025 idea**: "1 issue → 1 task achieved", "issues are prompts for Claude", the Claude Code Action workflow, the full Neogit+Octo flow

**What it does**: Takes a GitHub issue and executes the full development cycle — branch creation, implementation, conventional commits, PR creation — following the pattern your 2025 blog described but without the Neovim tooling.

**Workflow**:
1. Read issue content (via `gh issue view`)
2. Create branch: `type/issue-number-description`
3. Implement (this is where Claude Code does its thing)
4. Commit with conventional format, referencing the issue
5. Push and create PR with structured template
6. Link PR to issue (`Closes #N`)

**Safety rails**:
- Checks if branch already exists for this issue
- Validates that changes address what the issue asked for
- Runs verification loop before PR creation
- Uses `--force-with-lease` if history needs updating

**Integration**: Works with `commit-craft` for message generation, `verification-loop` for pre-PR checks, and `git-recall` if commit cleanup is needed.

---

### 6. `git-recall` enhancement — Add safety backup to starlight-changelogs

**Already exists** (documents 1-5), but add awareness of:
- The release-please workflow (don't rewrite commits that release-please has already parsed)
- The `repo-bootstrap` conventions (branch naming, PR templates)
- Integration with `commit-craft` for the rewriting step

---

## How They Compose

```
Issue created on GitHub
        │
        ▼
   issue-to-pr          ← reads issue, creates branch
        │
        ▼
   [Claude codes]       ← normal Claude Code work
        │
        ▼
   commit-craft         ← stages → analyzes → conventional commit
        │
        ▼
   verification-loop    ← (from ECC) build/test/lint check
        │
        ▼
   git-recall           ← (if needed) clean up before PR
        │
        ▼
   PR created & merged
        │
        ▼
   release-please       ← (GitHub Action) bumps version, changelog PR
        │
        ▼
   release-flow         ← enhances changelog, builds starlight site
        │
        ▼
   docs-drift           ← (periodic) checks docs still match code
```

## What This Replaces from 2025

| 2025 Approach | 2026 Skill |
|---------------|------------|
| Neogit `b c` with custom `create_branch_shell` | `issue-to-pr` reads issue, names branch |
| `~/.gitmessage.txt` commit template | `commit-craft` generates from diff |
| commitlint + husky hooks | `commit-craft` quality scoring + `repo-bootstrap` CI enforcement |
| Octo.nvim `:Octo pr create` | `issue-to-pr` creates PR via `gh` CLI |
| Octo.nvim `:Octo pr list label:chore/release` | `release-flow` manages release PRs |
| Manual changelog curation | `release-flow` + starlight-changelogs |
| Periodic manual doc review | `docs-drift` automated scanning |
| Diffview for PR review | `git-recall` + `verification-loop` |
| `git config --global commit.template` | `commit-craft` (no config needed) |
| Custom Neogit branch menu lua functions | `issue-to-pr` (just describe the issue) |

## Mapping to ECC Structure

Each skill follows the ECC pattern:
```
.agents/skills/skill-name/
├── SKILL.md              ← Main skill definition
├── agents/
│   └── openai.yaml       ← Cross-platform agent config
├── references/            ← (optional) detailed playbooks
│   └── *.md
└── scripts/               ← (optional) helper scripts
    └── *.sh
```

## What Stays as GitHub Actions (Not Skills)

These remain cloud-side guardrails, not local skills:
- **release-please** — runs on push to main, creates release PRs
- **semantic PR validation** — enforces conventional commit titles on PRs
- **CI pipeline** — lint/test/build (the `repo-bootstrap` skill creates these)
- **Claude Code Action** — triggered by `@claude` in issues/PRs

The skills *set up* these actions (`repo-bootstrap`) and *interact with their output* (`release-flow`), but the actions themselves run in GitHub's infrastructure.

## Priority Order

1. **`repo-bootstrap`** — highest leverage, sets up everything else
2. **`commit-craft`** — daily use, every commit benefits
3. **`issue-to-pr`** — the main development loop
4. **`release-flow`** — completes the automation chain
5. **`docs-drift`** — periodic maintenance
6. **`git-recall` enhancement** — already exists, just needs integration points
