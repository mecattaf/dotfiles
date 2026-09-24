# @substrate/factory

U-A11 supplies the host-neutral Factory service over the `PlanningStore`
interface. Tests compose the in-memory store, one constant `PriceVector`, and an
authored fake capacity feed. The package has no Worker entry and no SQLite
binding; those are U-A14's composition-root work.

The service owns the `unclaimed → released → inflight → closed` lifecycle.
`handOut` makes the first transition, `observeOutcome` applies `Accepted`,
`Rejected`, or `NotYet`, and `observeVerdict` mirrors a chained kernel record,
deduplicates `(executor, seq, hash)`, updates WIP once, and wakes the evaluator.
Only an `inflight` item may consume a verdict; a merely `released` item is
refused with its current state and keeps its WIP unchanged. A non-pass verdict
retries under the plan's `attemptCap` with a new armed-plan-and-attempt dedup
identity; a pass closes the item and can release an item whose `dependsOn` edge
has just become satisfied.

The service schema-encodes its mutable state under `FACTORY_STATE_KEY` after
each accepted mutation and restores it when another Factory is constructed over
the same `PlanningStore`. Inflight work, WIP, readings, mirrored chain state,
alarms, outcome idempotence, deferrals, heartbeats, receipts, and facts therefore
survive an in-memory recreation today and the U-A14 SQLite Layer later.
The backlog schema includes optional `argv_ref` and `mutation_hint` cells, so
the command reference and evaluator control carried by an armed item survive
that same boundary and are unchanged when the item is proposed after restart.

`makeFactoryHttpHandler` exposes `/plans`, `/capacity`, `/proposals`, `/outcomes`,
`/verdicts`, `/receipts`, `/heartbeats`, and `/state` without instantiating a
Worker. A proposal pull returns `{ proposals, next_wake_at }`, including the wake
instant when every row is stopped and the proposal list is empty. Every
state-changing request—including that GET proposal pull—requires the bearer
token supplied by the host. Receipt ingestion first uses the strict §2.3 decoder,
then requires `oracle_rc`, `mutation_rc`, and
`oracle_output_sha256` to match one mirrored verdict exactly.

The `/plans` route accepts the acceptor's producer body
`{ planHash, script_bytes_base64, args_bytes_base64, plan }`, hashes the decoded
script-plus-args bytes, and expands the emitted items into the Factory backlog.
The same plan hash is also the stable internal plan id, so posting the identical
producer payload again is append-only and duplicate-free.

The dominant checks are documented in [docs/factory.md](../../docs/factory.md).
