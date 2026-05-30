# Harness Image — Package Audit & krun-stack Gap

Your OS is the mkosi-built bootc/ostree image at `~/mecattaf/harness` (Fedora 44),
running as `ostree-unverified-registry:ghcr.io/mecattaf/harness:latest`. Adding packages =
edit the harness repo + rebuild image + reboot (immutable). Full agent report in the Stage-4
transcript; the actionable summary:

## The gap

`crun` (1.27, **+LIBKRUN**) and `podman` (5.8.1) are installed, but **`crun-krun`, `libkrun`,
`libkrunfw` are NOT** — declared nowhere in the repo (not even commented). So crun has the
*capability* compiled in but can't `dlopen` libkrun because the library is absent.

## The fix — exact edit

Dependency chain (verified via `dnf repoquery`, all stock Fedora 44 repos already enabled):
`crun-krun` → requires `libkrun` (same crun version) → requires `libkrunfw`. **Installing
`crun-krun` alone pulls the whole chain.** No new repos, no conflicts.

In **`mkosi.profiles/fedora-bootc-ostree/mkosi.conf.d/others.conf`** (the file that owns the
container runtime — `crun` is at line 21), in the `[Content] Packages=` list, change:

```
    crun
    cryptsetup
```
to:
```
    crun
    crun-krun
    libkrun
    libkrunfw
    cryptsetup
```
(Just `crun-krun` would suffice; listing all three is self-documenting.) Then rebuild + reboot.

## Optional adds (to `mkosi.conf.d/harness-devtools.conf`, next to the podman tooling)

- `buildah` — if the sandbox tool ever builds images (it currently only runs OCI images).
- `shellcheck` — to lint the project's bash (the tool itself, postinst/prepare chroots, Justfile).

## Already present (no action) — relevant to the sandbox tool

`passt`/`pasta` (the `pasta` binary ships in `passt`; pulled by podman) · `aardvark-dns` ·
`netavark` · `jq` · `coreutils` (`timeout`) · `openssh-clients` (ssh-agent) · `git-core`/`git-lfs` ·
`distrobox` · `toolbox` · `ramalama` · `podman-compose`/`podman-tui`/`podmansh`.

`virtiofsd` is **not** needed — libkrun has its own virtio-fs implementation for `--runtime=krun`.

## No-reboot path for testing NOW

Use distrobox (see `OUVERTURE.md` / the testbed verdict) — `dnf install crun-krun libkrun
libkrunfw` *inside* a distrobox container needs no host reboot.
