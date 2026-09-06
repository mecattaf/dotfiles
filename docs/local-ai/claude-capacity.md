# The claude-capacity oracle — and its case count

`home/dot_local/bin/claude-capacity` is the ONE thing on this fleet that can
answer "does the Claude subscription have headroom right now". It reads
`/api/oauth/usage` — the same endpoint Claude Code's own `/usage` reads — and
serves both a waybar module and the dispatch gate from the same cached reading,
so the bar and the dispatcher can never disagree about headroom
(`64879c9d`, DECISION-R2-1).

**Its hermetic suite has 23 cases. Not 21.** That is the whole reason this page
exists; everything else here is context for that number.

## The number

| | |
|---|---|
| Suite | [`tests/claude-capacity/test-claude-capacity.py`](../../tests/claude-capacity/test-claude-capacity.py) |
| Cases | **23**, all hermetic — seeded cache, temp `XDG_RUNTIME_DIR`, temp `HOME`, deliberately dead token |
| Last line it prints | `23/23 passed` |
| Measured out-of-nix 2026-09-06 | **23/23 passed, rc 0** (unit U-D8), reproducing the estate pass of the same day |
| Wired as | `nix flake check`'s `claude-capacity` ([`flake.nix`](../../flake.nix)) |

The cases are not decoration. What they pin is the three-value contract the
tally admission hook depends on: **exit 0 = headroom/admit, 1 = measured, no
headroom/defer, 2 = cannot determine.** A regression that turned "cannot
determine" into 0 would dispatch into a spent window; one that turned headroom
into nonzero would stall the queue in silence. Neither is visible by eye, which
is why they are asserted rather than assumed.

They fall in six blocks:

| block | cases | what it pins |
|---|---|---|
| fresh cache, the measured paths | 10 | per-window verdicts, `--threshold`, `--json`, the waybar text and percentage |
| a reading in hand needs no token | 2 | a `claude` token refresh must not turn a five-second-old measurement into "unknown" |
| stale cache | 2 | inside the grace window an old reading beats an error, and says it is stale |
| unknowns | 5 | every unmeasurable path is exit 2, never 0 |
| waybar's contract | 2 | waybar mode exits 0 even with nothing to report |
| no credentials at all | 2 | `--check` is 2, waybar is still 0 |

## The drift this page corrects

A receipt says 21:

> the claude-capacity oracle (from the herdr merge, 21 hermetic cases) is the
> Claude feeder waiting to be wired

— `/home/tom/research-methods/sessions/P05-handoff.md`, session dated
2026-09-06 (19 words).

That is the only carrier of the figure this unit could reach on disk. The
`l8-flash` PR body was reported to repeat it; the local copy at
`dotfiles-wt-l8-flash/.l8-flash/PR-BODY.md` (2026-09-06) does **not** — its one
mention is `` `claude-capacity` (from the herdr merge) and `nightly-record` both
exist and feed nothing``, carrying no count at all. Whether the body opened as
PR #285 differs from that copy is unchecked here; reading it is a network act
and this unit made none.

The unit that produced this page was asked to correct the line **or name the
two**. The two cannot be named, and the reason is on disk:

- `tests/claude-capacity/test-claude-capacity.py` has **exactly one commit** in
  this repository, `64879c9d`. `git log --follow` on the path returns that and
  nothing else.
- It landed with 23 cases. Its own commit message says so: *"23 cases,
  hermetic (seeded cache, temp HOME, dead token)"*.
- So no 21-case revision of the suite ever existed, and no pair of cases was
  ever added to a 21 to make 23. There is no "the two" to name.
- Guessing is not available either: **four** of the six blocks above hold
  exactly two cases, so subtracting a pair from 23 reaches 21 four different
  ways and the record picks none of them.

21 is a transcription error in a receipt, not a stale count of a smaller suite.
The suite is the authority; the receipts that say 21 are wrong at that word and
correct elsewhere, and they are append-only history, so they are **not edited** —
this page is the correction, and it is the number any future receipt should
copy from.

## Running it

Out of nix (this is the oracle; no network is required or used):

```
python3 tests/claude-capacity/test-claude-capacity.py   # 23/23 passed, rc 0
```

`CLAUDE_CAPACITY=<path>` overrides which script is exercised, which is how the
flake check points the suite at the store copy.

In nix, together with the `py_compile` guard on the script itself:

```
nix build .#checks.x86_64-linux.claude-capacity
```

## What this page is not

It does not say the oracle is wired to anything. It is not: dotfiles#304 is the
open issue for `usageMeter` feeders on the seat rows, and until that is ruled
and built, `claude-capacity --check` is a question nothing in the fleet asks.
The count is a fact about the suite, not a claim about admission.
