# Build Brief — the spec the Stage 3 agents implement

Reconciles the Stage 2 verb deliberation + Stage 2.5 condensation into ONE canonical spec.
Source detail: `STAGE2-per-repo-findings.md`, `STAGE2-verb-deliberation.md`, `STAGE2_5-condensed.md`.
Nothing here is final — it is the starting contract for the build, to be scrutinized in Stage 4.

## What we are building

A single, disciplined **bash** script installed at `~/.local/bin/sandbox`, plus a thin Claude
`SKILL.md` (skill is NOT built in Stage 3). Engine: `podman run --runtime=krun` over official
Fedora packages (`podman` + `crun-krun` + `libkrun` + `libkrunfw`). **No daemon, no state file,
no third-party runtime, no login.** Podman **labels are the single source of truth.**

Threat model: **accident, not adversary** — a coding agent's clumsy code must not damage the host.
We sandbox the **workload** (e.g. a webapp the agent wrote/runs), not the agent harness.
Tailscale-**orthogonal**: the tool knows nothing about the network; it publishes to localhost and
emits parseable output so ssh/Caddy compose around it externally. **No `--host` flag.**

## Canonical verb surface (11 verbs)

Adopted from the Stage 2 synthesis. Each verb's name has provenance in prior art.

| Verb | Signature (abridged) | Role | Tier |
|------|----------------------|------|------|
| `doctor` | `sandbox doctor [--json]` | verb-zero precondition probe; also runs cheaply atop every verb | core |
| `run` | `sandbox run [flags] <image> [-- cmd...]` | **unconditionally ephemeral** one-shot (`--rm` always on, no off switch); foreground; propagates workload exit code | core |
| `keep` | `sandbox keep --name N [flags] <image> [-- cmd...]` | explicit **persistence** verb (omits `--rm`, stamps `sandbox.persist=true`); loud warning | persistent-path |
| `start` | `sandbox start [-it] <name>` | restart a stopped kept sandbox (prevents worktree-orphaning) | persistent-path |
| `exec` | `sandbox exec [flags] <name> -- cmd...` | run a command in a running kept sandbox; **does NOT auto-start** (fails closed → `start`) | persistent-path |
| `logs` | `sandbox logs [-f] [-n N] <name>` | post-mortem stdout/stderr (the only post-mortem for an `--rm`'d crash) | core |
| `ls` | `sandbox ls [-a] [--json]` | list managed sandboxes via `podman ps --filter label=`; machine-readable **by default** | core |
| `inspect` | `sandbox inspect [--json] <name>` | single-object config/status; the `--json` contract ssh/Caddy read | core |
| `stop` | `sandbox stop [-f] [-t S] <name...>` | graceful stop of kept sandboxes; keeps worktree | persistent-path |
| `rm` | `sandbox rm [-f] [--keep-worktree] <name...>` | teardown kept sandbox + its worktree (path+commit guarded) | persistent-path |
| `reap` | `sandbox reap [--until DUR] [--dry-run] [--json]` | label-driven Layer-3 backstop; also reconciles atop every invocation | core |

**Documented dissent (Stage 2.5):** condensation preferred a leaner set with persistence as a
`--keep` *flag* on `run`. Rejected because (a) for an accident model a distinct *word* can't be
fat-fingered the way a flag can, and (b) `start`/`logs`/`inspect` each close a concrete footgun
(worktree-orphaning; no-post-mortem-after-`--rm`; the JSON compose contract). Keep all 11 but
**structure the script so the 5 persistent-path verbs are clearly a secondary cluster** around the
core ephemeral path.

## Cross-cutting flags

`--cpus N`, `--memory MiB` (→ `krun.cpus`/`krun.ram_mib` annotations, **integer-validated in bash**,
conservative defaults ~1 vCPU / 512–1024 MiB), `--network none|loopback` (default `none`),
`--publish HOST:GUEST` (guarded no-op under `--network none`), `--mount HOST:GUEST[:ro]` (extra mounts;
read-only ergonomics), `--env K=V`, `--workdir DIR`, `--ssh-agent` (forward `$SSH_AUTH_SOCK`, keys
never enter guest), `-it`, `--timeout DUR`, `--json`. Flags+env duality (`${VAR:-default}`), flags win.

## Non-negotiable disciplines (the "maximal discipline" checklist)

1. **`set -euo pipefail`** + a `trap` on `ERR EXIT INT TERM` that rolls back partial state. Use the
   **trap-disarm-first idiom** (`trap '' EXIT`) inside cleanup to avoid re-entrant double-cleanup
   (gh-runner-krunvm).
2. **One centralized birth function** every launch funnels through, stamping the **mandatory label set**
   (`sandbox.managed-by`, `.created`, `.id`, `.worktree`) and **safe-by-default isolation flags**.
   There is no second code path that creates a container.
3. **Three-layer teardown**: `--rm` (clean exit) + trap (interactive crash) + `reap` (hard kill / SIGKILL).
4. **Selection EXCLUSIVELY by `--filter label=sandbox.managed-by=<us>`**, never by name substring
   (the explicit footgun in gh-runner-krunvm / claude-code-sandbox / ERA).
5. **Safe-by-default isolation**: `--network none`; mounts read-only **except** the single tool-created
   worktree (`-v ...:Z` rw); `--security-opt no-new-privileges`; conservative `--cap-drop`; SELinux
   **stays on** (reject `label=disable`); conservative clamped `krun.cpus`/`krun.ram_mib`; rlimits as a
   second cap layer.
6. **The tool CREATES the git worktree** (never accept a pre-made one → orphans agent from `.git`).
   Any worktree removal is **path-safety-gated** (`is_safe_cache_path`: inside managed root, not a
   symlink, not repo root, non-empty) **and** **unpushed-commit-guarded** (warn/refuse unless forced).
7. **ssh-agent forwarding**: bind `$SSH_AUTH_SOCK` + set env; keys never cross into the guest.
8. **Isolation flags must reach an enforcing engine arg** and be **assertable by `doctor`** (ERA's
   `--network none` was metadata-only no-op — the headline fail-open we must not repeat).
9. **Machine-readable by default**: `--json`/stable columns derived from `podman ps --format`;
   diagnostics/progress to **stderr**; stdout stays pipeable.
10. **Stable, distinct exit codes**: forward the workload's exit code verbatim; reserve distinct codes
    for precondition-failure (doctor) vs not-found vs launch-failure. Never collapse everything to 255
    (krunvm anti-pattern). Document the scheme.
11. **Self-documenting `usage()`** that greps the script's own option-comment lines → zero help/parser
    drift (gh-runner-krunvm). **Leveled logging** to an fd.
12. **base64 command transport** for arbitrary agent-written code: encode host-side, decode in-guest,
    hand to `bash -c` to dodge shell-quoting bugs (ERA).
13. **Touch ONLY resources we labelled as ours** — never host-global state (the arrakis
    delete-all-`tap*`/`br0`/flush-iptables anti-pattern).

## Explicitly OUT of scope (scope-creep rejected)

Egress-policy DSL / allowlist proxy / TLS-intercept CA / credential proxy / secret-violation detector
(adversary model — sbx, microsandbox); snapshot/restore; volumes/registry/install/login/config verbs;
a second introspection verb; standalone `create`; SEV/TDX (untrusted-host defense we don't need); any
daemon, REST API, SDK, or MCP server (arrakis platform-creep). **Graduation signals** (stop growing
bash, adopt microsandbox / rewrite in Rust): need for concurrency-safe port/worktree allocation
(gh-runner's 30s-sleep mutex), arg-parsing exceeding ~hand-rolled sanity, or loss of single-file
auditability.

## Open questions handed to the build (resolve with a sensible default + a comment)

- Worktree creation/branch contract: exact `git worktree add` semantics, naming derived from branch/path.
- `reap`-on-every-invocation behavior without a lock (no-lock concurrency).
- `--network loopback` / `--publish`-to-localhost semantics under krun's passt.
- The exact libkrunfw ABI/soname acceptance matrix `doctor` should accept.
- `/tmp` writability decision (`--read-only-tmpfs` defaults true in podman).

## Section ownership for Stage 3

- **Agent A** — one-shots the COMPLETE script (the coherent spine + all 11 verbs + interfaces).
- **Agent B (lifecycle)** — birth function + mandatory labels + 3-layer teardown (trap-disarm-first) +
  ephemeral/`keep` split + `reap` + worktree create/`is_safe_cache_path`/unpushed-commit guards.
- **Agent C (isolation & krun)** — centralized safe-flags, krun annotations + integer validation,
  rlimits, ssh-agent forwarding, and `doctor`'s capability probes.
- **Agent D (CLI/UX & dispatch)** — arg parsing + verb dispatch, self-documenting `usage()`,
  `--json`/stable-columns + exit-code scheme + leveled stderr logging + base64 command transport.
- **Integrator** — merges A's spine with B/C/D's expert sections into the final single coherent script.
