# `seats` — one capacity oracle for every seat on this box

> **Status 2026-11-13 (#536).** `seats` is live. Tally (its timers, meters and
> `home/tally.nix`), Pi and the ds4 server on strix-worker, named in passages
> below, are retired; those passages are history.

One command answers the question that was previously assembled by hand at the
start of every session: **what has capacity right now, and until when.**

```
$ seats
SEAT             STATE    SESSION (5h)       WEEKLY (7d)        NEXT RESET          IN+OUT  W/CACHE  NOTE
cc               spent      1.0% ░░░░░░░░░░   97.0% ██████████  Wed 10:00Z in 1d4h  11.6M   5.8G
cc2              spent      0.0% ░░░░░░░░░░  100.0% ██████████  Thu 06:00Z in 2d0h  24.0M   6.7G
codex            spent    —                   98.0% ██████████  Sat 07:18Z in 4d2h  1.3G    2.5G
gpu-strix        open     —                  —                                      —       —       up, serving qwen3.8-flash-next

per-model weekly rows (bind that model only):
  cc             weekly · Fable         100.0% ██████████  resets in 1d4h

read at 2026-09-08T05:16:34Z
```

(A 2026-09-08 reading, trimmed to the seats that still exist; see "Retired
seats" below.)

## Where each number comes from

| Seat | Truth | Costs |
|---|---|---|
| `cc`, `cc2` | `api.anthropic.com/api/oauth/usage`, per-seat OAuth token from `~/.claude*/.credentials.json` | one request, usually zero (see freshness) |
| `codex` | `codex app-server` over JSON-RPC — the account's own live answer | one short-lived process, cached |
| `gpu-strix` | `GET /ready` on the Gufo server at the fleet endpoint (`LOCAL_MODEL_ENDPOINT`, `http://strix-coordinator:8731`), then `GET /v1/models` if `/ready` names no model id | two requests, nothing spent |

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
already called it for every Claude seat **every 30 seconds**. So the acquisition
order is:

1. this program's own reading, inside `--cache-ttl` (default 60s)
2. **the seat feeder's reading**, inside the same window — the identical call,
   already paid for, left beside its meter rows as `.window-cache-<seat>.json`
3. the network
4. either cache, up to `--stale-grace` (default 900s), graded `CACHED`

A ten-minute-old utilization figure routes work correctly; a shrug does not.
Two programs on one box disagreeing about one seat's number would be worse
than either being slightly stale.

## Retired seats

Two seats were removed on 2026-11-12. `cc3`, the third Claude login
(`~/.claude-3`), was out of use since 2026-09-22. The Qwen Cloud token-plan
seat, which pi and then dsh spent, went with the account (closed 2026-11-01;
pi itself was retired on 2026-10-25), together with its `--probe-qwen` flag
and the refusal-text window and credit calibration it carried. That
measurement stays in git history and in `DECISIONS.md`.

## Codex reads the account, not the rollouts

The account is the default source, and the reason is a measurement. On
2026-09-08 the newest rollout on this box said the weekly window was **98%
spent**; the account said **0%** — the window had reset and no rollout had been
written since. The local read was not merely stale, it was wrong in the
direction that stops work.

A rollout records what Codex was *told* at the time it last ran. Only the
account knows what is true now. `--codex-rollouts` forces the local read
(no process spawned) and the row is then graded `CACHED` and labelled
"what Codex was last told, not what the account says now".

The live answer also carries what no rollout does:

- **per-model limit rows** — `rateLimitsByLimitId` holds one entry per limit;
  a named entry (`GPT-5.3-Codex-Spark`) is a per-model cap with its own 5-hour
  and weekly windows. Only the account's own rows bind the seat.
- **rate-limit reset credits** — grants that hand back a full window. They are
  spendable only by a person and **they expire**, so they are reported with
  their next expiry date. Hiding three of these would be hiding capacity.
- `planType`, credit balance, and `spendControlReached`.

`account/read` is deliberately not called: it returns the login's email
address, and this login is not Tom's (RULINGS R-2026-09-06-02). `planType` is
already on the rate-limits result.

## Scoped model caps: reported from the API, cap cited from the docs

Both providers publish model-scoped limits alongside the account-wide one:
Anthropic as a `weekly_scoped` entry with `scope.model.display_name`, OpenAI as
a named entry in `rateLimitsByLimitId`. Each has its own percentage, its own
severity, and its own reset. **Both numbers are repeated exactly as the API
states them.**

What Anthropic documents about the Fable cap
([support.claude.com/…/15424964](https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan),
updated week of 2026-09-01):

> "You can use up to 50% of your weekly usage limits on Fable models at no
> extra cost. **They draw from your plan's regular weekly usage limits and use
> them faster than other Claude models.** When you reach your Fable limit, you
> can keep using Fable models with usage credits, or switch to another model to
> stay within your plan's usage limits."

and, answering the obvious question head-on:

> "**Will I get 50% more for my weekly limit for Fable models…?** No. You can
> use up to 50% of your weekly limit on Fable models, but your use of other
> models draws from the same usage limits and you can never use more than your
> weekly limit."

So the scoped cap is a **slice** of the weekly allowance, not a budget beside
it, and scoped usage draws the account row down too. That is sourced, and it is
carried per model as `documented_term` — a citation with its quote, URL and
check date, sitting beside the reading.

**The conversion between the two percentages is not documented, so it is not
computed.** "Fable at 100%" plausibly means 50 points of the weekly row, but
Anthropic never says so, and two clauses above make a local check impossible:
Fable "use[s] them faster than other Claude models" (tokens are weighted, so
counting tokens per model proves nothing about points), and usage on claude.ai
and Claude Desktop counts against the same limits (so this box cannot see all
of it). An earlier version of this tool published a derived points figure as if
it were measured; a test now asserts those field names never return.

```
model-scoped limits (their own cap, stated by the provider; the account row above is the ceiling for everything else):
  cc     Fable                weekly  100.0% ██████████ resets in 1d2h  critical ← governing  [documented cap: 50% of the weekly allowance]
  cc     account (all models) weekly   97.0% ██████████ 3% left for everything else
  codex  GPT-5.3-Codex-Spark  5h        0.0% ░░░░░░░░░░ resets in 4h59m
  codex  account (all models) weekly    0.0% ░░░░░░░░░░ 100% left for everything else
```

When a scoped model is capped but the account still has room, the report says
so, because Anthropic states the escape explicitly: *"keep using Fable models
with usage credits, **or switch to another Claude model** to keep working
within your plan's usage limits."*

```
  cc     → Fable is capped, but the account has 3% left: switch models to keep working on this seat
```

### `is_active` is carried, not interpreted

The payload's `is_active` flag looks like "the limit currently governing". It
is not, and this was checked before relying on it:

| payload | session | weekly_all | weekly_scoped | flag on |
|---|---|---|---|---|
| [claude-code#87419](https://github.com/anthropics/claude-code/issues/87419) (2026-08-17) | 5% | 14% | 16% | **session** |
| [#79412 comment](https://github.com/anthropics/claude-code/issues/79412) (2026-08-22) | 0% | 50% | 44% | **weekly_all** |
| this box | 2% | 97% | 100% | **weekly_scoped** |

The first row is the counterexample: the flag sits on a 5% window while a
scoped row sits higher. It is neither "highest" nor "nearest exhaustion".
Anthropic documents nothing, Claude Code never reads the field, and CodexBar
decodes it and then ignores it. So it is published raw as
`seat.model_budget.provider_is_active_on` and **nothing depends on it** — a
test asserts the state does not move when only the flag moves.

### The legacy null fields

`seven_day_opus` / `seven_day_sonnet` are the flat per-model buckets that
`limits[]` superseded. `seven_day_opus` remains in Claude Code's known-keys
list but is no longer rendered anywhere. Null means "no legacy bucket applies
to this account", **not** "no per-model data available" — the per-model data is
in `limits[]`, which is what this reads.

## Pending allowance changes

A weekly percentage is a fraction of an allowance, and the allowance moves. The
report carries dated advisories for changes that have not yet taken effect, and
drops each one once its date passes:

> **! allowance change in 5d16h (2026-09-14):** Claude Code weekly limits drop
> from the temporary +50% boost (ends 2026-09-13) to a permanent +25% over the
> pre-July baseline — about 17% less than now.

Source: [BleepingComputer, 2026-08-29](https://www.bleepingcomputer.com/news/artificial-intelligence/anthropic-is-cutting-claude-codes-current-weekly-limits-by-17-percent/).
Add entries to `ALLOWANCE_CHANGES` as they are announced.

Note also that usage on claude.ai, Claude Code and Claude Desktop all counts
against the same limits ([support.claude.com/…/11647753](https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work),
updated 2026-07-13) — which is why the transcript token counts in this report
are a floor on consumption, never the whole of it.

## The provider's grading may tighten the state, never loosen it

Anthropic's payload grades each limit `normal` / `warning` / `critical` — this
box has observed 45% graded `normal` and 97% graded `critical`. It is a real
field and it is the provider describing its own product, so it is used.

But the threshold at which it flips is documented nowhere, and a sibling field
on the same entries (`is_active`, above) turned out to mean something other
than the obvious reading. So severity is allowed to make the answer **more**
conservative and never less: a seat is as spent as the worse of the provider's
grade and the local threshold. An undocumented field whose semantics might
shift can then cost some caution, never a flooded window.

`seat.state_basis` names which rule fired and mentions the other.

`seat.overage` carries whether there is any way past the wall at all —
`extra_usage_enabled`, `credits_enabled`, `can_purchase_credits`.

## Grades

| Grade | Means |
|---|---|
| `MEASURED` | read from the provider's own live answer |
| `MEASURED-FROM-REFUSAL` | read out of the provider's own 429 text |
| `ESTIMATED` | measured window bounds, position inside them from a calibrated constant (no current seat reports it) — `--pick` ranks these at the conservative end of the calibration's spread |
| `CACHED` | a live answer older than the TTL; the age is in `source.reading_age_seconds` |
| `UNKNOWN` | nothing on this box knows — the row says so and never counts as headroom |

## States

`open` (every binding window under 80%) · `tight` (80–95%) · `spent` (a binding
window at 95%, or a provider refusal in force) · `n/a` (a device with no
server declared behind it; graded `UNKNOWN`, never headroom) · `unauth` ·
`offline` · `unknown`.

The GPU row has no windows. `gpu-strix` is `open` when the Gufo server
answers `/ready` (a busy GPU is a queue, not a wall) and `offline` when it
does not. It is not a subscription, so `--pick` never names it and `--check`
on it answers 2. The ds4 DeepSeek server on strix-worker (`:8732`, started by
hand) has no row.

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
seats --only cc,cc2      # by seat id or by provider (claude, codex, gufo, openrouter, none)
seats --watch 60         # redraw on an interval
```

Exit-code oracles, for scripts and dispatchers:

```sh
seats --check cc                           # 0 headroom / 1 spent / 2 unmeasurable
seats --check cc --window five_hour --threshold 80
seats --pick                               # prints the seat with the most headroom, 1 if none
```

`--check` fails **closed**: 2 (unmeasurable) is distinct from 1 (measured, no
headroom) so a caller may choose to fail open with `|| exit 0`, but a wrapper
that treats every nonzero as "defer" will defer on an unreachable API rather
than flood a spent window. That is the safe direction at 3 a.m.

Other flags: `--refresh` (skip the reuse window), `--no-spend` (skip the
transcript scan), `--days N` (spend window when a seat publishes no weekly
reset), `--codex-rollouts` (read Codex's own rollouts instead of asking the
account), `--no-color`.

`SEATS_NO_NETWORK=1` makes every outbound call fail immediately — useful on a
train, and how the test runs. Nothing degrades to a guess; rows say `CACHED` or
`UNKNOWN`.

`SEATS_INFERENCE_URL` overrides the `gpu-strix` row's base URL (default
`LOCAL_MODEL_ENDPOINT`, `http://strix-coordinator:8731`). The override
is for pointing the row at a hand-run `llama-server`, not for a second
declared server.

## Configuration

None is required. `~/.config/seats/seats.json`, if present, replaces the seat
table wholesale — a list of `{id, provider, label, owner, config_dir,
spend_root, endpoint, reason, note}` objects (`endpoint` for a `gufo` row,
`reason` for a `none` row). Seat ids are the pool names in
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

`nix build .#checks.x86_64-linux.seats` — 41 assertions against a home tree the
test builds itself (every fact here is relative to *now*, so a checked-in
fixture would rot on the second day), with `SEATS_NO_NETWORK=1`.
