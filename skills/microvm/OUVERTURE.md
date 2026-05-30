# OUVERTURE — handoff for the next agent

> **Scope of this document.** Everything in `findings/build/sandbox.draft.sh` is a **first draft**,
> not final. This file hands off the work: what was built, what must be fixed before it can run,
> how to set up a testbed, how to test it to the edges, and which `SKILL.md` variants to write so
> the tool is actually usable by a coding agent. **Executing this plan is the next agent's job, not
> this run's.** The previous run did: clone references, deliberate the verb surface, build the draft,
> and scrutinize it. It deliberately did NOT run sandboxes, fix the bugs, or write the skill.

## 0. Orientation — what exists

| Artifact | What it is |
|----------|------------|
| `findings/build/sandbox.draft.sh` | The merged 1566-line draft. `bash -n` clean, shellcheck-clean. **Has 4 blockers — do not ship as-is.** |
| `findings/BUILD-BRIEF.md` | The canonical spec: 11 verbs, flags, the 13 non-negotiable disciplines, out-of-scope list. |
| `findings/STAGE4-scrutiny.md` | 30 source-verified findings (2 critical, 7 high, 6 medium, 15 low). The fix-list. |
| `findings/STAGE2-verb-deliberation.md` | The 11 verbs with full provenance + signatures. |
| `findings/STAGE2_5-condensed.md` | Cross-reference of the 16 prior-art tools (consensus + per-repo uniqueness). |
| `findings/HARNESS-packages.md` | Exact package edit for the immutable image. |
| `findings/DISTROBOX-testbed.md` | Empirical testbed verdict (both no-reboot and reboot paths). |
| `references/` | 16 cloned repos (read-only), `INDEX.md` classifies them. Ground truth for any "does X really work" question — verify against source, do not guess. |

The engine is **`podman run --runtime=krun`** over official Fedora packages. No daemon, no state file
(podman labels are the only source of truth), accident-not-adversary threat model, sandbox the
**workload** not the agent, Tailscale-orthogonal.

## 1. FIX FIRST — blockers (from `findings/STAGE4-scrutiny.md`)

The draft cannot complete a single `run` until these land. Fix, then re-run shellcheck + `bash -n`.

1. **CRITICAL — `gen_id()` dies (exit 141) under `set -o pipefail`** (`sandbox.draft.sh:246`).
   `tr … | head` gets SIGPIPE. Make it SIGPIPE-immune, e.g.
   `gen_id(){ LC_ALL=C tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 10 || true; }`.
   Every `run`/`keep` is dead until this is fixed.
2. **HIGH — krun annotation keys are wrong** (`:581-582`). Draft emits `run.oci.krun.cpus`/`…ram_mib`;
   crun does an **exact-match** lookup of the literal `krun.cpus`/`krun.ram_mib`
   (`references/documentation/crun/src/libcrun/handlers/krun.c:262,272`; `find_string_map_value`, no
   prefix stripping; `krun.1.md:45`). Result: resource caps **silently no-op** (the ERA fail-open).
   Fix: emit bare `--annotation krun.cpus=…` / `krun.ram_mib=…`. (A verifier claimed podman rewrites
   the prefix — **false**; podman passes annotations verbatim. Confirmed against source.)
3. **HIGH — `--network loopback` never sets `krun.use_passt`** (`:938-949`). Under krun the guest has
   **no NIC** unless `krun.use_passt>0` (`krun.c:324,578`; `krun.1.md:59`). So loopback/`--publish` is a
   metadata-only no-op. Fix: in the loopback branch also emit `--annotation krun.use_passt=1` (bare key),
   then **verify** a published port actually reaches the in-guest listener (krun port-publish under
   passt has TSI caveats) before advertising the feature.
4. **HIGH — `doctor` proves too little** (`:442-450`). The smoke test only confirms a microVM boots; it
   never asserts a cap/flag bound in-guest, which is *why* bugs 2–3 could ship. Add probes that run the
   **same `apply_*` code path** and assert in-guest: `nproc` + `MemTotal` match the clamp (use
   `ram_mib ≥ 512`; ≤128 is silently ignored), and a read-only-rootfs write is rejected.

Also fix before any agent drives it (highs):
- **`--timeout` is a dead flag on `keep`/`exec`** — wire it (`timeout` around `podman exec` for exec;
  reject for detached `keep`, or map to a reap age-cut). Discipline #8.
- **base64 transport loses argv boundaries** (`:283-291`) — `echo a;rm` would run `rm`. Either pass
  words as podman trailing args (no shell) for the common case and reserve base64 for an explicit `-c`
  script, or per-word base64 + positional reconstruct. Fix the misleading "dodges all shell quoting" comment.

The medium/low items (orphaned `sandbox/<id>` branch leak, half-born reap gap, rw-mount `:Z` relabel,
usage/dispatch drift, misleading isolation comments, precheck ordering, exec `--ssh-agent`) are real but
post-blocker — work them after the tool runs. All have locations + fixes in `STAGE4-scrutiny.md`.

## 2. Package prerequisites

Per `findings/HARNESS-packages.md`: the only required adds are **`crun-krun`** (pulls `libkrun` →
`libkrunfw`) — `crun` is already `+LIBKRUN`. Two ways to get them depending on testbed (next section).
Optional dev adds: `buildah` (only if the tool ever builds images), `shellcheck` (to lint this very
script — recommended).

## 3. Testbed — pick one (BOTH documented; see `findings/DISTROBOX-testbed.md` for the evidence)

A plain `distrobox enter` + nested podman **does not work** (proven: rootless-in-rootless userns/storage/
IPC cascade). Use one of:

### Path A — host install + ONE reboot (recommended; the production target)
Add the packages to the harness image (`HARNESS-packages.md`) and rebuild+reboot, **or** for a quick
local trial: `rpm-ostree install crun-krun` then reboot. Then host podman runs krun natively. Verify:
```bash
podman run --rm --runtime=krun --network=none docker.io/library/alpine uname -r   # kernel ≠ host ⇒ real microVM
```

### Path B — rootful `--root` distrobox (no reboot; user runs it, needs sudo password)
```bash
distrobox create --root --name krun --image registry.fedoraproject.org/fedora:44 \
  --unshare-all --volume /dev/kvm:/dev/kvm:rw \
  --additional-packages "podman crun-krun libkrun libkrunfw fuse-overlayfs"
distrobox enter --root krun
# if overlay-on-overlay bites: printf '[storage]\ndriver = "vfs"\n' | sudo tee /etc/containers/storage.conf
```
Then run the same smoke test. (Not verified end-to-end here — needs the interactive sudo password.)
Note: vfs storage is slower and the tool's `:Z`/worktree assumptions should be re-checked under a
rootful-in-box podman.

## 4. Test plan — to the edges

Run `sandbox doctor` first on whichever testbed; it must pass before anything else. Then:

**Per-verb happy path:** `run` (ephemeral, exit code propagates, container gone after), `keep --name`
(survives, labelled `sandbox.persist=true`), `start`/`stop` (kept sandbox cycles, worktree preserved),
`exec` (into a running kept one; **fails closed** on a stopped one), `logs` (post-mortem of an `--rm`'d
crash), `ls`/`inspect` (machine-readable by default, `--json` valid), `rm` (tears down + worktree),
`reap` (sweeps orphans).

**Enforcement assertions (the whole point — these catch the fail-opens):**
- `run --cpus 1 --memory 512 … -- nproc; grep MemTotal /proc/meminfo` → must reflect the clamp
  (regression test for blocker #2). Try `--memory 64` → expect it ignored (≤128 rule), document.
- `run --network none … -- ip addr` (or `wget`) → no external reachability; `--network loopback`
  → published port actually reachable from host (regression for blocker #3).
- read-only rootfs: `run … -- sh -c 'touch /nope'` fails; the worktree mount is the only writable path.
- `--ssh-agent`: `git push` works inside; `env | grep SSH` shows the socket; keys never copied in.

**Lifecycle / orphan edges (the disposability guarantee):**
- Ctrl-C / SIGTERM mid-`run` → trap removes the container + worktree (no orphan). `kill -9` the
  script → `reap` later cleans it. Pull the network mid-run. Fill the disk inside the guest → host fine.
- Concurrent `run`s (parallel worktrees) → no name/port collision; `reap` under concurrency is
  best-effort (documented graduation signal).
- Branch leak: confirm `sandbox/<id>` branches are deleted on teardown (medium finding) — or filed.
- `rm` with unpushed commits in the worktree → refuses without `--force` (and isn't *over*-aggressive
  on a fresh branch-off-HEAD — A flagged `has_unpushed_commits` may false-positive).

**Robustness:** every verb on a non-existent name → distinct not-found exit code (not 255). `doctor`
on a box without the krun stack → actionable message + distinct precondition code. base64 transport
with metacharacters (`-- sh -c 'echo "a; rm -rf /tmp/x"'`) behaves correctly (regression for the argv bug).
Workload exit codes (0, 1, 137, 124-on-timeout) forwarded verbatim.

**Reference cross-check:** for any "should it behave like X" question, read the real source under
`references/` (e.g. krun annotation semantics in `crun/.../krun.c`, passt in `krun.1.md`,
trap/usage idioms in `gh-runner-krunvm/`). Do not trust memory — that's how the annotation bug slipped in.

## 5. SKILL.md variants to write

The skill teaches *judgment* (when/why/recover) and delegates *how* to `sandbox --help` — never restate
flags (they drift). Recommended set:

1. **`SKILL.md` (core)** — "run agent-written/under-test code in a disposable microVM." Teaches: prefer
   `sandbox run <image> -- <cmd>` for one-shots; never run the workload directly on the host; the
   ephemeral-by-default model and disposability ("if it wedges, `rm`/`reap` and recreate"); how to read
   exit codes; the `doctor`-first habit and how to act on its failures; the **don't** list (don't point
   it at a pre-made worktree; guard destructive git inside; don't expect host network by default).
   Points at `sandbox --help` for flags.
2. **A persistent-workflow variant** (or a section) — when to reach for `keep`/`start`/`exec`/`stop`
   (a long-running webapp the agent iterates on) vs `run`; the responsibility that `keep` sandboxes
   survive and must be `stop`/`rm`/`reap`'d.
3. **A "serve my webapp" variant** — the ingress story: `keep` with `--network loopback --publish`,
   then point Caddy at the localhost port (Tailscale composes around it — the tool stays orthogonal).
   Only write this once blocker #3 (passt/publish) is verified to actually work.

Keep each short and judgment-focused. The script's `--help` is the single source of truth for `how`.

## 6. Open questions the build deferred (resolve with a default + a comment)

Worktree branch/checkout contract (which ref, naming); reap-on-every-invocation no-lock concurrency
on worktree removal; exact libkrunfw ABI/soname matrix `doctor` should accept; `/tmp` writability
(`--read-only-tmpfs`); whether `reap`/`stop`/`rm`/`logs` should gate on podman-only (not full krun)
precheck so cleanup works when krun is broken. See the "open questions" + low findings in the stage docs.

## 7. Definition of done (for the next run)
`doctor` green on a chosen testbed; the 4 blockers + 2 highs fixed; the enforcement-assertion tests in
§4 pass (caps + network actually bind); ephemeral/orphan edges clean; `SKILL.md` (at least the core
variant) written; script installed to `~/.local/bin/sandbox` (chezmoi-managed). Medium/low findings
either fixed or filed with rationale.
