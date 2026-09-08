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

## Qwen Cloud, the awkward one

Qwen Cloud (Alibaba token-plan) publishes **no** usage endpoint. Its allowance
is a plan-credit page nothing here can read — which is why the tally meter row
for it has always been `UNKNOWN`. But it states the reset in its own refusal:

```
Your token-plan 1-week quota has been exhausted.
The quota will reset at 09-12 08:02:00 UTC.
```

So the window is graded `MEASURED-FROM-REFUSAL`: parsed out of the last 429
this box actually received (from `~/.local/state/seats/qwen-hold.json` or the
factory lane's `pi-hold.json`, newest wins), never a made-up TTL. The year is
inferred — the refusal states only a month and day — by taking the year that
puts the reset after the refusal.

A free `GET /models` confirms the key still authenticates, which is a
different fact from having headroom. `--probe-qwen` spends one token to learn
the real state and writes the result back to the hold record; it is opt-in
precisely because asking costs the thing being measured.

## Grades

| Grade | Means |
|---|---|
| `MEASURED` | read from the provider's own live answer |
| `MEASURED-FROM-REFUSAL` | read out of the provider's own 429 text |
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
