# Tally flows — waves 1+2 campaign (authored 2026-07-25)

Flow scripts for the post-LaCie campaign: local-model materialization (lane A) and
the notes-reshape/drain arc (lane B), run concurrently. Authored against the
flow-era tally.nix on its `main` (e7ae081, FS-1…FS-7 landed). **Nothing here is
wired or scheduled yet** — `tally-flows.nix` is deliberately NOT imported, and no
flow runs until dotfiles issue #104 (LaCie post-restore) closes and T0 below is done.

Codex is the agentic harness for all implementation nodes (ruled 2026-07-25);
Claude Code is not used as a flow node. Local quorum work goes through `local()`
members on coordinator llama-swap; the soft-retired worker remains optional.

## T0 — flow-era readiness (babysat, daylight; tracked as its own issue)

1. Bump `inputs.tally` to the flow-era rev (>= e7ae081): `nix flake lock --update-input tally`.
2. Deploy **worker first, then coordinator**, with a manual rollback path staged.
   Caveat #106: `nixos-rebuild --rollback` is currently broken — babysit, do not
   let the nightly producer take this generation unattended.
3. Add the `codex-window` pool (resource `subscription`, capacity 1, cooperative)
   to `home/tally.nix` pools; flows here declare it.
4. Import `flows/tally-flows.nix` next to `home/tally.nix` and verify the
   `services.tally.flows` option surface exists on the HM module (surveyed in
   tally.nix `nix/modules/common.nix` ~1493; confirm HM export).
5. `tally flow check flows/<each>.js` (also runs under `nix flake check` once
   wired). All six flows + the selector catalog already passed flow check
   against the flow-era binary on 2026-07-25; re-run after any edit.
6. Reconcile the 9 ORACLE-DELTAS listed in tally.nix `legacy-docs/campaign/MORNING-REPORT.md`
   (non-blocking).
7. Normalize the repo: resolve the uncommitted `hosts/coordinator/services.nix`
   drift and stray `result` symlink before the input bump lands.

## Run order and gating

| flow | lane | gates on | agent nodes |
|---|---|---|---|
| `allowlist-implementation` | A1 | T0 | codex |
| `parakeet-determinism` | A2 | T0 | codex |
| `materialize-model-weights` | A3 | #104 CLOSED (in-flow gate node) + A1 | none (pure sh) |
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
  `build`, `coordinator-gpu`, plus `codex-window` added at T0. Weight downloads
  serialize through `build` deliberately — one WAN link, and it keeps the lane
  honest against the nightly deploy.
- `materialize-model-weights` builds `.#models.<artifactId>` store paths; get the
  current id list with
  `nix eval .#legacyPackages.x86_64-linux.models --apply builtins.attrNames`.
  Parakeet artifact ids join the list once A2 lands.
- Uncensored roster ruling 2026-07-25: only `qwen3.6-35b-heretic` materializes;
  the other two uncensored deployments stay cataloged, not downloaded.
