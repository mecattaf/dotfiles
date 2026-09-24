> Ported from tally-ts-sdk 897f9015 `docs/policy-sheet.md` on 2026-09-24 (parity gap PT-02). The data is `policy-sheet.json` beside this file; the reader is `tools/policy-sheet-diff.mjs`; the tests are `packages/planning/test-policy/`. Paths below that name `docs/policy-sheet.*` mean this folder. Card paths under /home/tom/research-methods are unchanged.

# The policy sheet — RUL-01's B-Q3, B-Q4 and B-Q5, bound

**Unit** `U-A9 · LAKE-POLICY`, branch `lake/policy-defaults`, off `main`.
**Sheet** `docs/policy-sheet.json`. **Tool** `tools/policy-sheet-diff.mjs`.
**Finding** `docs/findings/proposed-B-line-dropMeteredWhenFreePreferred.md`.
**Tests** `packages/planning/test-policy/policySheet.test.ts` (21), beside the 86 ported.

---

## 1. What this is for

`ReleasePolicy` (`packages/planning/src/release/evaluator.ts:130-167`) carries
four fields that exist, in the sketch's own words, because *"a rule in the
evaluator had no source in the canon and was therefore a preference someone had
encoded as code"*. Three of them are questions on RUL-01's Section B:

| RUL-01 line | question | field | value |
|---|---|---|---|
| **B-Q3** | routing preference order | `routingPreference` | `"routerOrder"` |
| **B-Q4** | congestion policy | `congestion` + the closed list `EscalationReason` | `{ _tag: "Wait" }` + three triggers |
| **B-Q5** | the length exponent | `lengthExponent` (through `DEFAULT_LENGTH_EXPONENT`) | `1` |

TL-2 (`/home/tom/research-methods/DECISIONS.md` **D-B2**) accepted all three at
the sheet's defaults, on Tom's sentence of 2026-09-05T23:23: *"Q3–Q5, Q12 and
Q13 are accepted at the sheet's defaults"*.

Before this unit those three values were true of the code and unfalsifiable
against the sheet: nothing on disk said which field answered which line, and a
value could have drifted with no check noticing. The sheet is that statement,
as data, and the tool is the check.

**The status stays `default, unruled`.** Tom's acceptance is a transcript
sentence and `RULINGS.md` is the durable store; transcribing it is his act, not
an operator's (`DEFERRED.md`, the U-A1 `[OPERATOR]` row, carried forward). So
every line in the sheet reads `status: "default, unruled"`, `ruled_by: "none"`,
and check **C1** goes RED if one of them is ever written otherwise without the
ruling that licenses it. *A later ruling changes data, not code.*

## 2. The mechanism, in three lines

1. `docs/policy-sheet.json` transcribes each RUL-01 line — its question, its
   `Default (PROPOSED).` sentence verbatim, its status — and *binds* it to the
   exact source lines that answer it.
2. `tools/policy-sheet-diff.mjs` imports the built `defaultReleasePolicy`, reads
   the bound sources, and prints one diff line per disagreement. **Empty diff,
   rc 0** means the built policy is RUL-01's defaults.
3. The fourth field, `dropMeteredWhenFreePreferred`, has **no sheet line at
   all**. It is in `findings[]`, not `lines[]`, it rides unchanged at `true`, and
   check **C6** goes RED the moment it is moved into `lines[]` as if it were a
   fourth accepted default.

## 3. Why the mark is an anchor and not a comment in `evaluator.ts`

The issue asks for each default *"marked `default, unruled` in place"*. In place
here is **by anchor**, not by comment, and the reason is measured:

U-A7 landed the sketch's 46 `src` modules **byte-identical**, and
`tools/port-copy.sh --check` enforces it — G1–G4 compare every manifest row's
byte length, sha256 and `cmp` against the sketch, and G6 refuses any file under
`packages/planning/{src,test}` the manifest does not name. A `// default,
unruled (RUL-01 B-Q3)` comment written into `evaluator.ts` would put that check
permanently RED and break the port's own contract, which is the one thing U-A9's
non-goal — *no change to the ported sketch's behaviour* — is protecting.

So each binding names the source line it marks:

```json
{ "kind": "policyField", "field": "routingPreference", "value": "routerOrder",
  "file": "packages/planning/src/release/evaluator.ts",
  "declaration_anchor": "  readonly routingPreference: RoutingPreference;",
  "value_anchor": "  routingPreference: \"routerOrder\"," }
```

and check **C3** requires each anchor to appear in that file **exactly once**.
The mark is therefore falsifiable in both directions: it points at a real line,
and if the line moves or is rewritten the diff is non-empty and names it. Eight
anchors are checked (MEASURED: `C3 8 anchor(s), each marked in place exactly
once`).

`DEFERRED.md`'s U-A9 boundary carries this as an `[OTHER-REPO]`/`[SCOPE]` pair.

## 4. The three binding kinds

| kind | what it compares | used by |
|---|---|---|
| `policyField` | the sheet's value against the built `defaultReleasePolicy[field]`, deep | B-Q3, B-Q4, B-Q5 |
| `closedList` | the sheet's members against the `export type NAME = \| "a" \| "b";` union in the named file, in source order | B-Q4 |
| `constant` | the sheet's value against the `export const NAME = <number>;` literal | B-Q5 |

`closedList` exists because B-Q4 is two sentences, not one. *"Wait when the
preferred member is congested"* is the `congestion` field; *"with escalation on
capability floor, deadline, or a failed verdict only — a closed list of three
triggers"* is the closure of `EscalationReason`
(`packages/planning/src/heuristics/localFirst.ts:33-39`). A fourth member added
to that union widens the sheet's answer without a ruling, and the diff catches
it (negative control `dropped-trigger`).

`constant` exists because `defaultReleasePolicy.lengthExponent` is not a
literal: it is `DEFAULT_LENGTH_EXPONENT`
(`packages/planning/src/heuristics/lengthTermFlip.ts:50`). B-Q5's answer lives
in two places and both are checked.

## 5. Running it

```sh
# the DOMINANT oracle, both halves
sh scripts/test.sh                                          # 107 = 86 ported + 21 policy
sh scripts/test.sh --exec node tools/policy-sheet-diff.mjs  # empty diff, rc 0
```

`sh scripts/test.sh --exec` is what `PFX_NODE;` stands for in this repository
(`docs/toolchain.md` §3): `node` is ABSENT from the login PATH on this box, so a
bare `node tools/policy-sheet-diff.mjs` exits **127** before it opens a file.
`npm run check:policy` is the same argv.

The diff goes to **stdout** and the check log to **stderr**, so "empty diff" is
literal:

```sh
sh scripts/test.sh --exec node tools/policy-sheet-diff.mjs > diff.txt   # 0 bytes
```

**The card cross-check.** `--against-card [PATH]` re-reads
`/home/tom/research-methods/cards/RUL-01.md` and compares each transcribed
question and `Default (PROPOSED).` sentence to the card's own text. It is off by
default so the oracle is hermetic to this repository. MEASURED 2026-09-06 in
this unit's worktree:

```
$ sh scripts/test.sh --exec node tools/policy-sheet-diff.mjs --against-card
ok    C8 the transcription against /home/tom/research-methods/cards/RUL-01.md
ok    the diff is empty: the built policy is RUL-01's B-Q3/B-Q4/B-Q5 defaults
rc=0
```

The suite runs the same comparison hermetically against
`packages/planning/test-policy/fixtures/rul-01-section-b-excerpt.md`, a verbatim
`sed -n '444,481p'` of the card at sha256 `bb812861…`.

**The card is read-only.** Nothing in this unit writes to
`/home/tom/research-methods`, and no `>` line is written on anywhere
(R-2026-09-05-03).

## 6. The negative controls

The house idiom (`tools/check-skeleton.sh`, `tools/baseline-86.sh`): rc 1 means
the control went RED as it must; rc 0 with an `UNEXPECTED` line means the green
above it is vacuous. MEASURED 2026-09-06, each rc 1:

| control | what it mutates | the diff line it produces |
|---|---|---|
| `mutated-value` | B-Q5's sheet value → 2 | `- B-Q5 lengthExponent sheet=2` / `+ … built=1` |
| `dropped-trigger` | one of B-Q4's three triggers | `- B-Q4 EscalationReason sheet=["capabilityFloor","deadline"]` |
| `fourth-rule-adopted` | the finding becomes a B-Q3 binding | `- F-A9-01 dropMeteredWhenFreePreferred is filed as a finding but adopted as a default by B-Q3` |
| `moved-anchor` | an anchor that is not in the file | `- B-Q3 … value_anchor appears 0 time(s), the sheet marks 1` |

The unit's own `mutation_hint` — *mutate one policy value → sheet diff
non-empty* — is the first row applied to the **code** rather than the sheet;
`§8` records the run.

## 7. Where the policy tests live, and why not in `test/`

`packages/planning/test/` is U-A7's port: 9 files, byte-identical to the
sketch, named one by one in `docs/port-manifest.tsv`. `tools/port-copy.sh
--check` G6 fails on any file under `packages/planning/{src,test}` the manifest
does not name, so U-A9's tests would break the port's contract if they landed
there. They live in `packages/planning/test-policy/` instead, which vitest picks
up by its default include and `port-copy.sh` does not walk. MEASURED after this
unit: `86 ported + 21 policy = 107 passed`, and `bash tools/port-copy.sh
--check` still green at 55 of 55 rows.

`packages/planning/tsconfig.json` includes `src/**` and `test/**` only, so
`test-policy/` is not under `tsc -p packages/planning`. That is deliberate and
recorded in `DEFERRED.md`: the suite reads files with `node:fs` and the package
declares `"types": []` with no `@types/node` in the tree U-A3 copied; adding one
is a new dependency, which is barred (`CONTRIBUTING.md` §2 rule 2). The ported
tsconfig is not edited by this unit.

## 8. What was MEASURED here

| | |
|---|---|
| `sh scripts/test.sh` | 9 files, **107 passed**, rc 0 (86 ported + 21 policy) |
| `sh scripts/test.sh --exec node tools/policy-sheet-diff.mjs` | empty stdout, rc 0, C1–C7 all `ok` |
| the same with `--against-card` | C8 `ok` against the live card, rc 0 |
| four negative controls | rc 1 each, each naming what moved |
| `mutation_hint`: `lengthExponent: DEFAULT_LENGTH_EXPONENT` → `2` in `evaluator.ts` | diff **non-empty**, rc **1**, and the suite RED; reverted |
| `bash tools/port-copy.sh --check` | 55 of 55 rows byte-identical, G6 green |
| `git diff --stat main -- packages/planning/src packages/planning/test` | empty |
| `git diff --stat main -- package-lock.json` | empty |
