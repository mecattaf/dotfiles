# workerd.nix in this flake

`mecattaf/workerd.nix` is declared here as a flake input. **Nothing is enabled.**
No host imports anything from it, no NixOS module exists to import, no unit is
defined, no package is installed on any machine. A `nixos-rebuild switch` after
this landed changes nothing about any host; the only artefacts are one input,
one `lib` passthrough and one buildable package attribute.

This page says what the input is, which half of the microvm.nix split it
delivers, what is deliberately absent, and the exact commands to try it by hand.

Every factual claim below is graded MEASURED (a command was run and its output
read) or INFERRED (reasoned from something measured). Claims about the workerd
side that were measured by another session are graded REPORTED.

## What workerd.nix is

Independent Nix packaging and checks for Cloudflare's `workerd`, plus an emitter
that renders a declared deployment into a `config.capnp` and a systemd unit
graph.

MEASURED at the pinned revision (`git show <rev>:flake.nix`): its outputs are
`packages.x86_64-linux.{workerd, miniflare, wrangler, chrome-for-testing, bench,
patch-native-binary, workload-mount-runner, default}`, `checks.x86_64-linux.*`,
`devShells.x86_64-linux.workers`, `lib.{emit, mkBench, patchNativeBinary,
declaredRunner}`, `overlays.default`, and `templates."client-repo"`.

MEASURED: it declares **no `nixosModules` attribute at all**. That is deliberate
upstream, and the reason is worth quoting because it is the reason this page
exists. `DECISIONS.md` D-A-15 in that repository declines the durable path
because "a module that nothing imports is dead weight and declaring workerd.nix
across the fleet is a dotfiles decision rather than this repository's". This
page, and the input it documents, are the dotfiles half of that sentence, and
they still declare nothing on any host.

## The ephemeral and durable split, and which half is here

The model is `microvm.nix`, and the split is the thing copied. See the `microvm`
input comment at `flake.nix` (the block immediately above the `workerd` input)
and `modules/microvm-host.nix` (MEASURED, 19 lines, of which two are
functional).

| path | what it costs a consumer | microvm.nix | workerd.nix, here |
|---|---|---|---|
| **EPHEMERAL** | one flake input and one `nix run`. No host module, no switch, works on any capable machine. | `nix run <guest>.config.microvm.declaredRunner` | **delivered**: `nix run .#workerd-workload-mount-runner`, plus `lib.workerd` |
| **DURABLE** | an opt-in host module, imported by one machine, enabled by a gate | `modules/microvm-host.nix`, imported by `hosts/coordinator/default.nix` only | **not delivered, and not sketched** |

**Only the ephemeral half lands here.** INFERRED from the two rows above: the
ephemeral half is the one that travels, so it is the one worth paying a lock
node for, and the durable half costs a module that nothing would import.

## What is wired

Three things, and only three.

1. **The input**, in the `inputs` region of `flake.nix`, immediately after
   `microvm`. Pinned **by revision**, not by branch, with `inputs.nixpkgs.follows
   = "nixpkgs"`. The input's own comment carries the pin's rationale and the
   one-line test for moving it: when the workerd.nix pull requests merge, repin
   to `main`.

   MEASURED: the revision pinned is the head of the **unmerged** branch
   `w/declared-runner-impl`, pull request `mecattaf/workerd.nix#61`. It is pinned
   by rev because a branch name in a lock is a moving target that a deleted
   branch turns into a broken lock, and because that is the house precedent twice
   over (`nixpkgs-paperless` is one frozen rev; `tally-b`, `tally-lake` and
   `herdr` are all pinned to a rev and bumped by editing `flake.nix`).

   MEASURED: the URL is the `git+https://...?rev=` form rather than the
   `github:` shorthand, because the repository is private and the `github:`
   shorthand resolves through the codeload tarball API, which answers HTTP 404
   unauthenticated. `tally-b` and `tally-lake` already use the same form for the
   same reason. No token is in `flake.nix` and none is in `flake.lock`.

   MEASURED: adding it added **exactly one node** to `flake.lock` (plus the root
   `inputs` wiring line and the `follows`). No existing `locked` block moved, and
   no `nix flake update` was run on any existing input.

2. **`lib.workerd`**, a passthrough of the input's own `lib`, published beside
   `lib.rollingInputOverrides`. A consumer on this fleet can reach
   `lib.workerd.emit` without adding the input to their own flake.

   MEASURED: `nix eval --raw .#lib.workerd --apply 'x: builtins.concatStringsSep
   " " (builtins.attrNames x)'` prints `declaredRunner emit mkBench
   patchNativeBinary`, rc 0. `lib.workerd.emit` in turn carries `deploymentType
   inspect mkOciImage render validate`.

3. **`packages.x86_64-linux.workerd-workload-mount-runner`**, one named
   attribute in `packages.${system}`, pointing at the input's real runner.

   MEASURED: it is the **real** runner of `#61`, not the fail-fast stub of `#52`
   (whose derivation is named `deployment-runner-not-yet-delivered` and whose
   build fails by design). It is built from workerd.nix's own pure example
   declaration at `conformance/golden/pass/workload-mount/input.json`, so it
   needs no artefact from any other repository.

   MEASURED: `nix build --no-link --print-out-paths
   .#workerd-workload-mount-runner` exits 0 and produces a single binary,
   `bin/workload-mount-runner`.

   REPORTED, from that file's own header: the runner `exec`s `workerd serve`
   from a `config.capnp` baked into the store, so it runs in the **foreground**,
   SIGINT and SIGTERM reach workerd, the exit status is workerd's, and **no host
   is activated** — no unit, no activation script, no `/var/lib` path. Teardown
   is the whole of `kill <pid>`.

## What the seam is

R41 asked whether the CRM Worker can run under a configuration workerd.nix
emits. REPORTED, from
`/home/tom/overnight-tuesday/receipts/workerd-crm-local-seam/RECEIPT.md`, which
measured it on the worker:

- The CRM Worker **does** run under `workerd serve` from the emitted
  configuration, listening on `127.0.0.1:8080`.
- `GET /health` returns **200** with `{"status":"ok","service":"mecattaf-crm"}`.
- The owner gate closes: `GET /v1/status` without `X-CRM-Owner` returns **403**.
- **Every route touching the `DB` binding returns 500.** The pinned Cap'n Proto
  schema has no `d1Database` arm, so D1 is reached as a `service` binding onto an
  `ExternalServer`, which presents to the Worker as a JS-RPC stub; `env.DB.prepare(sql)`
  then yields an `RpcPromise` the Worker cannot serialize.

So the seam reached a **served** request and not a **D1-backed** one. The open
half is `mecattaf/workerd.nix#56`. Nothing on this page closes it, and the input
landing here does not change it either way.

## What is deliberately NOT here

- **No `modules/workerd-host.nix`.** No module file of any kind was added.
- **No host `default.nix` edit.** No `imports` list gained an entry.
- **No `environment.systemPackages` entry and no `home.packages` entry.** Nothing
  is installed on any machine. The package attribute is a `nix build` / `nix run`
  escape hatch only, the same way `stable-diffusion-cpp-rocm` and `live-iso` are.
- **No `checks` entry.** MEASURED: the `checks` output IS reached by
  `nix flake check --no-build` on this repository, so an added check would really
  be evaluated; nothing here needs one, and adding one would only create a way
  for an unmerged upstream branch to turn this repository red.
- **No secret, no unit, no gate, no switch.** Nothing was minted and nothing was
  activated.
- **Nothing about `#458`.** `nix flake check --no-build` is red on `main` at
  `checks.x86_64-linux.nas-topology`, on the assertion that port 8731 is absent
  from the coordinator's `wlp192s0` while the coordinator opens it. MEASURED both
  before and after this change in the same clone: same rc, same derivation, same
  24 evaluated checks. That red predates this work and is untouched by it.

## The durable path, if Tom ever wants it

Proposed, **not delivered**:

- `modules/workerd-host.nix`, in the shape of `modules/microvm-host.nix`: a
  banner comment explaining the split, and a short functional body.
- Option namespace `myWorkerd`, via `lib.mkEnableOption`, landing with the
  **gate OFF**, which is the house convention for a gated module.
- Imported by `hosts/coordinator/default.nix` only, the way
  `../../modules/microvm-host.nix` is, because the coordinator is the durable
  execution and artifact front door.
- A `checks.x86_64-linux.workerd-topology` asserting the rendered shape, in the
  house `assert`-chain style.

INFERRED: none of that is worth writing until something actually wants a
long-lived workerd on a host. D-A-15 declines it upstream for exactly that
reason, and a module nothing imports is the dead weight it names.

## Trying it by hand

From a checkout of this repository. None of these change any host.

```
# What the input publishes.
nix eval .#lib.workerd --apply builtins.attrNames
nix eval .#lib.workerd.emit --apply builtins.attrNames

# The runner attribute exists in this flake's package set.
nix eval .#packages.x86_64-linux --apply builtins.attrNames

# Build it. Produces bin/workload-mount-runner and installs nothing.
nix build --no-link --print-out-paths .#workerd-workload-mount-runner

# Run it in the foreground. It execs `workerd serve` on a config.capnp baked
# into the store, activates no host, and stops on Ctrl-C.
nix run .#workerd-workload-mount-runner

# Render a declaration to its artefacts without running anything.
nix eval --impure --expr '
  let f = builtins.getFlake (toString ./.);
  in builtins.attrNames (f.lib.workerd.emit.render (builtins.fromJSON (builtins.readFile ./your-deployment.json)))
'
```

To reach workerd.nix's other packages (`workerd`, `wrangler`, `miniflare`) the
input is there but no dotfiles attribute aliases them; use
`nix build .#packages` on the input's own flake, or add an alias here if a second
one is ever wanted.

## Unknowns and proposed defaults

- **Whether pinning an unmerged branch's revision belongs in the lock.** It is
  the only way the runner is reachable at all today: `main` has no runner, and
  `w/declared-runner-design` has only a stub whose build fails by design.
  Default: keep the rev pin, and repin to `main` the moment the workerd.nix
  stack merges. If that is unwelcome, dropping to `main` is a one-line change to
  the input URL and the deletion of the package attribute.
- **Whether `follows = "nixpkgs"` is right.** Default: yes, matching `microvm`,
  so the fleet does not carry a second nixpkgs closure for one input. The named
  risk is real: workerd.nix fetches and patches native prebuilt binaries
  (`lib.patchNativeBinary`), so our pin rather than its own `nixos-unstable`
  decides what they are patched against. MEASURED that it does not break today —
  the runner builds, rc 0, under the followed nixpkgs. That is one measurement at
  one pin, not a guarantee across future bumps.
- **Whether `docs/workerd.md` is the right path.** The repository keeps
  per-topic pages under `docs/`. Default: a single page here; a reviewer may move
  it.
- **Whether a second package alias (`workerd` itself) should be exposed.**
  Default: no. Nothing on this fleet consumes it yet, and an unused alias is the
  dead weight D-A-15 warns about.
