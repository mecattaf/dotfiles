## context
this is where i attempt to capture maximal context about the way that i write code in a way that is assisted by ai agents.
there are several components to this document, which will be released as a markdown documentation for technical people to be able to understand how i code using ai in 2025.

this is in the context of preparing a unified cli tool that runs locally that i can run on my 30+ existing github repositories such that they can now be maintained by ai moving forward: specifically the claude code github action

### 1) old-school github action-based workflows
A - conventional commits drive automatic version bumping
as a rule, commit messages always references an issue. this is automatically done with claude code github action.
B - release-please for automated semantic versioning
C - automated changelog creation: this is built-in with tools like release please
keeping this consistently and having these releases bump versions automatically removes a lot of the high level management
we also use a cloudflare pages-deployed decicated astro starlight package to display the changelogs

other specialized tools include github action driven workflows where we maximally leverge builds with reusable patterns

workflow chaining: once each atomic workflow is tested and confirmed we can work on orchestration and caching

##### gh actions of interest:

| **Action**                                   | **Purpose**                                                                                                 | **Substitute / Overlap**                                                                                                                                                                                     |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `anthropics/claude-code-action`              | Listens to `@claude` in issues or comments, generates a branch + PR via Claude in response to goals/issues. | No direct substitute—this is your AI-driven PR generator.                                                                                                                                                    |
| `amannn/action-semantic-pull-request`        | Validates PR titles follow Conventional Commits (`feat:`, `fix:`, etc.).                                    | Substitute: `step-security/action-semantic-pull-request` (more secure, API-compatible). Overlaps with other PR-lint tools like `jonlabelle/commit-check-action`. ([github.com][1], [app.stepsecurity.io][2]) |
| `CondeNast/conventional-pull-request-action` | Lints PR title and all commits in PR against Conventional Commits.                                          | Substitute for commit-level enforcement—overlaps with `commitlint`-based actions.                                                                                                                            |
| `googleapis/release-please-action`           | On `main` pushes, generates a release PR with SemVer bump and CHANGELOG updates.                            | Overlaps with `semantic-release` but offers a reviewable PR flow.                                                                                                                                            |
| `commitlint` (via various GitHub Actions)    | Validates commit messages meet Conventional Commit spec at commit-level.                                    | Overlaps with commit-level enforcement actions; complements PR title linting.                                                                                                                                |
| `actions/checkout`                           | Default action to checkout code for subsequent steps.                                                       | Required dependency.                                                                                                                                                                                         |


###### Issues are for Claude, not releases
* Issues are prompts for Claude to understand what to build
* Claude reads the issue content and generates appropriate commits
* Claude will write conventional commits in the PR it creates
* Release Please reads PR titles and commits, not issue titles

###### Issue Writing Strategy:
* Focus on clarity for Claude: Describe what you want built, not how
* Don't stress about conventional commit format in issues
* Use natural language: "Add dark mode toggle" not "feat: add dark mode toggle"
* Be specific about requirements: Claude works better with detailed specs

##### Set up considerations:
to set up the claude code action in all repos: this involves writing the `.github/workflows/*.yml` file each time and adding the claude api key to each repo individually; unless it's in a gh organizatin in which case we only need to add it once
for relase-please we also need a PAT or github code

with the claude ai assistant in github: we consider the atomic development approach: one issue -> one PR approach
context window limitations create natural boundaries so large codebases quickly exceed context limits

## ai-optimized codebase organization:
```
project/
├── .ai-context/          # AI-specific context files
│   ├── project-summary.md
│   ├── architecture.md
│   └── conventions.md
├── docs/                 # Human and AI documentation
├── src/
│   ├── core/            # Essential functionality
│   ├── features/        # Feature-specific modules
│   └── utils/           # Shared utilities
```
the above structure has been recommended by many agentic developers
another advanced vibe coder recommended:
```
1) ai_docs/   #persistent memory, knowledge repo for ai tools
contains best practices for coding, api docs and integrations
architecture docs and design
hidden non-code business logic
project-specific patterns

2) specs/   # contains the plan, PRD > units of work
plan is the prompt
detailing all the work that needs to be done before handing off to ai tools
things like db structure, implementation notes, api, project structure, validation

3) .claude # contains different comands as raw prompts
example: <context_prime.md> "read README.md and run `git ls-files` for context"
used to set up new instances of agentic tooling over time

recipe for external planning: first, prime the LLM with specific context on codebase
then draft the plan for specific features w/requirements which are placed in /specs
of the sort 1 feature > 1 markdown file (engineer becomes curator)
high quality plans include: high-level objectives, type changes, method changes, self-validation and a clean readme
```
for the claude gh action we use CLAUDE.md directly

however we take this paradigm further by leveraging the built-in github wiki. 
there is a key distinction to be explained here and that is: who is the audience of the documentation


## token optimization strategy

using deepwiki or equivalents to analyze the codebase periodically and track decision drift. this allows us to remain documentation-first. "measure twice, cut once" now becomes measure once, cut, measure again, and cut again.
the motions are repo to wiki <-> docs to code

### patterns from major projects as inspiration:
- hashicorp has a "docs impact assessment" for each feature PR
- stripe's system uses commit parsing to detect apu changes and creates issues with oneapi spec diffs attached - this logic can be replicated but for automatically askign for additional documentation to be updated in the docs repo associated to the work in progress repo (in tthe context of cross-repo linking). bidirectional references is the preferred mechanism so that release notes can pull from both repos 

#### Core Philosophy
the leger project embodies two key principles:
1) Deterministic Form Generation: Complex UI forms can be mechanically generated from well-structured schemas without AI intervention at runtime
2) Redundant Activity Minimization: Every component built for this tool will be reused in the full Leger platform

frequently prune and maintain documentation drift: documentation as single source of truth

mechanical vs creative: try to keep as many things mechanical as possible


some references to reach through. this is other people's experience with agentic coding:
- https://crawshaw.io/blog/programming-with-agents
- https://crawshaw.io/blog/programming-with-llms
- https://simonwillison.net/2025/Mar/11/using-llms-for-code/
- https://nicholas.carlini.com/writing/2024/how-i-use-ai.html
- https://blog.nilenso.com/blog/2025/05/29/ai-assisted-coding/
- https://ai.intellectronica.net/ai-assisted-software-engineering-in-the-large?trk=comments_comments-list_comment-text
- https://ai.intellectronica.net/ruler

first post should be about the specifics of claude code github action. some resources to look through specifically here:
https://www.kdnuggets.com/automate-github-workflows-with-claude-4?utm_source=perplexity
- https://dev.to/depot/faster-claude-code-agents-in-github-actions-1p2h?utm_source=perplexity

author i follow:
https://foo.zone/gemfeed/2025-06-22-task-samurai.html
