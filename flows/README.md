# Tally flows — waves 1+2 campaign (authored 2026-07-25)

Flow scripts for the post-LaCie campaign: local-model materialization (lane A) and
the notes-reshape/drain arc (lane B), run concurrently. They are registered on
coordinator against tally.nix 0.1.0 (`6b250541`) but remain unscheduled: every
entry has `onCalendar = null` and runs only through an explicit
`tally flow run`. Dotfiles issue #104 is closed; its materialization gate remains
in the script as witnessed proof rather than an active blocker.

Codex is the agentic harness for all implementation nodes (ruled 2026-07-25);
Claude Code is not used as a flow node. Local quorum work goes through `local()`
members on coordinator llama-swap.

## T0 — flow-era readiness record

- The worktree was clean, had no stray `result` symlink, and passed
  `nix flake check` before the input bump.
- `inputs.tally` is pinned to tally.nix 0.1.0 at `6b250541`, past the original
  flow-era minimum `e7ae081`.
- The Home Manager module exports `services.tally.flows`; `home/tally.nix`
  imports this registry on coordinator only.
- The Codex lane used to be a cooperative capacity-one mutex pool named after
  the harness window. It was retired on 2026-09-06 (dotfiles#291, dotfiles#302)
  and replaced by per-seat `budget` rows in `home/tally.nix`. Flows deliberately
  cannot lease windowed-consumption budget pools — see "The Codex lane is gone"
  below.
- Tally 0.1.0 reserves `build` for `drv()` nodes. Shell nodes use
  `flow-build`; the nightly deploy leases both lanes to retain exclusivity.
- The returned compute host is removed under #117. There is no remote-first
  activation; the operator performs the coordinator switch and test drive
  manually. This repository change does not deploy or switch a host.
- The ORACLE-DELTAS reconciliation remains Tom's separate, non-blocking item.

## Run order and gating

| flow | lane | gates on | agent nodes |
|---|---|---|---|
| `allowlist-implementation` | A1 | T0 | codex |
| `parakeet-determinism` | A2 | T0 | codex |
| `materialize-model-weights` | A3 | A1; #104 is closed (in-flow proof remains) | none (pure sh) |
| `docs-model-split` | A4 | A1 landed (roster reflects allowlist) | codex |
| `issue-96-drain` | B2 | T0; final acceptance gates on notes cutover (prompt A) | codex |
| `errata-map` | B3 | notes cutover (in-flow gate node) + A3 (local members need weights) | codex + local quorum |

Prompt A (notes cutover) stays a supervised session, not a flow. Prompt C and
inbox-july23 processing follow B-lane completion as sessions.

## Invocation

One-shot (all flows have `onCalendar = null`):

```
tally flow check flows/errata-map.js --args '<json>' --catalog flows/catalog.json
tally flow run   flows/errata-map.js --args '<json>' --catalog flows/catalog.json
```

Args defaults live in `tally-flows.nix`; override per run with `--args`.

## The Codex lane is gone, and these flows cannot get it back at this pin

`home/tally.nix` no longer declares a per-harness window mutex for Codex; the
five flows below dropped it from `meta.pools` on 2026-09-06 (dotfiles#302).
They stay registered and dormant (`onCalendar = null`) so that the fact stays
visible rather than being deleted with them.

Affected: `allowlist-implementation`, `parakeet-determinism`, `docs-model-split`,
`issue-96-drain`, `errata-map`. Their `sh()` nodes are unaffected — those name
`flow-build` and `coordinator-gpu`, which still exist. Their `codex()` nodes are
**refused at admission** and will stay refused until a later tally lands
seat-named sugar.

Three facts from the pinned tally (`mecattaf/tally.nix` `62fac87c`) decide this,
and none of them has a workaround on the dotfiles side:

1. `codex()` fixes its node's pool set to exactly the retired per-harness window
   name (`doc/src/flows/host-api.md`), and the sugar takes no pool argument. A
   flow cannot ask for the `codex` seat row, or any other seat.
2. A flow may not name a windowed-consumption pool at all.
   `crates/tally-flow/src/dialect.rs::validate_flow_pool_predicates` rejects it
   with `FlowPoolError`/`windowed-consumption-excluded` — *"flows are excluded
   from windowed-consumption admission by design; use priorities to control
   contention between workloads"* — and the Nix module always runs `flow check`
   WITH the config, so pointing `meta.pools` at the new `codex` row would fail
   the build, not merely the run.
3. There is nothing to declare instead. `host-api.md`: *"There is deliberately
   no `consumptionEstimate` field"*; an unknown field is
   `FlowSpecError`/`unknown-spec-field`. `consumptionEstimate` exists only on
   `enqueue`, never on the flow spec surface.

The upstream ask is dotfiles#305.

## Notes

- Pool names reference the live coordinator daemon config (`home/tally.nix`):
  `flow-build` and `coordinator-gpu`. Weight downloads serialize through
  `flow-build` deliberately — one WAN link — and the nightly deploy leases that
  lane as well.
- `materialize-model-weights` builds `.#models.<artifactId>` store paths; get the
  current id list with
  `nix eval .#legacyPackages.x86_64-linux.models --apply builtins.attrNames`.
  Parakeet artifact ids join the list once A2 lands.
- Uncensored roster ruling 2026-07-25: only `qwen3.6-35b-heretic` materializes;
  the other two uncensored deployments stay cataloged, not downloaded.
