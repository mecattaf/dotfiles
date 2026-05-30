# Testbed Verdict — running podman + krun without rebooting the host

Empirically tested on this machine (Fedora 44, `ghcr.io/mecattaf/harness`), 2026-05-30.
Plus a cited research pass. Bottom line: the krun stack itself is fine no-reboot; the obstacle
is podman-in-podman nesting, which a **plain rootless distrobox cannot do**.

## Host facts (confirmed)

- `/dev/kvm` exists, mode **`crw-rw-rw-` (0666)** — world-RW, so access is never group-gated
  (neutralizes the #1 documented krun/rootless failure: crun#1894, podman#16701).
- `kvm_intel` + `kvm` modules loaded; bare-metal (not a VM) → this is **NOT nested virtualization**;
  leave `krun.nested_virt` OFF.
- Installed: `podman 5.8.1`, `crun 1.27` **`+LIBKRUN`**. Missing: `crun-krun`, `libkrun`, `libkrunfw`.
- Host sudo is **NOT passwordless** (`sudo -n` fails).

## Proven inside a plain `distrobox` (fedora:44)

- `/dev/kvm` is present inside the box at **0666** (owned `nobody:nobody` via userns map, still usable).
- `dnf install crun-krun libkrun libkrunfw` **succeeds with NO reboot** →
  `crun-krun-1.27.1`, `libkrun-1.18.0`, `libkrunfw-5.3.0`, `crun +LIBKRUN`, `/usr/bin/krun -> crun`.

## Proven FAILURE: nested podman+krun in a *rootless* distrobox

Running the inner `podman --runtime=krun run` inside a plain `distrobox enter` fails through the
entire documented rootless-in-rootless cascade (each fix exposes the next layer):

1. rootless inner podman → `cannot re-exec process to join the existing user namespace`.
2. `sudo` podman (rootful-in-box) → `'overlay' is not supported over overlayfs, a mount_program is required`.
3. force vfs / fuse-overlayfs → `failed to open 2048 locks in /libpod_lock: permission denied`, and
   `/dev/shm/libpod_lock` is owned by an unmappable `nobody` — even `sudo rm` gets
   `Operation not permitted`. Dead end for the rootless box.

This is exactly what distrobox docs and the research warned (rootless-in-rootless storage/userns/IPC
collisions). It is a **podman-nesting** limit, NOT a krun/KVM limit.

## The two paths that DO work

### Path A — host install + ONE reboot (production path, cleanest)
Add the three packages to the harness image (see `HARNESS-packages.md`) and rebuild+reboot, or for a
quick local trial `rpm-ostree install crun-krun` + reboot. Then native host podman runs krun with zero
nesting. This is the real deployment target; recommended for serious testing.
Smoke test after reboot:
```bash
podman run --rm --runtime=krun --network=none docker.io/library/alpine uname -r   # kernel != host kernel ⇒ real microVM
```

### Path B — rootful `--root` distrobox (no reboot; YOU must create it — needs sudo password)
The research-documented recipe gives the inner podman a proper rootful userns (+full IPC), sidestepping
all three failures. `--unshare-all` strips host devices, so `/dev/kvm` is re-added explicitly:
```bash
distrobox create --root --name krun --image registry.fedoraproject.org/fedora:44 \
  --unshare-all --volume /dev/kvm:/dev/kvm:rw \
  --additional-packages "podman crun-krun libkrun libkrunfw fuse-overlayfs"
distrobox enter --root krun
# inside, if overlay-on-overlay bites, init a clean vfs store once:
#   printf '[storage]\ndriver = "vfs"\n' | sudo tee /etc/containers/storage.conf
podman --runtime=krun run --rm --network=none docker.io/library/alpine uname -r
```
NOT verified end-to-end here because `distrobox --root` needs the interactive host sudo password.
Treat the boot step as "expected to work per docs+precedent", to be confirmed on first use.

## Precedent that krun-in-container works given /dev/kvm
Red Hat RamaLama runs models in libkrun microVMs via `podman --runtime=krun` in rootless containers;
krun default networking is userspace TSI (no `/dev/vhost-*` needed). Sources in the Stage-4 research
transcript (developers.redhat.com RamaLama+libkrun; crun#1894; podman#16701/#24609/#25365; libkrun README).
