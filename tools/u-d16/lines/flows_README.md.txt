1. `codex()` fixes its node's pool set to exactly the retired per-harness window
2. A flow may not name a windowed-consumption pool at all.
3. There is nothing to declare instead. `host-api.md`: *"There is deliberately
Affected: `allowlist-implementation`, `parakeet-determinism`, `docs-model-split`,
and none of them has a workaround on the dotfiles side:
  and replaced by per-seat `budget` rows in `home/tally.nix`. Flows deliberately
  below.
  cannot lease windowed-consumption budget pools — see "The Codex lane is gone"
   contention between workloads"* — and the Nix module always runs `flow check`
   `crates/tally-flow/src/dialect.rs::validate_flow_pool_predicates` rejects it
   `enqueue`, never on the flow spec surface.
five flows below dropped it from `meta.pools` on 2026-09-06 (dotfiles#302).
`flow-build` and `coordinator-gpu`, which still exist. Their `codex()` nodes are
   flow cannot ask for the `codex` seat row, or any other seat.
   `FlowSpecError`/`unknown-spec-field`. `consumptionEstimate` exists only on
   from windowed-consumption admission by design; use priorities to control
`home/tally.nix` no longer declares a per-harness window mutex for Codex; the
`issue-96-drain`, `errata-map`. Their `sh()` nodes are unaffected — those name
   name (`doc/src/flows/host-api.md`), and the sugar takes no pool argument. A
   no `consumptionEstimate` field"*; an unknown field is
**refused at admission** and will stay refused until a later tally lands
seat-named sugar.
   the build, not merely the run.
## The Codex lane is gone, and these flows cannot get it back at this pin
- The Codex lane used to be a cooperative capacity-one mutex pool named after
  the harness window. It was retired on 2026-09-06 (dotfiles#291, dotfiles#302)
The upstream ask is dotfiles#305.
They stay registered and dormant (`onCalendar = null`) so that the fact stays
Three facts from the pinned tally (`mecattaf/tally.nix` `62fac87c`) decide this,
visible rather than being deleted with them.
   with `FlowPoolError`/`windowed-consumption-excluded` — *"flows are excluded
   WITH the config, so pointing `meta.pools` at the new `codex` row would fail
