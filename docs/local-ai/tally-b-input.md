# The `tally-b` input and `modules/tally-b.nix`: what the rewrite kernel runs against

Written for U-D13 (`mecattaf/dotfiles#316`). It records what the input pins and
why the URL looks the way it does, what the one module declares, and which
questions the kernel's own repo left for this file to answer.

## What the input is

`tally-b` is `github.com/mecattaf/tally` — the REWRITE kernel's cargo workspace
(U-B1…U-B13: admission, leases, the witness chain, the typed socket). It is not
the `tally` input above it in `flake.nix`: that one is `mecattaf/tally.nix`, the
public packaging flake of the LIVE daemon, consumed through
`homeManagerModules.tally` by `home/tally.nix`. The repo names are confusingly
alike and the flake.nix comment on `tally` says so itself — "NOT mecattaf/tally,
which is the pre-rebuild spec history" — which is exactly the repo `tally-b`
pins: the spec history that grew the rewrite inside it.

```nix
tally-b = {
  url = "git+https://github.com/mecattaf/tally?rev=26d758049bf0e89126157b3ea743085bb1b918f0";
  flake = false;
};
```

**`flake = false`** because the repo ships no flake of its own and never will:
its CONTRIBUTING §1 rule 2 is "This repository carries no Nix at all", and its
DEFERRED.md names `modules/tally-b.nix` in THIS repository as the unit's home
("[SCOPE] The systemd unit … is U-D11 (`modules/tally-b.nix` in
`mecattaf/dotfiles`)"). The input is a plain source tree, consumed the way
`sfmono-liga` is; the packaging is ours.

**`git+https://`, not `github:`** because the repo is PRIVATE
(`gh repo view mecattaf/tally --json isPrivate,visibility` →
`{"isPrivate":true,"visibility":"PRIVATE"}`, MEASURED 2026-09-06) and this unit
flips no visibility — no executor does; contrast U-D15, where a Tom line
(R-2026-09-06-22) had already cleared the flip before the `github:` form was
taken. The native `github:` fetcher was MEASURED against that wall: it
downloads the codeload tarball with nix's own `access-tokens`, of which this
fleet configures none, and answers `HTTP error 404` on the private repo. The
`git+https://` form fetches through git, and git on this box authenticates
through the machine's own persistent credential path (the `gh auth
git-credential` helper in the global gitconfig) — no token in `flake.nix`, none
in `flake.lock`, none needed in the environment at eval time, and none read or
printed to establish any of this. The consequence is stated plainly in
`DECISIONS.md`: the ONE network act (the lock update / a cold fetch) works only
on a host whose git can authenticate to github.com. After that act the git
cache and the store path make every gate `--offline`-clean anywhere.

**The rev** `26d7580` is `origin/main` of mecattaf/tally at the pin: the merged
head past U-B13 (PR #45, `k/socket`) plus the evaluator's own probe commit. It
is the commit U-B13's deliverable sits on, and the card's oracle requires
exactly that — "the input pinned to a pushed commit of mecattaf/tally".
`tests/tally-b/test-tally-b-input.sh` clause D checks the pin is an ancestor of
the clone's `origin/main` without touching the network. Bump by editing the rev
in `flake.nix` and running `nix flake lock --update-input tally-b`,
deliberately, the way `nixpkgs-paperless` is bumped — the lock update at the
pin must be a NO-OP, and clause A0 asserts it.

## What the module declares

`modules/tally-b.nix`, imported by `hosts/coordinator/default.nix` alone:

- **The package.** `rustPlatform.buildRustPackage` over the input's source,
  `cargoBuildFlags = [ "-p" "tally-socket" ]` — the workspace member whose
  `[[bin]]` IS `tally-kernel` (`serve | call | chain | guard`; the library
  package of that name is the kernel it serves, tally-socket's own Cargo.toml
  says why). The workspace is std-only: its `Cargo.lock` carries path members
  and not one external crate, so `cargoLock.lockFile` needs no `cargoHash`, no
  vendoring, no network. MEASURED: the built output carries exactly one bin,
  and `serve` over a temp state dir answers `rows.read` with a `row_state`
  reply (the same smoke `tools/socket-smoke.sh` runs, one level down).
- **`tally-kernel.service`** on the SYSTEM bus, `User = tom`:
  `tally-kernel serve --state /home/tom/.local/state/tally-rewrite --rows
  <rendered rows> --socket /home/tom/.local/state/tally-rewrite/kernel.sock`.
  Every path is the kernel's own default made explicit (`default_state_dir`,
  `default_socket_path` = SOCKET_BASENAME beside the chain it fronts), so the
  unit says what it runs against instead of inheriting it from `$HOME`.
- **The rows.** `services.tally-kernel.rows` renders to the `--rows` JSON and
  defaults to exactly the three `owner: kernel` rows of the rewrite's own
  `docs/rows.md` — `gpu-coordinator`, `gpu-worker`, `mechanical` — with that
  table's cells: capacity 1, `window: none` (a device is contended, never
  spent), `context_window` 32768 on the GPU rows and null on `mechanical`,
  graces 30/10, `per_attempt_token_cap` 100000 (D-B3/TL-3). The `running`
  source of a GPU row is llama-swap's `/running` endpoint — this box's for
  `gpu-coordinator`, `http://worker:9292/running` (the fleet-name pin of
  `modules/fleet-hosts.nix`) for `gpu-worker`, because ONE kernel on the
  coordinator serves both devices (spec §2.4 Q2). The seat rows (cc, cc2, cc3,
  codex, pi-qwencloud) are NOT in this file: they are tom-owned observations
  written into the meters dir by U-D12's feeders on the user bus and read
  through it. A failed `/running` probe is written busy with grade UNKNOWN,
  never as false idle (`RunningSource::observe`), so a down endpoint cannot
  fabricate headroom.
- **The meters dir and the state root**, declared as system tmpfiles rules
  (`d … 0700 tom users`), the same motion `home/tally.nix` and
  `home/seat-feeder.nix` use from the user bus: a missing directory should be a
  legible failure, never a silent no-op. They coexist with seat-feeder's
  user-bus rules over the same two paths — `d` lines are idempotent and both
  say 0700 tom.
- **`evaluatorLock`**, default null: without `--evaluator-lock` no verdict is
  ever derived (tally `docs/socket.md` §4), which is the right state until
  U-A17's `apps/evaluator` exists in the lake to be locked.

## Coexistence with the live daemon, as bytes

The live estate is `tally-daemon.service` on tom's USER bus (the `tally`
input's home-manager module, `home/tally.nix`) writing `~/.local/state/tally/`.
The rewrite is `tally-kernel.service` on the SYSTEM bus writing
`~/.local/state/tally-rewrite/`. Different bus, different unit name, different
state root — and the separation is not this module's opinion: the kernel's own
`Ledger::open` refuses branch (a)'s paths BY NAME
(`crates/tally-kernel/src/ledger.rs:31-35`), so a served kernel pointed at the
live root fails to start. `modules/tally-b.nix` asserts the same refusal at
eval time (stateDir must carry the `tally-rewrite` component), the
`tally-b-topology` check in `flake.nix` asserts the whole shape — including
that the live user-bus declaration still evaluates and that no system-bus
`tally-daemon` twin appeared — and clause F of the test script re-reads both
from a bare PATH.

The socket path question the kernel's DEFERRED.md left open ("[OPERATOR] Where
the socket lives on the coordinator once U-D11 runs it under systemd … which
path the estate settles on is an operator's line") is answered here at the
kernel's own default — `kernel.sock` beside the chain — and recorded in
`DECISIONS.md`. It moves by changing `services.tally-kernel.socketPath`, never
by an environment variable on the unit.

## What is deliberately not here

- **No switch.** The unit is DECLARED; only U-D19's coordinator switch installs
  it (`DEFERRED.md` DF-U-D13-1). Until then `systemctl status tally-kernel` on
  the box answers "could not be found", and nothing is hand-started (Rule 9).
- **No uplink, no lake.** The socket speaks newline-delimited JSON over
  AF_UNIX; the uplink that probes rows and POSTs readings is W-03, and the
  `tally-uplink.service` of the spec's U-D11 row is U-D14's (tally-ts-sdk as an
  input). This module runs the kernel and nothing else.
- **No feeder timers.** U-D12 declared them on the user bus
  (`home/seat-feeder.nix`); they are untouched.
- **The live daemon's configuration** — `home/tally.nix`, its pools, producers
  and adapters — is not edited by this unit at all.

## How to re-run the acceptance

```console
$ bash tests/tally-b/test-tally-b-input.sh
```

Clauses: A0 lock-update no-op; A `nix flake check --offline --no-build`; B the
card's eval → `true`; C toplevel `--dry-run`; D the pin (flake.nix ↔ flake.lock
↔ pushed); E the unit's shape (store binary, state root, socket, rows and
their seven cells); F coexistence in both directions. The card's
`mutation_hint` — "remove the service from the module → the eval is false" —
was MEASURED red two ways: with the service block removed the attribute does
not exist and the eval fails non-zero; with `enable = false` it prints `false`.
