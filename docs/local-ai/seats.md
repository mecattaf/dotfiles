# `seats` — one capacity oracle for every seat on this box

One command answers the question that was previously assembled by hand at the
start of every session: **what has capacity right now, and until when.**

```
$ seats
SEAT             STATE    SESSION (5h)       WEEKLY (7d)        NEXT RESET          IN+OUT  W/CACHE  NOTE
cc               spent      1.0% ░░░░░░░░░░   97.0% ██████████  Wed 10:00Z in 1d4h  11.6M   5.8G
cc2              spent      0.0% ░░░░░░░░░░  100.0% ██████████  Thu 06:00Z in 2d0h  24.0M   6.7G
cc3              open       0.0% ░░░░░░░░░░   45.0% ████░░░░░░  Sat 11:00Z in 4d5h  662.3k  66.6M
codex            spent    —                   98.0% ██████████  Sat 07:18Z in 4d2h  1.3G    2.5G
pi-qwencloud     spent    —                  100.0% ██████████  Sat 08:02Z in 4d2h  1.7M    83.3M   weekly quota exhausted…
gpu-coordinator  open     —                  —                                      —       —       idle, no model resident
gpu-worker       offline  —                  —                                      —       —       unreachable

per-model weekly rows (bind that model only):
  cc             weekly · Fable         100.0% ██████████  resets in 1d4h

on course to hit the wall before it resets:
  cc3            weekly (7d)            0.7%/h → 100% in 3d9h (Fri 14:16Z), window resets in 4d5h

read at 2026-09-08T05:16:34Z   most headroom: cc3
```

## Where each number comes from

| Seat | Truth | Costs |
|---|---|---|
| `cc`, `cc2`, `cc3` | `api.anthropic.com/api/oauth/usage`, per-seat OAuth token from `~/.claude*/.credentials.json` | one request, usually zero (see freshness) |
| `codex` | the `rate_limits` records Codex writes into its own rollouts under `~/.codex/sessions` | nothing — reading a rollout is not a spend |
| `pi-qwencloud` | the reset stated in the provider's own 429 text | nothing, unless `--probe-qwen` |
| `gpu-coordinator`, `gpu-worker` | `llama-swap` `/running` | nothing |

Token counts come from the harnesses' own transcripts — the same records
`nightly-record` reads — counted from the moment **that seat's** weekly window
opened, not over a rolling week, because a percentage and a token count that
refer to different intervals cannot be compared.

`IN+OUT` is input plus output. `W/CACHE` adds cache reads and writes, which
dominate any seat that works in one repo all week and are the reason the two
columns are separate.

## Freshness, and why this is not a fourth poller

`/api/oauth/usage` rate-limits: a handful of hand polls in one minute already
returned 429 (measured 2026-09-02), and `tally-seat-feeder-claude.timer`
already calls it for all three seats **every 30 seconds**. So the acquisition
order is:

1. this program's own reading, inside `--cache-ttl` (default 60s)
2. **the seat feeder's reading**, inside the same window — the identical call,
   already paid for, left beside its meter rows as `.window-cache-<seat>.json`
3. the network
4. either cache, up to `--stale-grace` (default 900s), graded `CACHED`

A ten-minute-old utilization figure routes work correctly; a shrug does not.
Two programs on one box disagreeing about one seat's number would be worse
than either being slightly stale.

## Qwen Cloud: measured, not guessed

Qwen Cloud (Alibaba token-plan) publishes **no** usage endpoint. Its allowance
is a plan-credit page nothing here can read — which is why the tally meter row
for it has always been `UNKNOWN`. Two things had to be established before a
percentage could exist. Both were measured from this box's own history.

### 1. The window opens on first use, not on the reset

Four exhaustion events sit in pi's session logs, each carrying the provider's
stated reset. Three of the four windows begin within **24 seconds** of the
first qwen call after the previous reset:

| stated reset | window opened | gap |
|---|---|---|
| 2026-08-14 10:06Z | 2026-08-07 11:07:19Z | +61 min |
| 2026-08-22 13:34Z | 2026-08-15 13:34:24Z | +24 s |
| 2026-09-04 11:50Z | 2026-08-28 11:50:09Z | +9 s |
| 2026-09-12 08:02Z | 2026-09-05 08:02:24Z | +24 s |

So the window is **not** a calendar week: it is seven days from first use after
the previous reset, and an idle box burns no window. (The first row is an hour
out because it is the first window ever — something opened it before pi was
logging.) The reset stamps are recovered from the refusal texts in the session
logs themselves, so this needs no state file anyone has to maintain.

### 2. A credit is worth ~192 billable tokens, and cache reads are free

Each of those four windows ended at exactly 10,000 credits, which makes them
four independent readings of one constant. Fitting output weight and
cache-read weight against all four:

| formula | spread across the four windows | implied price |
|---|---|---|
| **input + output, cache reads free** | **10.7%** | **192.5 tokens/credit** |
| any nonzero cache-read weight | strictly worse — best fit puts it at 0 | — |
| cache reads alone | 30.4% | — not what is metered |

Per-window samples: 183.2, 224.8, 193.1, 169.0 tokens/credit.

**Cache reads are not charged.** That is the load-bearing finding: 98% of the
tokens crossing this seat are cache reads, so a meter that counted them would
have walled these windows five times sooner than they actually walled. The pi
session store also carries llama-swap and flashnix-local traffic, served by the
GPU in this room at no cost to the subscription; that is filtered out too.

**The output weight is not identifiable from this data.** The output:input
ratio sat at 0.33–0.37 in all four windows, so weighting output 1× or 6× moves
the spread only 10.7% → 9.2%. Parity is assumed, and the estimate therefore
holds only for work of a similar shape — heavy-reasoning work would burn faster
than this says.

So: **10,000 credits ≈ 1.92M input+output tokens per week, ±11%.**

The plan lives in `QWEN_PLAN` and is overridable at
`~/.config/seats/qwen-plan.json` (`credits_per_window`, `window_days`,
`tokens_per_credit`, `max_concurrent_agents`) — a plan change is one file, not
an edit to the program.

### Concurrency is a plan term

Standard runs **3–4 agents concurrently** (Lite runs 1–2); 4 is the ceiling for
this box, and the number is published with the seat. What this data *cannot*
show is whether exceeding it costs extra credits per token — all four
calibration windows were worked inside the cap. What it *can* show is that
fan-out multiplies context re-sends and input tokens are charged: five agents
on one task bill five prompt prefixes, so the window drains faster whether or
not the provider adds a surcharge.

### What still needs the provider

A live refusal outranks the estimate — the provider saying "exhausted" is a
measurement, and an estimate that disagrees with it is wrong. A free
`GET /models` confirms the key still authenticates, which is a different fact
from having headroom. `--probe-qwen` spends one token to learn the real state
and writes the result back to the hold record; it is opt-in precisely because
asking costs the thing being measured.

## Scoped model caps: Fable and the account together

Fable is **half the individual subscription** on `cc` and `cc2`. Its scoped
weekly row reaching 100% means Fable has eaten 50 points of the account's week
— it does **not** mean the seat is finished. Opus and Sonnet may keep going
against whatever the account's overall weekly row has left. Read alone, either
number misleads, so both are published:

```
per-model weekly caps (a slice of the account's own week, in points of that week):
  cc     Fable    100.0% ██████████ of its 50-point cap = 50 pts spent
                  →  0 pts left for Fable, 3 pts left for other models
  cc2    Fable     96.0% ██████████ of its 50-point cap = 48 pts spent
                  →  0 pts left for Fable, 0 pts left for other models
```

The account cap bounds a scoped model too: when `cc2`'s week is at 100%, Fable
having 4 points of its own share left is irrelevant — `points_left_for_this_model`
is the smaller of the two.

In JSON this is `seat.model_budget`: `account_used_pct`,
`account_remaining_pct`, `points_left_for_other_models`, and a row per model
with `used_pct`, `share_of_total`, `account_points_used`, `account_points_cap`
and `points_left_for_this_model`.

The share is per-seat config (`model_shares: {"fable": 0.5}` on `cc` and `cc2`).
`cc3` is Pro and carries no Fable row yet — when it is upgraded, add the same
entry and nothing else changes.

## Grades

| Grade | Means |
|---|---|
| `MEASURED` | read from the provider's own live answer |
| `MEASURED-FROM-REFUSAL` | read out of the provider's own 429 text |
| `ESTIMATED` | measured window bounds, position inside them from a calibrated constant (Qwen credits) — `--pick` ranks these at the conservative end of the calibration's spread |
| `CACHED` | a live answer older than the TTL; the age is in `source.reading_age_seconds` |
| `UNKNOWN` | nothing on this box knows — the row says so and never counts as headroom |

## States

`open` (every binding window under 80%) · `tight` (80–95%) · `spent` (a binding
window at 95%, or a provider refusal in force) · `busy` (a GPU with a model
resident — a queue, not a wall) · `unauth` · `offline` · `unknown`.

**Only the session and weekly windows bind.** A per-model weekly row — `Fable`
at 100% on `cc` — restricts that model and nothing else, so it is reported
separately and never spends the seat. This is the fact the meter rows record as
`model_split: UNKNOWN`: `usage.seven_day_opus` really is null, but the same
payload's `limits[]` array carries the scoped rows with
`scope.model.display_name`.

## Output

```sh
seats                    # the table
seats --json             # one document, schema seat-capacity/1
seats --jsonl            # one line per seat — append to a ledger, pipe to jq
seats --tsv              # one row per window — awk, sort, a spreadsheet
seats --only cc,cc3      # by seat id or by provider (claude, codex, qwen, llama-swap)
seats --watch 60         # redraw on an interval
```

Exit-code oracles, for scripts and dispatchers:

```sh
seats --check cc3                          # 0 headroom / 1 spent / 2 unmeasurable
seats --check cc3 --window five_hour --threshold 80
seats --pick                               # prints the seat with the most headroom, 1 if none
```

`--check` fails **closed**: 2 (unmeasurable) is distinct from 1 (measured, no
headroom) so a caller may choose to fail open with `|| exit 0`, but a wrapper
that treats every nonzero as "defer" will defer on an unreachable API rather
than flood a spent window. That is the safe direction at 3 a.m.

Other flags: `--refresh` (skip the reuse window), `--no-spend` (skip the
transcript scan), `--days N` (spend window when a seat publishes no weekly
reset), `--codex-live` (ask `codex app-server` over JSON-RPC instead of reading
rollouts), `--no-color`.

`SEATS_NO_NETWORK=1` makes every outbound call fail immediately — useful on a
train, and how the test runs. Nothing degrades to a guess; rows say `CACHED` or
`UNKNOWN`.

## Configuration

None is required. `~/.config/seats/seats.json`, if present, replaces the seat
table wholesale — a list of `{id, provider, label, owner, config_dir,
spend_root, endpoint, note}` objects. Seat ids are the pool names in
`home/tally.nix` and the row names in `~/.local/state/tally-rewrite/meters`,
deliberately: a row here and a row there must be joinable by one field.

## Relationship to what was already here

- `claude-capacity` — one Claude seat, waybar-shaped, and the dispatch
  admission oracle wired into tally. Unchanged; `seats` does not replace it.
- `tally-seat-feeder` — stamps kernel meter rows on a 30-second timer so the
  rewrite's admission rungs see fresh rows. `seats` reads its cache and never
  competes with it.
- `nightly-record` — one row per seat-lane per day, banked nightly. `seats`
  reads the same transcripts for a live window rather than a closed day.

`seats` is standalone by design: stdlib only, no tally, no daemon, no bar. It
reads the same sources as those three, so it cannot disagree with them about a
number, but it does not need any of them alive.

## Test

`nix build .#checks.x86_64-linux.seats` — 20 assertions against a home tree the
test builds itself (every fact here is relative to *now*, so a checked-in
fixture would rot on the second day), with `SEATS_NO_NETWORK=1`.
