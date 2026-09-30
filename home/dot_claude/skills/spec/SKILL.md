---
name: spec
description: Author, lint, ratify, and dispatch a light-format chapter spec (SPEC.md + PROVE.md) against the house claim grammar, then derive and run substrate tasks from it. Use when the user says "write the spec", "spec for <chapter>", "ratify [the spec]", "spec-check", "derive tasks", or asks about a PROVE row or PROVE.md.
---

# Author, check, ratify, derive, dispatch

One chapter gets one `SPEC.md` at the root of its primary repo, plus one
`PROVE.md` beside it holding the proof receipts. This skill is the
procedure that turns Tom's rulings and a repo read into that file, keeps it
honest with a shell lint, and — once ratified — turns it into substrate
runs that come back as branches and PRs, never pushes to `main`.

Templates: `TEMPLATE.md` (the exact SPEC.md skeleton) and
`PROVE.template.md` (the receipt table + legend), both beside this file.
Lint: `scripts/spec-check.sh`.

## Author

Read the tree before writing a line — a claim about code you did not read
this session is fiction. Copy `TEMPLATE.md` to `SPEC.md` at the chapter
repo's root and fill it from Tom's rulings (verbatim, dated, one per line
under `## Rulings`) and what the repo actually does:

- **Outcome** first, 3–8 sentences, observable before/after, no hedges.
- **Claims**, one `C<n>.<n> <condition> → <observable>. [prove: P<id>]` (or
  `[human: H<id>]`) per line, grouped into `### Stage A/B: <name>` blocks.
  Mark a claim `(tree)` when the tree is authoritative and the spec is
  wrong if they disagree. Give every numeral `(given)` or `(GUESS)` unless
  it is an id, a pinned version, or a path. Never name a model in a claim —
  runtimes belong only in the `## Tasks` table, added later.
- **Open questions**: `Q<n> [BLOCKING] <question>? default: <answer>
  (GUESS)` for forks, `H<n> [HUMAN] <what only Tom can do>` for gates.
- **Out of scope** is always last, verb-first exclusions.
- Empty section → `Omitted: <reason>.`, never a blank heading.

Then run the **falsity pass**: hand only the numbered claim lines (nothing
else — not Outcome, not Rulings) to a fresh, read-only reader with no
loyalty to the prose (a separate factory node, or a sub-agent with no
write tools) and one question — "Which of these statements about this repo
are false?" Fix or demote a refuted `(tree)` line; a refuted non-tree line
stays and becomes an Open question instead. Record every correction as a
`## Rulings` row.

## Check

```
home/dot_claude/skills/spec/scripts/spec-check.sh SPEC.md
```

(from an installed checkout: `~/.claude/skills/spec/scripts/spec-check.sh`).
Exit 0 is clean. Exit 1 prints one `SPEC.md:<line>: <rule>` per violation —
fix the bytes, never argue with the linter in prose. Run it again after
every edit, including after the falsity pass and after every Open-question
answer. `scripts/test.sh` runs the bundled fixtures if you doubt the
checker itself.

## Ratify

Ratification is Tom, at a keyboard, merging the spec PR and flipping
`Status: proposed` to `Status: ratified <YYYY-MM-DD>` in that same PR.
Refuse to flip it — say so and stop — while `spec-check.sh` would refuse:
any `(GUESS)` or `[BLOCKING]` line left anywhere in the file. After
ratification the file is frozen except for two kinds of append: Status
transitions, and a `## Tasks` table (next).

## Derive tasks

At ratification, group the claims of one stage that share a repo and a
gate into one task — **one task = one repo, one branch, one PR**. Order
tasks by dependency. Append the `## Tasks` table from `TEMPLATE.md`'s
shape (`task | claims | repo | branch | runtime plan | depends | run id |
PR | state`) — these rows are data, not code, and the table is an allowed
post-ratification append.

For each row, write `tasks/T<n>.json` beside `SPEC.md` in the §4.6 args
shape:

```json
{"chapter":"email","spec":"agency-agency/email@<sha>:SPEC.md","task":"T1",
 "claims":["C1.1","C1.2","C1.3"],"repo":"agency-agency/email","repoDir":"/home/tom/mecattaf/email-svc",
 "base":"main","branch":"t/email-t1-toolchain","worktree":"/home/tom/.wt/email-svc/t1",
 "routes":{"impl":"codex-rw","review":"opus","mech":"halogen"},
 "prove":[{"id":"P1.1","cmd":"pnpm -r typecheck"}],"maxFixRounds":2}
```

## Dispatch

One task, one submit, using the shared program
`agency-agency/substrate` `programs/spec-task.workflow.js` (never a
bespoke per-chapter script):

```
substrate submit programs/spec-task.workflow.js \
  --id <chapter><task>r<n> --name <chapter>-<task> --args @tasks/T<n>.json
```

`<chapter><task>r<n>` is 6–40 lowercase letters/digits (e.g. `emailt1r1`)
and makes the submit idempotent — bump `r<n>` for a resubmit of the same
task. The program itself preflights the worktree, implements on
`routes.impl`, runs every `prove[].cmd` and appends PROVE rows on the
branch, runs the falsity pass again as read-only review, fixes up to
`maxFixRounds`, then `git push -u origin <branch>` and `gh pr create`. It
never pushes `<base>` and never merges.

## Verify

Read the returned PR's PROVE rows yourself; re-run one gate command from
them to confirm rc and evidence still hold; report to Tom only what
actually needs him (a `fail`/`blocked` row, an Open question, or the merge
itself — ruling: every merge stays with Tom unless he says otherwise).
Do not merge.

## Close

Once every task's PR is merged and every `[prove: Px]` row in `PROVE.md`
reads `pass`, flip `Status: ratified <date>` to `Status: closed <date>` in
one more PR. A chapter with `[human: Hx]` claims still `blocked` stays
`ratified`, not `closed`, until Tom clears the gate and a rerun PROVE row
lands `pass`.
