---
name: backlog-discipline
description: Conventions and CLI workflow for the Leger backlog at ~/leger/backlog (Sodimo pilot project tracking). Use when creating, editing, archiving, or querying tasks/decisions/docs/drafts under ~/leger/backlog; when processing daily logs under ~/leger/sodimo/ that feed the backlog; or when the user mentions the backlog board, IDs like TASK-NN / decision-NN / DRAFT-NN / m-N, or actions like "add a task", "log this", "archive that", "check the board". Prime directive — CLI only, never hand-write .md files.
when_to_use: cd into ~/leger or any subtree; user references TASK-N / decision-N / DRAFT-N / m-N; new artifact creation; status flips; AC checks; archive/cleanup; weekly retrospective writeups.
---

# Leger backlog discipline

The Leger backlog at `~/leger/backlog/` tracks the Sodimo pilot. It is managed by the [`backlog`](https://github.com/MrLesk/Backlog.md) CLI (v1.45.1+, already installed). **The single most important rule: every artifact MUST be created via the CLI. Never hand-write `.md` files** — past hand-writing produced 34 invalid files that bypassed validation and had to be rebuilt.

## Live project facts (verify before acting)

| Field | Value |
|---|---|
| Root | `~/leger/backlog/` |
| Web UI | `cd ~/leger && backlog browser --port 6421` |
| Board | `cd ~/leger && backlog board` |
| Statuses (4) | `To Do`, `In Progress`, `Blocked`, `Done` |
| `task_prefix` | `task` → IDs are `TASK-1`, `TASK-2`, ... |
| `date_format` | `yyyy-mm-dd` (no time on this project) |
| Default editor | `nvim` |
| DoD defaults (3) | AC all checked · Refs cite path/url or N/A · Deps resolved or waived |

Always verify the live config before structural ops:

```bash
cd ~/leger && backlog config list
```

Tasks are read in agent-friendly form with `--plain`. Without it the CLI opens a TUI that will hang an agent session.

## Artifact-type decision tree

```
Did the project commit to a date?
  YES → milestone (m-N; thin; no AC; e.g. DR-sim 2026-05-16, email cutover 2026-05-14→17)
  NO ↓
Is it "we chose X over Y because Z" that other tasks reference?
  YES → decision (decision-N)
  NO ↓
Is it "we do this every time / for every employee / for every service"?
  YES → doc (doc-N) — never "Done"; updated in place
  NO ↓
Is it a one-time action with verifiable AC?
  YES → task (task-N)
  NO ↓
Is it an idea not yet committed to / not scheduled?
  YES → draft (draft-N)
```

In doubt: if it has verifiable AC and a clear done state, it is a task.

`completed/` is for genuinely shipped work (Done + `backlog cleanup`). `archive/` is for superseded, abandoned, or killed work. **Do not put killed work in `completed/`.**

## Field discipline (frontmatter)

**ID casing**: filename `task-NNN.md` (lower), YAML `id: TASK-NNN` (upper). Subtasks: filename `task-NNN.NN.md`, YAML `parent_task_id: TASK-NNN`.

**Status values**: exactly the four above. `Blocked` is a *pause* state, not terminal — used only for hard external dependencies (Florian's dump, Starlink ISP, hardware arrival, vendor confirmation, Paul's TARIF/DEPOT labels). When the blocker clears, return to `In Progress`.

**Assignee**: YAML array. `assignee: ['@thomas']` for Tom's work. Retro-rebuild agents used `@sonnet-day-pass` and `@opus-retrospective`; do not invent new handles without reason.

**Labels** — apply 1–4 per task across three axes; don't label everything:

- **Layer** (what part of the stack): `infra`, `data`, `ai`, `crm`, `mail`, `web`, `secrets`, `dr`, `docs`
- **Type** (what kind of work): `setup`, `bug`, `refactor`, `decision-followup`, `migration`, `playbook`
- **Scope** (who it applies to): `sodimo`, `leger-personal`, `pre-pivot`

If a needed label isn't in the taxonomy, **ask Tom before inventing one** — drift is real and previously bit the rebuild.

**Priority**: use on fewer than 30% of tasks.
- `high` = hard blocker with a dated commitment (DR-sim 2026-05-16; email cutover window)
- `medium` = important to the pilot but not calendar-gated
- `low` = nice-to-have / docs / edge-case
- Otherwise omit.

**Dependencies**: always explicit. Empty = `dependencies: []`. Populated = `dependencies: [task-7, task-8]` (lower-case, no prefix). Wire `--dep` at creation time. **Never leave `dependencies: []` on a task that has a real upstream** — the graph is the structural record.

**created_date**: for retrospective tasks, use the date of the daily log being processed, not today.

## Body discipline

- **Description**: always present. 1–2 sentences for small tasks. Sub-headed `### Why / What / Context` only when motivation is non-obvious or multi-layer.
- **Acceptance Criteria**: inside `<!-- AC:BEGIN -->` / `<!-- AC:END -->` markers, numbered `#1`, `#2`. Min 1, typical 3–7. Each AC must be testable from outside. Retro-logged Done tasks have all ACs checked `[x]` at create time.
- **Implementation Plan**: only when path is non-obvious. Numbered, written before execution, not modified after. Deviations go in Notes.
- **Implementation Notes**: what actually happened. Short on simple tasks, timestamped paragraphs on complex ones. Absent on `To Do`. For archived items, write a supersession note here *before* archiving.
- **Final Summary**: only for deliverables that crossed a PR or external-review boundary. Sodimo solo work usually omits.
- **DoD**: inherited from `config.yml`. For non-code work, annotate inapplicable items ("not applicable — no TypeScript; verified by `just setup`") rather than silently checking them. Add Sodimo-relevant DoD with `--dod`.

Length scales with AC count: 1–3 AC = 1–2 sentence description, no plan; 3–6 AC = optional 4-step plan; 6+ AC = sub-headed description, phased plan, timestamped notes, optional Final Summary.

## CLI cheat-sheet

Run from `~/leger` (the CLI walks up from any subtree). **Always `--plain` for inspection** unless explicitly opening a TUI.

### Create

```bash
backlog task create "Harden Vaultwarden and wire R2 nightly backup" \
  --status "Done" \
  --assignee "@thomas" \
  -l secrets,setup,sodimo \
  --priority high \
  --ac "#1 Admin token rotated; signups disabled; fail2ban configured" \
  --ac "#2 data.sqlite3 → R2 nightly backup live; lifecycle 90d" \
  --ac "#3 Vaultwarden restore drill completed; timings captured" \
  --plan "1. Rotate token  2. Configure fail2ban  3. Wire R2 sync  4. Drill restore" \
  --notes "Initial pass completed 2026-04-14; drill timings captured in run-log" \
  --dod "All 6 Caddy routes return HTTP 200 through CF Access" \
  --ref ~/leger/sodimo-dev/runbooks/vaultwarden-hardening.md \
  --ref https://vaultwarden.dev/docs/install/admin \
  --doc doc-3 \
  --doc https://github.com/dani-garcia/vaultwarden/wiki \
  --dep task-19
```

Every create-time flag has an edit-time counterpart of the same name. Also accepted at create:
- `--final-summary "..."` — PR-style summary (rare on Sodimo; reserve for deliverables crossing an external review)
- `--no-dod-defaults` — opt the task out of the project DoD inheritance entirely (use with care; annotate-and-keep is preferred)
- `--draft` — alternative to `backlog draft create`; produces a draft instead of a task

Sub-task: `backlog task create -p 14 "Add Login with Google"` (sets `parent_task_id: TASK-14`).

### Citations: `--ref` and `--doc` (satisfies DoD #2)

DoD default #2 ("Refs cite a concrete file/path/url") is *only* satisfiable via these flags. Both accept file paths AND URLs, both can be repeated for multiple citations:

```bash
backlog task create "..." \
  --ref ~/leger/sodimo-dev/runbooks/foo.md \
  --ref https://developers.cloudflare.com/workers/observability/ \
  --doc doc-7 \
  --doc https://docs.example.com/spec
```

Convention: `--ref` for files/URLs that *informed* the work (specs, source material, prior art); `--doc` to link Sodimo backlog docs by ID (`doc-N`) or external design docs. When DoD #2 doesn't apply (e.g. pure ops task with no external source), check it off via `--check-dod 2` and note "no external refs needed."

### Multi-line description / plan / notes

The CLI takes input **literally** — `\n` is not converted. Two safe forms (both work in agent sandboxes):

1. **Repeat `--append-*` per line**:

   ```bash
   backlog task edit 7 --notes "First line"
   backlog task edit 7 --append-notes "Second line"
   backlog task edit 7 --append-notes "Third line"
   ```

2. **Real newlines inside double quotes** (single command):

   ```bash
   backlog task create "Feature" --desc "Line 1
   Line 2

   Final paragraph"
   ```

Avoid Bash/Zsh `$'...\n...'` and `printf`-substitution shortcuts — those work interactively but are rejected by tree-sitter agent sandboxes.

### Edit

```bash
backlog task edit 7 -s "In Progress"            # status flip
backlog task edit 7 --check-ac 1 --check-ac 3   # mark AC #1 and #3 done
backlog task edit 7 --uncheck-ac 2
backlog task edit 7 --check-dod 1
backlog task edit 7 --ac "New criterion"        # append AC
backlog task edit 7 --remove-ac 2               # remove AC #2 (shifts numbering)
backlog task edit 7 --dep task-12               # add dep
backlog task edit 7 -l web,migration,sodimo     # set labels (replaces)
backlog task edit 7 --append-notes "..."        # append (preserves history)
backlog task edit 7 --notes "..."               # REPLACE — destructive
backlog task edit 7 --final-summary "..."       # PR-style summary (replaces)
backlog task edit 7 --append-final-summary "..." # append to existing
backlog task edit 7 --clear-final-summary       # remove entirely
backlog task edit 7 --plan "..."                # replace Implementation Plan
```

Mixed AC ops in one call: `--check-ac 1 --uncheck-ac 2 --remove-ac 4`.

### Archive (superseded / killed)

Three steps, in order — never archive without a note:

```bash
backlog task edit 7 --append-notes "2026-05-11: Killed by May-11 pivot. <reason>. Archiving."
backlog task archive 7
```

### Move Done → completed/

```bash
backlog task edit 26 --check-ac 1 --check-ac 2 --check-ac 3
backlog task edit 26 -s Done
backlog cleanup       # interactive at v1.45.1 — moves all Done tasks to completed/
```

`cleanup` is interactive-only on the installed version; Done tasks stay in `tasks/` until you run it.

### Decisions

CLI stubs accept only title + status; the body needs a follow-up edit:

```bash
backlog decision create "Harness reads Sodiwin via CIFS direct mount (not NAS rsync)" -s accepted
# Then open the file in nvim to add Context / Decision / Rationale / Consequences.
```

Decision statuses: `proposed`, `accepted`, `rejected`, `superseded`. Most existing decision bodies are CLI stubs (86 of 143 at last count); a body-fill pass is a separate effort.

### Docs

```bash
backlog doc create "DR runbook — end-to-end rebuild" -t guide
backlog doc create "Retrospective — fourthweek" -t other
backlog doc create "Setup Guide" -p guides/setup    # nested path under backlog/docs/
backlog doc update doc-1 --content "Updated markdown"
backlog doc update doc-1 --title "..." --tags setup,runbook -p guides
backlog doc list
backlog doc view doc-1
```

Types: `guide`, `specification`, `other`. Docs are never "Done" — updated in place.

### Drafts

```bash
backlog draft create "WhatsApp order-acknowledgment bot" \
  --ac "#1 Meta Business Verification complete" \
  -l ai,sodimo
backlog draft promote 24      # convert draft → task
backlog task demote 24        # convert task → draft
```

### Read / inspect

```bash
backlog task 7 --plain                       # single task, AI-friendly
backlog task list --plain                    # all
backlog task list -s "Blocked" --plain
backlog task list -p task-9 --plain          # subtasks of 9
backlog search "auth" --plain                # fuzzy across tasks/docs/decisions
backlog search "bug" --priority high --plain
backlog sequence list                        # dependency-ordered execution sequence
backlog overview                             # project stats (TUI)
backlog board                                # kanban TUI
```

### Export & sharing

```bash
backlog board export                          # default file (Backlog.md)
backlog board export status.md                # named file
backlog board export --force                  # overwrite existing
backlog board export --readme                 # write into README between markers
backlog board export --export-version "v1.0"  # include version string in header
backlog board export --readme --export-version "Release 2026-05-16"
```

### Config

```bash
backlog config list                           # show all
backlog config get defaultEditor              # one key
backlog config set autoCommit true            # set
backlog config                                # full interactive wizard (DoD editor, etc.)
```

Current Leger backlog config keys and values:

| Key | Current | Purpose |
|---|---|---|
| `default_status` | `To Do` | first column |
| `statuses` | `[To Do, In Progress, Blocked, Done]` | 4-value Leger set (note `Blocked` is Leger-specific) |
| `task_prefix` | `task` | ID prefix |
| `date_format` | `yyyy-mm-dd` | dates without time |
| `default_port` | `6421` | web UI |
| `default_editor` | `nvim` | E-key editor |
| `auto_commit` | `false` | full git control retained — manual commits |
| `bypass_git_hooks` | `false` | hooks run normally |
| `remote_operations` | `false` | offline-safe (no git fetch) |
| `check_active_branches` | `true` | cross-branch state check |
| `active_branch_days` | `30` | branch-activity window |
| `auto_open_browser` | `true` | `backlog browser` opens automatically |
| `definition_of_done` | 3 defaults | inherited by every new task |
| `onStatusChange` | (unset) | shell hook on status flip — see below |
| `zeroPaddedIds` | (unset) | leading-zero padding on IDs |

**`onStatusChange` hook**: shell command that runs on every status flip with `$TASK_ID`, `$OLD_STATUS`, `$NEW_STATUS`, `$TASK_TITLE` available. Per-task override via `onStatusChange` in task frontmatter. Don't enable casually — it fires on every flip and can rack up tokens fast. Example pattern (do NOT enable without discussing):

```bash
backlog config set onStatusChange \
  'if [ "$NEW_STATUS" = "In Progress" ]; then claude "Task $TASK_ID ($TASK_TITLE) just entered In Progress — review and propose next step" & fi'
```

### Setup & rare ops (backlog is already initialized)

```bash
backlog init                                  # re-init; preserves existing config
backlog agents --update-instructions          # refresh CLAUDE.md / AGENTS.md / .github/copilot-instructions.md
backlog completion install --shell bash       # install tab-completion (per-shell)
```

## Hard rules

1. **CLI only.** If a field can't be set via flag, create via CLI first, then surgically edit one line. Never `cat > task-N.md`.
2. **`--append-notes`, not `--notes`** when adding to existing notes — the bare form overwrites.
3. **`--ac` repeats**, not `\n` separators.
4. **`--plain` for inspection** — without it the CLI opens a TUI that hangs an agent.
5. **Status reflects state at the time of the log** for retrospective work. The weekly Opus retrospective corrects mid-week pivots, not in-line edits.
6. **No look-ahead** in retrospective passes — process days in chronological order; do not skim later days to "know how it ends."
7. **Dependencies are never silently empty** — wire `--dep` at create or via edit. The graph must reflect the real cascade.
8. **archive/ ≠ completed/** — archive is killed/superseded; completed/ is genuinely shipped (Done + cleanup).
9. **Write a supersession note in Implementation Notes before archiving.** No bare archives.
10. **Ask before inventing labels** outside the three-axis taxonomy.

## Retrospective conventions

When logging work that was completed during the 5-week Sodimo window (2026-04-14 → 2026-05-11):

- Create the task with all AC checked `[x]` and `--status "Done"`, using the daily log's date as `created_date`.
- Batch-run `backlog cleanup` at end of each day-pass (or week-pass) to move Done → `completed/`.
- For Blocked-at-log-time work that is still externally gated: create as `Blocked` with the named blocker in Notes.
- For tasks never started and now moot: create reflecting log-time state → add supersession note → `backlog task archive`.

The 5-week sequencing plan and per-day key events are documented in `~/Downloads/backlog/BACKLOG-METHODOLOGY.md` §11. Do not read ahead while processing.

## Pre-pivot pattern (May-11 2026 reset → decision-138)

The May-11 pivot killed: Leger-as-product, OpenTofu / `leger-labs/recipes` / `leger CLI` / `app.leger.run`, custom monitoring dashboards (60-part-dashboard, launchpad), multi-tenant abstractions, AIcademy / exec-seeding framing for Leger.

Any pre-pivot work captured retrospectively gets label `pre-pivot` + a supersession note. Sequence:

```bash
backlog task create "Apply OpenTofu recipes for CF zone + GH org + R2" \
  --status "In Progress" \
  --assignee "@thomas" \
  -l infra,setup,pre-pivot \
  --ac "#1 tofu init passes for all 4 recipes" \
  --ac "#2 cf-r2-bootstrap applied; 4 R2 buckets created" \
  --ac "#3 gh-org-baseline applied; sodimo GitHub org configured"

backlog task edit <id> --append-notes "2026-05-11: Killed by May-11 pivot. OpenTofu + leger CLI dropped; CF/GH/R2 bootstrapped manually before pivot. Archiving as pre-pivot artifact."

backlog task archive <id>
```

**Exception**: if the work itself was delivered and is still live (e.g., the Sodimo website rebuild on CF Pages), keep it in `completed/` with the `pre-pivot` label and a note clarifying that the framing is superseded but the artifact stands.

## When to ask Tom rather than guess

- Two tasks may overlap → ask whether to merge, sub-task, or keep separate. Don't dedup silently.
- A decision is partially alive / partially killed → flag for split or scope-clarification note rather than flipping a single status.
- Adding a label outside the established taxonomy.
- Bulk operations across >5 artifacts → confirm scope before executing.
- Body-fill of stub decisions → confirm whether the wave is wanted; 86 of 143 decisions have hollow bodies by design.
- DoD-check of retro-logged Done tasks where defaults were inherited post-fact → mechanical; usually skip.

## Reference paths

- Full methodology (12 sections, sequencing plan, depth calibration, length tiers): `~/Downloads/backlog/BACKLOG-METHODOLOGY.md`
- Full CLI reference (every flag): `~/Downloads/backlog/CLI-INSTRUCTIONS.md`
- Advanced config (`backlog config`, DoD wizard, on-status-change hook): `~/Downloads/backlog/ADVANCED-CONFIG.md`
- Source reference analyses (A discipline, B dryrun scope, C changelog inventory, D sodimo-dev map): `~/Downloads/backlog/_reference-analysis-{A,B,C,D}-*.md`
- Live config: `~/leger/backlog/config.yml`
- Daily working logs (retro source): `~/leger/sodimo/<week>/<day>/`
- Most recent state + open threads: `~/leger/sodimo/fifthweek/tuesday/morning-work-handoff.md`
- Unresolved judgment calls awaiting Tom: `~/leger/sodimo/fifthweek/tuesday/contradictions-to-resolve.md`
- Per-week Opus retrospectives: `~/leger/backlog/docs/retrospectives/doc-{7,15,18,22}-Retrospective-*.md`
