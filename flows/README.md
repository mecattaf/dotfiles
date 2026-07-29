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
- `codex-window` is a cooperative capacity-one mutex. Tally 0.1.0 has no
  `subscription` resource class, and flows deliberately cannot lease
  windowed-consumption budget pools.
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

## Notes

- Pool names reference the live coordinator daemon config (`home/tally.nix`):
  `flow-build`, `coordinator-gpu`, and `codex-window`. Weight downloads
  serialize through `flow-build` deliberately — one WAN link — and the nightly
  deploy leases that lane as well.
- `materialize-model-weights` builds `.#models.<artifactId>` store paths; get the
  current id list with
  `nix eval .#legacyPackages.x86_64-linux.models --apply builtins.attrNames`.
  Parakeet artifact ids join the list once A2 lands.
- Uncensored roster ruling 2026-07-25: only `qwen3.6-35b-heretic` materializes;
  the other two uncensored deployments stay cataloged, not downloaded.
