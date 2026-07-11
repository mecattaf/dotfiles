---
name: microvm
description: Operating manual for microVMs on NixOS via astro/microvm.nix — the declarative flake toolkit that replaced the Fedora podman+krun `sandbox` tool. Use when creating, running, listing, entering, updating, stopping, and (critically) TEARING DOWN microVMs; when an agent needs a disposable VM to run/test untrusted code; when wiring `microvm.nix` into the flake; or when the user mentions microvm, microVM, `microvm@`, `/var/lib/microvms`, `declaredRunner`, a VM sandbox, or a per-agent VM. Prime directive — microvm.nix KEEPS VMs and ships NO teardown verb; cleanup is manual and it is the reason this skill exists.
when_to_use: agent needs an isolated/disposable VM; "spin up a microVM", "sandbox this build", "run this in a VM"; create/run/list/ssh/stop a microVM; a leaked `/var/lib/microvms/*` dir or dangling gcroot; wiring microvm.nix into the host flake; deciding declarative-service-VM vs ephemeral-sandbox.
---

# microvm.nix — declarative microVMs on NixOS

Upstream: `astro/microvm.nix` (redirects to `microvm-nix/microvm.nix`). Local clone for reading source: `~/Downloads/microvm.nix`. This skill supersedes the Fedora `podman run --runtime=krun` `sandbox` tool (research corpus at `~/mecattaf/dotfiles/skills/microvm/`); the Fedora COPR/krun packaging tax is gone — on Nix the instrument is a flake output, `git clone` = export, `nixos-rebuild` = import.

## Mental model (read first)

- **It is not a daemon.** microvm.nix is a Nix flake that exports `nixosModules` (`nixos-modules/{microvm,host}`). A microVM is a full para-virtualized guest — a **NixOS system built from the store**, running on a type-2 hypervisor. Each managed VM becomes **its own systemd service** `microvm@<name>`. There is no central microvm process.
- **The guest rootfs is content-addressed and pinned by the flake** — byte-identical, no drift, trivial rollback. Sharing the host `/nix/store` read-only over virtiofs means a new sandbox flavour is a new closure, not a new image to build/pull.
- **microvm.nix is persistent-by-design.** It is built to *keep* VMs, not dispose of them. **There is no `remove`, no `-x`, no `reap`.** This is the exact inversion of the old krun `sandbox` tool, whose whole value was ephemeral-by-default disposal. **Teardown is on you** — see [Cleanup](#cleanup--teardown--reap-the-crux). Treat this as the skill's prime directive.
- **Threat model** (carried from the notes): *sandbox the workload, not the agent.* The VM isolates the code-under-test; egress is the thing to gate.

## Live facts (verify before acting)

| Field | Value |
|---|---|
| Upstream flake | `github:microvm-nix/microvm.nix` (was `astro/microvm.nix`) |
| Local source clone | `~/Downloads/microvm.nix` |
| State dir (per VM) | `/var/lib/microvms/<name>/` — holds `current`/`booted`/`toplevel` symlinks, `flake`, auto-created volume `*.img`, sockets |
| GC roots (per VM) | `/nix/var/nix/gcroots/microvm/<name>` and `.../booted-<name>` (deploy path also `.../old-<name>`) |
| systemd unit | `microvm@<name>.service` (+ `microvm-tap-interfaces@`, `microvm-virtiofsd@`, `microvms.target`) |
| Imperative CLI | `microvm` — **only present when the host module is enabled** |
| Host module | `microvm.nixosModules.host`; toggle `microvm.host.enable` (default true); `microvm.stateDir` |
| Hypervisors | `qemu`, `cloud-hypervisor`, `firecracker`, `crosvm`, `kvmtool`, `stratovirt`, `alioth`, `vfkit`(macOS) |
| Clean-shutdown support | qemu / cloud-hypervisor / firecracker = **yes** (control socket). kvmtool / stratovirt / alioth = **NO** (hard kill only) |

**WIRED IN (2026-07-11).** `flake.nix` carries the `microvm` input; the durable host platform (`microvm.host.enable`) is enabled on the **worker** via `modules/microvm-host.nix`. So:

- **Ephemeral default** — `nix run …config.microvm.declaredRunner` works from **any** host (needs only the input; no host module). This is the default and matches the old krun `run` verb's disposability.
- **Durable path** — the `microvm` CLI + `microvm@` units + `microvm.vms` live on the **worker** (the Strix Halo compute box; keeps the coordinator light per the no-heavy-build doctrine). Run/manage long-lived VMs there. Move the `modules/microvm-host.nix` import if the sandbox-execution target changes.

## Path decision — pick before you build

```
Is this a throwaway VM to run/test code, torn down after? (agent sandbox)
  YES → EPHEMERAL: nix run .#…config.microvm.declaredRunner
        (no host module, no state dir; foreground process; writable state only in tmpfs/ephemeral volume)
  NO ↓
Is it a long-lived service you want rebuilt+restarted with the host?
  YES → DECLARATIVE: microvm.vms.<name>.config = { … } in host config; nixos-rebuild switch
  NO ↓
A hand-managed VM you update on its own cadence on a host?
  YES → IMPERATIVE: microvm -c / -Ru on a host with the module enabled
```

In doubt for an agent workload: **ephemeral `declaredRunner`**. It is the closest analogue to the krun tool and needs nothing wired into the host.

## How it's wired (reference)

Already done — the input is in `flake.nix` and the host platform is enabled on the worker (`modules/microvm-host.nix`). Shown here for enabling on another host or declaring a guest.

```nix
# flake.nix (present)
inputs.microvm.url = "github:microvm-nix/microvm.nix";
inputs.microvm.inputs.nixpkgs.follows = "nixpkgs";
```

```nix
# modules/microvm-host.nix (imported by hosts/worker/default.nix)
{ inputs, ... }: {
  imports = [ inputs.microvm.nixosModules.host ];
  microvm.host.enable = true;                 # installs the `microvm` CLI + state dir + tmpfiles; boots no VM
}
```

To add a long-lived declarative guest on the host module (durable path):

```nix
# in the host config
microvm.vms.myvm.config = {
  microvm.hypervisor = "cloud-hypervisor";  # pick one that supports clean shutdown
  microvm.vcpu = 2;
  microvm.mem = 2048;
  # … guest NixOS config …
};
microvm.autostart = [ "myvm" ];             # wire into microvms.target
```

For the **ephemeral default**, no host module is needed — define a throwaway guest that imports `inputs.microvm.nixosModules.microvm` and `nix run` its `config.microvm.declaredRunner` (9p store share + qemu user-net; the bare `nix run` path does no virtiofsd/TAP setup).

`microvm.vms.<name>.config` = **fully declarative** (rebuilt/restarted with the host; cannot be `microvm -u`'d — the CLI refuses, "managed fully declaratively"). For deploy-once-then-update-imperatively, use `microvm.vms.<name> = { flake = self; updateFlake = "git+file:///etc/nixos"; }` instead.

## CLI cheat-sheet (by verb)

The `microvm` command is a getopts wrapper; canonical actions are `-c -u -r -s -l` with flags `-f`/`-R` (verified against `pkgs/microvm-command.nix`).

### Create (imperative)

```bash
microvm -f git+file:///etc/nixos -c <name>   # default flake is git+file:///etc/nixos if -f omitted
# builds .#nixosConfigurations.<name>.config.microvm.declaredRunner,
# stores the flakeref in /var/lib/microvms/<name>/flake, plants gcroots, then:
systemctl start microvm@<name>.service
```

### Run ephemerally as a package (disposable — no host module, no state dir)

```bash
nix run .#nixosConfigurations.<name>.config.microvm.declaredRunner   # foreground console
nix run .#<name>          # if exported as packages.<system>.<name> = …declaredRunner
```

Caveat: the package path does **no** TAP/virtiofsd host setup — rely on 9p shares + qemu user-net. Writable guest state must be tmpfs or an ephemeral volume, else it persists in the cwd/volume.

### List

```bash
microvm -l                                                    # rich; SLOW (evaluates the flake per VM)
ls -1 /var/lib/microvms                                       # fast
ls -l /var/lib/microvms/*/{current,booted}/share/microvm/system   # fast current-vs-booted version view
```

### Enter / console / SSH / logs

```bash
microvm -s <name>                     # SSH over VSOCK (needs microvm.vsock.cid set on the guest)
journalctl -u microvm@<name> -f       # logs
machinectl login <name>               # only if registerWithMachined / useNotifySockets
# console: attach to the foreground process (nix run / microvm -r) or use the guest getty autologin
```

### Update / rebuild

```bash
microvm -u <name>       # rebuild the runner (does NOT refresh packages — that's `nix flake update`)
microvm -Ru <name>      # rebuild AND restart (update needs a restart to take effect)
```

### Stop (graceful)

```bash
systemctl stop microvm@<name>.service   # runs microvm-shutdown (socket-gated), tap-down, machined unregister
```

## Cleanup / teardown / reap (THE crux)

microvm.nix ships **no** teardown verb. `systemctl stop` releases the process, network devices, and machined registration — but **leaves the state dir and the gcroots behind**. Left unmanaged, every `microvm -c` leaks `/var/lib/microvms/<name>` **and** dangling closure-pinning gcroots forever. Run the sequences below explicitly. (This is exactly the disposal discipline the old krun `sandbox` tool automated in 3 layers; upstream automates none of it.)

### Destroy one VM (full teardown — run in order)

```bash
# 0. revoke exposures FIRST (publish-artifact skill): a destroyed origin with a
#    live route is a dangling exposure. Check the coordinator's drop-dir for
#    reverse_proxy blocks targeting this VM's forwarded port:
#      grep -l "worker:<port>" /var/lib/artifacts/*.caddy   # then unpublish
systemctl stop microvm@<name>.service                                  # graceful; hard-kills if no socket
rm -rf /var/lib/microvms/<name>                                        # runner symlinks, flake, auto-created volumes, sockets
rm -f /nix/var/nix/gcroots/microvm/<name> \
      /nix/var/nix/gcroots/microvm/booted-<name> \
      /nix/var/nix/gcroots/microvm/old-<name>                          # unpin the closure (upstream never does this)
nix-collect-garbage                                                    # reclaim the now-unpinned store paths
```

The official "Removing MicroVMs" doc stops after `rm -rf /var/lib/microvms/$NAME` — it does **not** prune the gcroots. Skipping the `rm -f …/gcroots/microvm/*` step silently pins dead closures against `nix store gc`. Always do it.

### Reap orphans (backstop — porting the krun `reap` verb)

```bash
# report state dirs whose systemd unit is dead (candidate leaks):
for d in /var/lib/microvms/*; do
  n=$(basename "$d")
  systemctl is-active -q "microvm@$n" || echo "DEAD VM state present: $d"
done

# prune dangling gcroot symlinks (state dir already gone):
find /nix/var/nix/gcroots/microvm -xtype l -print -delete
```

Treat `/var/lib/microvms/` + `microvm@` unit state as the **single source of truth** (the Nix analogue of the krun tool's "podman labels only" rule) — never track VMs in a side file.

### Shutdown caveat by hypervisor

`systemctl stop` only shuts a guest down *gracefully* if a control socket exists. **qemu / cloud-hypervisor / firecracker** send Ctrl-Alt-Del over their socket (`lib/runners/{qemu,firecracker}.nix`). **kvmtool / stratovirt / alioth have no socket** → systemd just **kills** the process; the guest gets no chance to flush. For any VM holding writable volumes, pick a socket-capable hypervisor.

## Storage / shares / networking (essentials)

- **Volumes** (`lib/volumes.nix`) — block images under the state dir; `autoCreate` runs at every start (`truncate` → `chattr +C` → `mkfs`). **Persistent by default.** For disposable workloads, don't add a volume — keep writable state in tmpfs, or delete the volume after shutdown.
- **Shares** — `9p` (built-in, slower) or `virtiofs` (needs the `microvm-virtiofsd@` service). Share the host `/nix/store` read-only to shrink the guest closure. Writable `/nix/store` overlay needs a *volume* (not a share) and, per upstream, "delete and recreate the overlay after shutdown."
- **Networking** (`nixos-modules/microvm/interfaces.nix`) — `tap`, `macvtap`, `bridge`, or qemu `user`. TAP/macvtap devices are set up by generated `tap-up`/`macvtap-up` scripts and **torn down automatically** on `systemctl stop` via `tap-down` (`ip link delete`). Egress control lives here — for a sandbox, prefer `user`/loopback or no network.
- **Publishing a port out of a VM** (the publish-artifact seam) — qemu `user`-net guests are NOT tailnet-reachable: forward the guest port to `worker:<port>` (qemu hostfwd / the runner's forwardPorts), picking from the designated window **8000–8099** (open on tailscale0 via `myArtifacts.livePortRange`), then hand `worker:<port>` to the publish-artifact skill. A live exposure means the VM must outlive the exposure TTL ⇒ use the durable `microvm -c` path, never a foreground ephemeral VM.

## Gotchas & security posture

- **firecracker has NO virtiofs/9p shares, no device passthrough, no balloon** (`lib/runners/firecracker.nix` throws). If you need host shares, use qemu or cloud-hypervisor.
- **No clean shutdown on kvmtool/stratovirt/alioth** — see the caveat table above.
- **Signature enforcement differs from Fedora.** The old bootc/podman flow signature-enforced image pulls; NixOS default policy is `insecureAcceptAnything`. Any in-guest OCI pulls are unverified unless you configure a policy. Don't assume the Fedora posture carried over (`references/devlogs/1h26/nix-test-rescue/audit/round2-obsolete-refutation.md:127`).
- **Ephemeral ≠ automatic.** microvm.nix has no ephemeral-VM concept; "disposable" means *you* chose the `nix run` path with no persistent volume. Persistence is the default everywhere else.

## Hard rules

1. **Every `microvm -c` incurs a teardown debt.** When done, run the full [Destroy](#destroy-one-vm-full-teardown--run-in-order) sequence — including the gcroot prune. A `rm -rf /var/lib/microvms/<name>` without the gcroot `rm -f` is an incomplete teardown.
2. **For agent/untrusted workloads, default to the ephemeral `declaredRunner` path** — not `microvm -c`. It needs no host wiring and leaves no state dir.
3. **State dir + systemd unit are the only source of truth.** Never invent a side registry of running VMs.
4. **Pick a socket-capable hypervisor** (qemu/cloud-hypervisor/firecracker) for anything with writable state, so `systemctl stop` flushes cleanly.
5. **Gate egress deliberately.** Sandbox the workload; default a sandbox VM to no network or `user`-net + loopback, and gate any public ingress (Caddy/Tailscale) behind access control.
6. **Don't `microvm -u` a `microvm.vms.<name>.config` VM** — it's fully declarative; rebuild the host instead. Use `flake=`/`updateFlake=` VMs for imperative updates.
7. **The `microvm` CLI + `microvm@` units live on the worker** (host module there). Use them from the worker; from the coordinator, target the worker (ssh / microvm.nix's ssh-deploy) rather than enabling the host module on the conductor.

## Reference paths

- **Upstream source (read here):** `~/Downloads/microvm.nix` — CLI `pkgs/microvm-command.nix`; runners `lib/runners/*.nix`; host module `nixos-modules/host/default.nix` + `options.nix`; interfaces/volumes/shares under `nixos-modules/microvm/` and `lib/`; docs `doc/src/{microvm-command,declarative,shares,packages}.md`.
- **Old krun `sandbox` corpus (disposal discipline this skill ports):** `~/mecattaf/dotfiles/skills/microvm/` — `sandbox.sh` (`ephemeral_trap`, `verb_rm`, `reap_core`, `remove_worktree`), `OUVERTURE.md`, `CADDYFILE`.
- **Design lineage (why microvm.nix won):** `notes/references/devlogs/1h26/june18-nix-learnings.md` (the flake-module architecture Tom fell for), `.../june24-openclaw-research.md` (the "Fedora tax dissolved" retrospective), `.../nix-test-rescue/strix-halo-cluster.md` (deepest technical case), `notes/references/archive/july26-fable-first/july6-consolidation/CONSOLIDATION-PROPOSAL.md:264` (the ruling that settled it on architecture alone).
- **Board thread this closes:** `notes/backlog/tasks/task-45 - Check-microvm.nix-claude-skill-exists-or-write-a-simple-one.md`; supersession record `notes/areas/dotfiles-skills-pipeline.md:38`.
