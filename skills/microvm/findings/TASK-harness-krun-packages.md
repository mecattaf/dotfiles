# TASK — Add the krun stack to the harness bootc image

**Target repo:** `~/mecattaf/harness` (the mkosi-built Fedora 44 bootc/ostree image,
shipped as `ostree-unverified-registry:ghcr.io/mecattaf/harness:latest`).
**Status:** To Do — blocks all real-world testing of `skills/microvm/` (the `sandbox` tool).
**Constraint:** the test device boots harness **fresh** → this is a **one-shot** package
request. After the image is built we cannot add packages without `rpm-ostree install` + a
second reboot, so everything the tool + its edge tests need must land in this single edit.

## Why

`sandbox` runs on `podman run --runtime=krun`. The host already has `crun` (1.27, **+LIBKRUN**)
and `podman` (5.8.1), but **`crun-krun`, `libkrun`, `libkrunfw` are declared nowhere** in the
repo. crun has the krun capability compiled in but cannot `dlopen` libkrun because the library
is absent → `--runtime=krun` fails. This is the single gap between the current image and a
working microVM host.

**Vanilla Fedora — NO COPR.** All three are stock Fedora 44 packages in repos already enabled
(verified by `dnf repoquery`; also `dnf install`'d cleanly inside a plain distrobox during the
testbed pass). `harness-copr.conf` is untouched. The COPR-only sister projects (krunvm,
microsandbox, smolvm) are exactly what this engine choice avoids.

## The required edit (the gap)

File: **`mkosi.profiles/fedora-bootc-ostree/mkosi.conf.d/others.conf`**, in the
`[Content] Packages=` list (where `crun` is, line 21). Add three lines:

```
    crun
    crun-krun
    libkrun
    libkrunfw
    cryptsetup
```

`crun-krun` alone pulls `libkrun` → `libkrunfw`; listing all three is self-documenting.
No new repos, no conflicts (dependency chain verified, all same-version-pinned).

## One-shot insurance adds (recommended, low cost)

Because we get one shot, lock these now rather than risk a second reboot cycle:

- **`passt`** — in `others.conf` alongside the krun stack. The `pasta` binary (loopback /
  `--publish` networking, blocker #3 of the script) ships here. It is almost certainly already
  pulled transitively by podman, but listing it explicitly removes all doubt for the feature
  the network test depends on. Near-zero cost.
- **`shellcheck`** — in `mkosi.conf.d/harness-devtools.conf` (next to the podman tooling). The
  immediate next work stage fixes the bash and **re-runs shellcheck**; without it on the device
  the script can't be linted in place. High value, small.

## Decide before building (default: skip)

- **`buildah`** — NOT needed: the tool only *runs* OCI images, never builds them (explicit
  non-goal in `BUILD-BRIEF.md`). Add only if you want headroom to prep custom images on-device
  without another reboot. Default: skip.
- **`fuse-overlayfs`** — NOT needed on the host. It is only for the rootful-distrobox **Path B**
  testbed (no-reboot nesting), which the fresh-boot device makes irrelevant — fresh boot **is**
  Path A (native host, zero nesting). Skip.

## Not required (already present or N/A)

`openssh-clients` (ssh-agent, `rhel-edge.conf:44`) · `coreutils`/`timeout`
(`rhel-edge.conf:23`) · `jq`, `git-core`, `socat`, `policycoreutils` (`others.conf`) ·
`aardvark-dns`/`netavark` (podman bridge DNS — krun uses userspace TSI, not needed but pulled
by podman anyway) · `virtiofsd` (libkrun has its own virtio-fs for `--runtime=krun`) ·
SELinux policy module (`/dev/kvm` is 0666 world-RW on this host → no group-gating; krun's
default TSI networking needs no `/dev/vhost-*`).

## Acceptance / done

After the image is built and the device boots fresh, on the host (no distrobox, no nesting):

```bash
# 1. krun stack resolves and a real microVM boots (guest kernel != host kernel):
podman run --rm --runtime=krun --network=none docker.io/library/alpine uname -r

# 2. (once the script blockers are fixed) doctor goes green:
sandbox doctor
```

Done when #1 prints a kernel string different from the host's `uname -r` (proves a real
microVM, not a container). #2 is gated on the separate script-fix work, not on this task.

## Hand-off note

This task is **independent of the script blockers** in `OUVERTURE.md` / `STAGE4-scrutiny.md` —
the package edit can be locked and built now; the fresh-boot device then tests the *fixed*
script against a correct host. The four script blockers (gen_id SIGPIPE, krun annotation
prefix, `krun.use_passt`, doctor probes) are fixed in the `sandbox.draft.sh` work, not here.
