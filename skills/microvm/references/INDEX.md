# References Index

Local clones of every repo that informs the **microvm sandbox** project: a single-user,
Fedora-canon, disposable-microVM code-execution tool driven by a Claude Code skill.
`.git` directories were stripped after a `--depth 1` clone so these trees are read-only
insight, not submodules. **Do not edit anything under `references/` — it is reference material.**

Two tiers:

- **`documentation/`** — the Fedora-canon building blocks we *actually sit on*. The engine
  is `podman run --runtime=krun`; everything here is (or underpins) an official Fedora package.
- **`inspiration/`** — sister / similar projects. We borrow their *verb surface, lifecycle
  discipline, and gotchas*; we do **not** adopt their code or runtimes.
- **`lists/`** — curated landscape lists, skim for anything missed.

The architecture decisions these informed are recorded in `../may30-latest-thread.md`.

---

## documentation/ — what we build on (Fedora-official stack)

The layering, bottom to top: **libkrunfw** (guest kernel) ← **libkrun** (VMM-as-library) ←
**crun** (`--runtime=krun` handler) ← **podman** ← Quadlet.

| Repo | Lang | Layer | Why it matters here |
|------|------|-------|---------------------|
| `libkrunfw` | C/Make | 0 — guest kernel | The Linux kernel bundled as a `.so`. Read to understand what the microVM boots and the SEV/TDX variants. Official Fedora pkg. |
| `libkrun` | Rust/C | 1 — VMM library | The VMM-as-a-library: virtio devices, **TSI networking**, **virtio-fs host passthrough** (the security soft-spot). `docs/`, `examples/`, `include/` are the surface. Official Fedora pkg. |
| `crun` | C | 2 — OCI runtime + krun handler | **The most important doc repo.** `krun.1.md` / `krun.1` define the krun handler and the **annotation surface** (`krun.cpus`, `krun.ram_mib`, `run.oci.handler=krun`, `.krun_vm.json`). Fedora ships crun built `+LIBKRUN`; `crun-krun` wires up `--runtime=krun`. The 2026 rootfs-escape CVE was fixed here (≥1.20). |
| `krunvm` | Rust | 2 — standalone CLI | Alternative front door: a CLI that makes microVMs from OCI images via libkrun+buildah. **COPR-only on Fedora, not official** — we do *not* use it, but its `src/commands/` is the clearest small reference for the create/start/exec/delete verb shape. |
| `crun-vm` | Rust | 2 — sibling runtime | A *different* runtime (`run.oci.handler=krun-vm`) that boots full VM images (QEMU), not the krun microVM path. Included for contrast — shows where the krun path ends and full-VM begins. |
| `podman` | Go | 3 — orchestrator | The official, Quadlet-native orchestrator we drive. Huge repo — read `docs/source/markdown/podman-run.1.md`, the Quadlet docs, and `--runtime`/`--annotation`/`--rm`/label/`ps --filter` surfaces only. This is the actual CLI our script wraps. |

## inspiration/ — sister projects (borrow verbs + discipline, not code)

| Repo | Lang | Tier | Fedora-fit | What to steal / learn |
|------|------|------|-----------|------------------------|
| `microsandbox` | Rust | libkrun microVM, SDK+daemon | COPR-only | The cautionary "this is a full SDK" example + the **explicit escape hatch** if we outgrow bash. Has `skills/` (Agent Skills), `sdk/`, daemon/MCP. Verb surface: `msb exe/init/add/up/down/run/shell/status/log/clean/install`. |
| `smolvm` | Rust | libkrun microVM (FORKED) | **2/10** — vendors its own `libkrun/`+`libkrunfw/` (divergent VMM, like Docker's libsailor) | Verb surface `machine create/start/exec/stop/delete`, `cp`, `run`. **SSH-agent forwarding without keys in guest** — the one feature we lift. Do NOT adopt the forked stack. |
| `agent-sandbox` (ags) | Rust | podman *container* (not microVM) | 6/10 | Independently arrived at our verb shape: **`doctor` (verb zero)**, `update`. `dcg` policy dep. Worktree-prune gotcha. `CLAUDE.md` + `docs/` worth reading. Container-tier = weaker isolation than us. |
| `ERA` | Make/shell | krunvm microVM (+Cloudflare) | krunvm/COPR | Closest prior art to our idea (superseded by smolvm, same author). `skill-layer/`, `recipes/`, setup checks. Buildah hard-dep + Cloudflare layer we improve on. |
| `arrakis` | Go | cloud-hypervisor microVM, REST+SDK+MCP | n/a | **The platform-creep cautionary tale**: 3 daemons (restserver/client/cmdserver), snapshot-restore, py-arrakis SDK, MCP. Exactly what our script must NOT become. |
| `gh-runner-krunvm` | Bash | krunvm microVM | krunvm/COPR | **Most directly relevant for bash discipline**: real-world bash orchestration of krunvm microVMs (`orchestrator.sh`, `runner.sh`, `lib/`). Fedora base Dockerfile. Read for trap/cleanup/labelling patterns in shell. |
| `claude-code-sandbox` | TS/Node | Docker container | n/a | Sandboxes the *agent* in Docker. Config schema (`claude-sandbox.config.example.json`), lifecycle. Different layer (container, agent-not-workload) but useful UX patterns. |
| `sbx-releases` | (docs only) | Docker microVM (libsailor), closed | RHEL8 rpm only | Release-only repo, **no source**. Read README/FAQ for the **egress policy model** (open/balanced/locked-down) we may emulate at the firewalld tier. Mandatory Docker login = rejected. |

## lists/ — landscape

| Repo | What it is |
|------|------------|
| `awesome-agent-sandboxes` (dloss) | Curated list of agent-sandbox tooling. Skim README for anything not yet evaluated. |
| `wincent-gist` | `agent-sandboxen.md` — practitioner notes on the sandbox landscape. |

---

## How these feed the build

1. **Verb surface** is taken *explicitly* from the inspiration tier — primarily `microsandbox`,
   `smolvm`, `krunvm`, and `ags` (which converge on create/run/exec/stop/delete/list + `doctor`).
2. **Isolation flags & annotations** come from `crun/krun.1.md` + `podman` docs (the documentation tier).
3. **Bash lifecycle discipline** (traps, labelling, reaping, ephemeral-by-default) is informed by
   `gh-runner-krunvm` (real shell prior art) and the anti-pattern warning from `arrakis`.
4. **SSH-agent forwarding** idea comes from `smolvm`.
5. **`doctor` precondition check** is confirmed convention across `ags` + `ERA`.
