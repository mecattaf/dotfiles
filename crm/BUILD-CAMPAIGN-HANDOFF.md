# CRM build campaign — supervisor handoff (2026-07-31)

You are a fresh session supervising the first tally-driven codegen campaign:
building Tom's personal CRM CLI (`crm`, Go + SQLite) by at-mentioning GitHub
issues that tally turns into codex flow runs. Everything is minted and
verified; your job is to DRIVE and JUDGE, never to write the product code
yourself. Tom is the escalation point for anything the spec corpus does not
answer.

## System map (all verified live)

- **Repo**: `github.com/mecattaf/crm` (private; local clone
  `~/mecattaf/crm`). Contains the complete spec corpus:
  `AGENTS.md` (agent orientation, four gates), `.specify/memory/constitution.md`
  (engineering non-negotiables), `specs/001-crm/{spec.md, data-model.sql,
  plan.md, tasks.md, style-transfer-map.md}`. The corpus is FROZEN for this
  campaign — any change to it requires Tom.
- **Issues**: #1–#19, label `build`, one per task, dependency-ordered;
  `specs/001-crm/tasks.md` holds the task↔issue map and the four
  cross-cutting conventions. Issue bodies are self-contained: goal, delivered
  behaviors, read-first list with style-transfer reference paths, runnable
  acceptance criteria, the four gates.
- **Producer** `crm-build` (gh kind) on coordinator: polls every 60s; an
  explicit comment containing exactly `@tally build`, posted by `mecattaf`,
  on an OPEN issue labeled `build` in mecattaf/crm, enqueues one job:
  `crm-issue-dispatch <issue-number>` on the capacity-1 `crm-campaign` lane
  (so runs serialize even if two mentions land). It posts an acknowledgement
  receipt comment on intake and an evidence comment on a passing run. It
  never closes issues.
- **Flow** `crm-issue` (registered; dotfiles `flows/crm-issue.js`), per run:
  1. prep: worktree `~/.local/state/tally-worktrees/crm-issue-<N>`, branch
     `issue-<N>` reset onto `origin/main` (`--force -B` — a re-run DISCARDS
     the previous failed attempt by design);
  2. codex node (codex-window lease): reads AGENTS.md + the issue via
     `gh issue view <N> --comments`, implements, runs gates itself, commits;
     does not push;
  3. four witnessed gate nodes, exactly AGENTS.md's invocations:
     `go build`, `go vet`, race-enabled `go test` (gcc for cgo),
     `golangci-lint run`;
  4. push + `gh pr create` with body `Closes #<N>...` — only reached when
     every gate passed.
- **Verified before handoff**: `nix flake check` green; flow passes
  `tally flow check`; producer unit live and polling; deployed store-path
  flow confirmed to carry the four gates; dry run
  `tally producer test crm-build --item .../issues/1 --event mention --actor
  mecattaf --no-enqueue` returned `would-enqueue` with the correct dispatch
  argv. No mention has been posted; no run has fired.

## The drive loop (one issue at a time, numeric order)

For each issue N = 1..19:

1. Confirm the previous issue's PR is merged and the issue closed.
2. Skim the issue once more; if a previous run taught you something codex
   must know, add it as an ordinary comment BEFORE triggering (codex reads
   `--comments`).
3. Trigger: `gh issue comment N --repo mecattaf/crm --body "@tally build"`
4. Within ~60s the producer's receipt comment appears on the issue. Then
   follow the run:
   - `tally query jobs` / `tally query watch` — the dispatch job and the
     flow's child nodes;
   - `journalctl --user -u tally-producer-crm-build.service -f` for intake;
   - the flow's node labels: worktree-prep → implement → gate-build →
     gate-vet → gate-test → gate-lint → push-pr.
5. On success: evidence comment on the issue + a PR titled with codex's
   commit subject. REVIEW THE PR DIFF yourself before merging — gates prove
   build/test/lint, you judge spec conformance (right verbs, right output
   contract, no scope creep beyond the issue, no db/sidecar files, no doc
   drift). Then:
   `gh pr merge <pr#> --repo mecattaf/crm --merge --delete-branch`
   (the `Closes #N` body closes the issue). Verify with
   `gh issue view N --repo mecattaf/crm --json state`.
6. Move to N+1.

Codex working style: expect roughly cobra/modernc idioms transferred from
`/home/tom/Downloads/crm-cli` and product/test genre from
`/home/tom/Downloads/crm.cli` — the issue's "Style-transfer references" name
the exact files; a diff that ignores its cited precedents deserves scrutiny.

## Failure protocol (fail-fast, ruled)

A failed gate (or failed codex node) rejects the flow run; no push, no PR.
Do not merge anything red; do not patch the worktree yourself.

1. Diagnose: `tally query job <uuid>` / `tally query log --task <uuid>` for
   the failing node; the worktree at
   `~/.local/state/tally-worktrees/crm-issue-<N>` is inspectable evidence.
2. Steer: write what went wrong and what to do differently as a comment on
   the issue (this is the sanctioned steering channel — it becomes part of
   codex's next read).
3. Replay: post a fresh `@tally build` comment. A new comment is a new event
   id, so intake accepts it; prep resets the branch and codex starts clean.
4. Two consecutive failures on the same issue with good steering → stop and
   escalate to Tom with the diagnosis. Never widen scope to route around a
   failure.

If a merged PR later proves defective, prefer a follow-up comment on the
NEXT relevant issue over reopening; if it blocks the sequence, escalate.

## If the flow or producer itself must change

Config lives in dotfiles (`flows/crm-issue.js`, `flows/tally-flows.nix`,
`home/tally.nix`). Procedure: edit → `tally flow check flows/crm-issue.js
--args '{"issue":1}'` → `nix flake check --no-build` → commit + push to
main → redeploy through tally (fleet-deploy resolves GitHub main, NOT the
local checkout):

    tally --socket "/run/user/$(id -u)/tally/tally.sock" enqueue \
      --source calendar --pool build --pool flow-build --pool coordinator-gpu \
      --priority medium --dedup-key "crm-campaign-redeploy-<date>-<n>" \
      --no-enqueue --evidence exit:0 \
      -- /run/wrappers/bin/sudo -n /run/current-system/sw/bin/systemctl --wait start fleet-deploy.service

Then re-verify the deployed flow store path carries your change (trace:
`/home/tom/.config/tally/config.json` → producer enqueue argv → dispatch
script → flow store path).

## Standing constraints

- Sequential, one issue in flight, numeric order (#1 → #19). The mutex
  enforces serialization; you enforce order — never stack mentions.
- #18 (import of the investor CSVs) stays LAST before #19; the tool must be
  fully proven first. #19 prepares `buildGoModule` + install docs only — the
  actual graduation into dotfiles is Tom-supervised, not yours.
- The spec corpus and AGENTS.md are read-only for you and for codex;
  ambiguity or contradiction discovered mid-build → escalate to Tom, do not
  interpret creatively on anything that changes the surface.
- No codegen outside tally (no local editing of the crm repo), no merging
  red, no closing issues by hand, no editing tally config beyond the
  procedure above.
- The db never exists in any repo; if a run leaves a `.db`/`-wal`/`-shm`
  file in the worktree or a PR, that PR is wrong regardless of gates.

## End state

All 19 issues closed, all PRs merged, gates green throughout. Then report to
Tom: campaign summary, anything learned about the at-mention pattern worth
folding into a reusable `mkIssueCampaign` helper (explicitly deferred until
this campaign proves the shape), and readiness for the dotfiles graduation.

## Issue sequence

 #1 T01 scaffold, db funnel, migration, init, exit codes, harness
 #2 T02a normalization tiers + output formatter (org add|ls)
 #3 T02b resolver ladder + org show|edit PATCH
 #4 T03 contact CRUD, polymorphic show, messy-refs persona pt1
 #5 T04 log, interaction read/repair, enum spine, concurrent-writer test
 #6 T05a find: cross-entity FTS, normalized rank merge
 #7 T05b context briefing, first-lead + agent-session personas
 #8 T06 pipelines + stages management
 #9 T07 deals, stage moves, win/lose/reopen, rot, deal-loop persona
#10 T08 contact links: relate/unrelate, both-ends rendering
#11 T09 status dashboard + stale report
#12 T10a archive/unarchive everywhere, honest ls --all
#13 T10b hard delete: confirm machinery, blocking matrix
#14 T10c doctor + --rebuild-fts
#15 T11 post-write hook, /crm skill, agent docs, recipe tests
#16 T12 export: flat JSON/CSV + markdown tree
#17 T13 dupes scoring + transactional merge, merge persona
#18 T14 import (idempotent, roundtrip, investor CSVs) — LAST implementation
#19 T15 graduation prep: buildGoModule + install docs (no dotfiles move)
