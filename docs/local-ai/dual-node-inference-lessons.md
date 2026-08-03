# Dual-node inference: preserved lessons from the ds4 cluster

**Status: historical.** Nothing on this page is a current deployment target.
The fleet has one Strix Halo box. The second one was returned and the `worker`
host was retired on 2026-07-29 (commit `fad16604`, issue #117), so the
two-node topology this page describes cannot be reproduced on the current
fleet at all. Issue #62, which tracked adding a ds4 quadlet pair on the
Thunderbolt fabric, was closed unplanned on 2026-08-03.

The `ds4` backend kind survives in the code — `lib/local-model-backends.nix`
lists it and `lib/local-model-runtime.nix` renders its `ds4-server` command —
but no catalog row in `lib/local-models.nix` uses that backend, so the renderer
is never invoked and the model never loads. Treat the surviving `ds4` plumbing
as an unexercised code path, not as a switch waiting to be flipped.

This page exists because the June 17 build produced transferable operational
knowledge that would otherwise be lost when `docs/old/` was retired. It is
mined from `docs/old/migration-journal/ds4-dual-node-lessons.md`, whose full
text (build report, appendix, and exact container invocations) is recoverable
with:

```console
git show 74d76a53:docs/old/migration-journal/ds4-dual-node-lessons.md
```

## What was built, and what it measured

A pipeline-parallel [ds4](https://github.com/antirez/ds4) cluster — antirez's
DeepSeek V4 Flash engine — split across two identical Ryzen AI MAX+ 395
desktops joined by a direct Thunderbolt host-to-host cable (~0.4 ms RTT,
link-local IPv4). The coordinator held layers `0:21` plus output, the worker
held `22:output`, and the pair served an OpenAI-compatible API at 131072
context to a local `pi` coding session.

The measured result was **~11 tok/s generation**. The Thunderbolt hop is pure
overhead relative to single-node inference; the topology bought model capacity
(a 154 GB Q4 checkpoint), not speed. For comparison, the current single-node
`qwen3.6-35b-a3b` row on the same class of hardware benchmarks at 46.33 tok/s
decode. That gap is the core reason the distributed route is not in the active
catalog: on one 128 GiB box, a Q8 model that fits locally beats a larger model
paid for with a network hop.

## Lessons that still apply

These outlived the cluster. Each one cost real debugging time on hardware the
fleet still runs.

**`No route to host` on a box that answers ping is a firewall REJECT.** Every
time, on this hardware. Check the interface's zone before you suspect a dead
process or a missing listener. The symptom surfaced twice: once as ds4's
`distributed route incomplete: missing layer 22`, once as
`KV payload staging failed: unable to connect to <ip>:41265`.

**Reason about connection *direction*, not just reachability.** The build
concluded "you only need the coordinator's Thunderbolt interface trusted",
which was correct only because the main pipeline dials worker→coordinator.
Enabling `--kv-disk-dir` made KV eviction dial coordinator→worker on an
ephemeral port, which the worker's firewall rejected, which wedged every chat
completion indefinitely with no self-recovery. A feature flag can silently
reverse the direction of traffic and invalidate a firewall conclusion drawn
before it was enabled. `ss -tnp` showing a `SYN-SENT` retry loop with a cycling
source port is the tell.

**Link-local IPv6 zone indices need escaping in `~/.ssh/config`.** A `HostName`
containing `%thunderbolt0` makes ssh try to expand `%t` as a token and fail
with `unknown key %t`. Write `%%thunderbolt0` in the config file; a bare
command-line `user@fe80::…%thunderbolt0` is fine.

**`rsync` mis-parses bare link-local IPv6 targets** (`Could not resolve
hostname fe80`). Use an SSH alias so rsync sees no colons, or bracket the
address.

**Hugging Face Xet downloads stall on these boxes** — both nodes saw 0–5 MB/s
and then froze with many open connections. `aria2c -x16 -s16` against the
direct CDN `resolve` URL with an `Authorization: Bearer` header worked, and the
token also lifts the unauthenticated rate cap. The current fleet has largely
retired this concern by moving weights into hash-pinned Nix fixed-output
derivations, but the failure mode is still worth recognizing.

**Download where the network is fastest, then copy over the fast local link.**
`rsync -a --append-verify` is the right flag when the destination already holds
a partial copy from the same source: the matching prefix verifies at local-disk
speed and only the tail crosses the wire.

**`pkill -f <pattern>` matches its own command line** and will kill the shell
that launched it. Use `pkill -x <procname>`, or run the kill from a context
whose argv does not contain the pattern.

**Agent sandboxes kill background listeners.** A local `http.server` died with
exit 144 mid-task. Prefer outbound fetches over inbound listeners, or use the
harness's managed background. Foreground `sleep` is likewise blocked — wait
with `until <cond>; do sleep N; done`.

**There is no pure-software way into a box that trusts no key you hold and has
passwords locked.** Someone has to run one command at a physical console, once.
When that moment comes, do not hand-type a 68-character base64 public key — it
will corrupt. Type a short command that *fetches* the key instead. The fleet has
since removed the need for this trick entirely: hosts are provisioned through
nixos-anywhere with `--extra-files` carrying the ssh host key, so a freshly
flashed box is reachable and agenix-decryptable on first boot.

**Rootless podman cannot change host firewall rules** (no `CAP_NET_ADMIN`), and
an SSH local-forward does not help when the application dials a peer's real IP
rather than localhost.

## What replaced it

Nothing distributed. The current architecture is a single coordinator running
llama-swap over hash-pinned local weights, described in
[`README.md`](README.md) and enumerated in [`model-roster.md`](model-roster.md).
Model capacity comes from choosing models that fit 128 GiB at Q8, not from
splitting one model across a fabric.
