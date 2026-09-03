# the local-models prune fires on every serve cycle, not just at boot

**Filed 2026-09-03 from the flashnix trinity bring-up.** Verified on `coordinator`.
Not yet acted on.

## The mechanism, read from the running units

`modules/local-models.nix:116` does `rm -rf "$dir"` for every directory in
`/var/lib/local-models` that the host's catalog does not declare. That much was known.
What was not known is **how often it runs**.

```
$ systemctl cat llama-swap.service | grep -E 'Wants|After'
After=network.target network-online.target local-models-sync.service
Wants=network-online.target local-models-sync.service

$ systemctl show local-models-sync.service -p Type -p RemainAfterExit -p ActiveState
Type=oneshot
RemainAfterExit=no
ActiveState=inactive
```

`llama-swap.service` **Wants** the sync unit, and the sync unit is a `oneshot` with
`RemainAfterExit=no`. A oneshot that does not remain after exit goes `inactive (dead)`
the moment it finishes — which is its state right now, having last run at 17:47. So the
`Wants=` pull is not a no-op on subsequent starts: **every `systemctl start
llama-swap` re-runs the prune.**

The coupling is the reverse of what it looks like. `local-models-sync.service` declares
only `WantedBy=multi-user.target` (`modules/local-models.nix:455`); it is `llama-swap`
that reaches for it.

## It is not hypothetical — it already destroyed this artifact repeatedly

`journalctl -u local-models-sync` on coordinator, Sep 1:

```
03:25:45  pruning retired artifact deepseek-v4-flash-0731-bf16
06:26:47  pruning retired artifact deepseek-v4-flash-0731-bf16
07:04:34  pruning retired artifact deepseek-v4-flash-0731-bf16
08:10:07  pruning retired artifact deepseek-v4-flash-0731-bf16
12:42:40  pruning retired artifact deepseek-v4-flash-0731-bf16
15:54:29  pruning retired artifact deepseek-v4-flash-0731-bf16
20:13:57  pruning retired artifact deepseek-v4-flash-0731-bf16
```

Seven sweeps in seventeen hours against a 156 GiB artifact, each one firing because
llama-swap started. It ran again on Sep 3 at 17:46 against a batch of other rows. This
is the direct explanation for why DeepSeek-V4 read as absent from both twins at the
start of the 2026-09-03 bring-up despite having been staged before: it was staged into
the pruned tree while undeclared, and the sweep removed it — more than once.

The unit is not lying about it either; it logs every removal with the artifact name.
Nothing was silent except the consequence.

## Why that matters more than a boot-time prune

`substrate/host/fn-cluster-up.sh` calls `fn-swap-arbitrate.sh stop` to take the GPUs,
which stops llama-swap on both twins, and teardown restores it. **Every flashnix serve
cycle therefore ends by triggering the prune.** The exposure window is not "overnight,
if the box reboots" — it is "once per model we bring up", several times a night.

Anything staged into `/var/lib/local-models` that the host's catalog does not declare is
deleted the next time llama-swap comes back. A row declared in Nix but not yet activated
(no `nixos-rebuild` run) counts as undeclared, because the prune reads the *running*
system's catalog.

## What flashnix did about it

Staged the two undeclared models to `/var/lib/flashnix-weights`, outside the pruned
tree, and taught `fn-cluster-up.sh` to bind `${FN_LOCAL_MODELS:-/var/lib/local-models}`
instead of a hardcoded path (flashnix `851e48a`). Qwen's `flashnext-fp8` stays in the
pruned tree and is safe there **because it is declared and active**.

That leaves a footgun worth knowing about: the weights root is one value for the whole
serve, so Qwen serves with `FN_LOCAL_MODELS` unset and the other two serve with it set.
An operator who exports it once and then serves Qwen gets a weight-load failure deep in
the engine rather than a clean preflight error.

## The question this leaves for dotfiles

Is the `Wants=` coupling deliberate? Re-syncing the model tree before llama-swap starts
is defensible; re-running a destructive `rm -rf` sweep on every service start is a
sharper edge than the module's own comments suggest. Candidates, none chosen:

- `RemainAfterExit=yes`, so it runs once per boot and the `Wants=` pull is a no-op after.
- Split the unit: a non-destructive fetch/sync that llama-swap may pull, and a prune that
  only activation runs.
- Leave it, and document that the pruned tree is unsafe for anything not in the catalog.

## Decides what

`modules/local-models.nix` (the prune and the unit definition) and whatever declares
`llama-swap.service`. No change made.
