# The `tally-lake` input and `home/tally-uplink.nix`: the lake's box-side loop

Written for U-D14 (`mecattaf/dotfiles#317`). It records what the input pins and
why the URL looks the way it does, what the one home-manager module sets, and
which questions the lake's own repository left for this file to answer.

The unit replicates the `tally.nix` input motion exactly (the card's exemplar,
and U-D13's before it): a flake input, then ONE home module that imports the
module the input exports and sets its options for this estate. Nothing the
uplink DOES is written here.

## What the input is

`tally-lake` is `github.com/mecattaf/tally-ts-sdk` — the LAKE (TALLY-SPEC §2.2):
`packages/schema`, `packages/factory`, `apps/worker` (the deployed Durable
Object) and `apps/uplink` (W-03, the box side). It is the THIRD tally-named
input in `flake.nix`, and the three are easy to confuse:

| input | repo | what it is |
|---|---|---|
| `tally` | `mecattaf/tally.nix` | the LIVE daemon's public packaging flake |
| `tally-b` | `mecattaf/tally` | the REWRITE kernel's cargo workspace (U-D13) |
| `tally-lake` | `mecattaf/tally-ts-sdk` | the LAKE that proposes to that kernel |

```nix
tally-lake = {
  url = "git+https://github.com/mecattaf/tally-ts-sdk?rev=897f9015e7c22304c3bfd7ca2ec990b294966ded";
};
```

**Consumed AS A FLAKE — no `flake = false`, unlike `tally-b`.** This repository
does ship a `flake.nix`: W-03 added it (lake commit `c29fdfb`, "packages.uplink
and homeManagerModules.tally-uplink (D-B65)") under an explicit supersession of
that repo's own CONTRIBUTING §2 rule 6, "No Nix in this deliverable" — because
U-D14's card assigns the package derivation and the home-manager module to the
lake and no other unit was chartered to build them. So `home/tally-uplink.nix`
imports `inputs.tally-lake.homeManagerModules.tally-uplink` exactly the way
`home/tally.nix` imports `inputs.tally.homeManagerModules.tally`.

**No `inputs.nixpkgs.follows`,** because there is nothing to follow: the lake's
flake takes NO inputs at all, on purpose (a `nixpkgs` input would be a fetch,
and its lock would pin bytes nobody in that repository chose). It records the
node store path its `scripts/node-env.sh` records and `throw`s before it yields
any output if the two disagree, so our pin drags no second package universe
along and our nixpkgs cannot move its toolchain under it.

**`git+https://`, not `github:`,** for the wall U-D13 established over
`mecattaf/tally` and re-MEASURED here for THIS repo on 2026-09-07: it is PRIVATE
(`gh repo view mecattaf/tally-ts-sdk --json isPrivate,visibility` →
`{"isPrivate":true,"visibility":"PRIVATE"}`) and no executor flips visibility.
`nix flake metadata github:mecattaf/tally-ts-sdk/<rev>` answers `HTTP error
404` (MEASURED on `a233c30` when this input was written, and true of every rev
since), because the tarball fetcher spends nix's own `access-tokens` and this
fleet configures none. The `git+https://` form fetches through git, and git here
authenticates through the machine's own persistent credential path (the `gh auth
git-credential` helper in the global gitconfig — never read, never printed). The
consequence, stated rather than hidden: the ONE network act (the lock update / a
cold fetch) works only on a host whose git can authenticate to github.com; after
it, the git cache and the store path make every gate `--offline`-clean anywhere.

**The rev** is `897f901` — `origin/main` of mecattaf/tally-ts-sdk on 2026-09-10
(MEASURED: `git rev-parse origin/main`; 32 commits ahead of the pin it
replaces, and the whole range is on `main`). The lineage of this line:

| rev | what it bought |
|---|---|
| `a233c30` | W-03's delivery (PR #99 `lake/uplink`, whose `flake.nix` commit `c29fdfb` is an ancestor) plus U-A22's evaluator probe — the first `main` that exports `homeManagerModules.tally-uplink` at all; anything before `c29fdfb` has no flake to import and this input cannot evaluate |
| `38a526ba` | the pin FT-3 replaced |
| `897f901` | **this pin.** `packages/planning/src/objects/factory.ts:617` `level_rank` and the uplink's `level_rank` passthrough (without it a proposal arrives without the level the floor ranks it by); FIX-E04, the uplink SHUTTING THE DOOR on the lake's 5xx instead of retrying into it; FIX-E05; FIX-E10 |

FIX-E04 is the one that matters on this box today: the deployed Worker answers
`500 FactoryError / PersistenceFailed` on the Durable Object's own SQLite read
(`tally-ts-sdk/docs/e2e.md:178-186`), so at the old pin every five-minute wake
was a retry into a red dependency and at this one it is a legible refusal.
**Bumping the pin is not deploying the lake and is not a switch**: this line
moves the bytes the BOX evaluates against, and the deployed Worker (`f95beed`)
already carried the factory fix. The switch that installs the result is Tom's
(dotfiles#322 U-D19), and so is any further bump. Clause D of the test script
checks the pin is an ancestor of the clone's `origin/main` without touching the
network. Bump by editing the rev and running `nix flake lock --update-input
tally-lake`, deliberately, the way `nixpkgs-paperless` is bumped — the lock
update at the pin must be a NO-OP, and clause A0 asserts it. NOT in
`rollingInputOverrides`: the lake proposes work onto this box's rows, so its
version moves when Tom says so, never on a nightly resolve.

## What the module sets

`home/tally-uplink.nix`, imported by `home/home.nix` on every host — the import
is unconditional, only the enablement is gated on `coordinator`:

- **The import.** `inputs.tally-lake.homeManagerModules.tally-uplink`. The
  upstream module declares `systemd.user.services.tally-uplink`, a `Type =
  oneshot` unit with no `Install` section, and everything the uplink does —
  probe every row, POST the reading, pull `/proposals`, admit over the kernel
  socket, POST `/outcomes`, execute under lease, mirror the chain, re-arm the
  plan, replay from `last_seq + 1` — is its code and is not re-implemented here.
- **`rows`** = `${inputs.tally-b}/docs/rows.md`: the PINNED kernel's own rows
  file, out of the store, not the live checkout at `/home/tom/mecattaf/tally`
  that a `git checkout` could move under the unit without a review anywhere.
  The rows the uplink probes and the kernel it probes them against are then ONE
  pin. The option is REQUIRED upstream and has no default, by the lake's own
  ruling that the rows file is a runtime argument (D-B64) whose path that
  repository does not own. MEASURED 2026-09-07 with the lake's own parser at the
  pin (`--parse-only` → rc 0): **nine rows** — `cc`, `cc2`, `cc3`, `codex`,
  `pi-qwencloud`, `cerebras` (owner tom / third-party, the seat rows U-D12's
  feeders write into the meters dir) and `gpu-coordinator`, `gpu-worker`,
  `mechanical` (owner kernel, the three U-D13's module serves). The uplink
  probes all nine; a probe that fails is written busy with grade UNKNOWN, never
  as false idle.
- **`tokenFile`** = `~/.local/state/tally-rewrite/lake-token` — see below.
- **`socket`, `ledger`, `stateDir`** = `kernel.sock`, `ledger.jsonl` and
  `uplink/` under the same root. All three are the upstream defaults, spelled
  absolute rather than left at the module's `%h` form. Same value (this is a
  user unit, so `%h` IS `/home/tom`) and one reason, `modules/tally-b.nix`'s on
  the system side one bus over: the rendered `ExecStart` then SAYS what it runs
  against instead of inheriting it from `$HOME`, so the topology check and the
  test script read the paths without a specifier-expansion step of their own.
- **`executor` = `coordinator`, and the module is enabled there and nowhere
  else.** ONE uplink per box that serves a kernel (spec §2.4 Q2); the worker
  twin is a ROW that kernel serves, not a second uplink. Asserted in both
  directions.
- **`node`** = `pkgs.nodejs-slim_24`. The lake's flake records a node store path
  (`nodejs-slim-24.19.0`) and cannot do better from inside a pure flake with no
  inputs — `builtins.storePath` is refused in pure mode, so its pin is a
  run-time reference and not a build-time one. THIS flake has a `pkgs`, so it
  passes a real derivation, which is the seam the lake exported for exactly this
  unit ("`mkUplink` takes `node` as an argument precisely so U-D14, which HAS a
  `pkgs`, can pass a real node derivation"). The interpreter is then a closure
  edge of the generation that installs the unit, GC-protected, instead of a
  naked store path nothing owns. It is 24.18.0 at this nixpkgs pin rather than
  the lake's recorded 24.19.0, deliberately: the interpreter belongs to whoever
  installs the unit, and both are node 24. MEASURED: `require('tls')
  .rootCertificates.length` is 120 on BOTH, so the unit needs no `SSL_CERT_FILE`
  the way `home/seat-feeder.nix`'s python feeders do.
- **`wakes` = 1.** One wake per invocation: probe, pull, execute what the door
  admitted, mirror, re-arm, exit. There is no interval to set — the uplink holds
  no schedule of its own, by its card's non-goal ("no scheduling logic in the
  uplink: the lake proposes, the door answers"), and the only instant it waits
  for is a `next_wake_at` the lake handed back.
- **`kit` is a store file** (TL-18 / D-B18, dotfiles#304 — this is the change
  DF-U-D14-3 deferred), and **`plan` stays null**. See *The kit* below.
- **Two tmpfiles rules**, `d <state>/uplink 0700 - - -` and `d
  <state>/uplink/usage 0700 - - -`. The uplink creates its outbox recursively
  itself, so what the first rule adds is the MODE and its existence before the
  first run; the second is where every `usage_source.path_glob` in the kit
  resolves — the kernel resolves the glob but does not create the directory.
  Idempotent with seat-feeder's rule over the parent.

## The kit

The kit is the box's argv table: `argv_ref → {argv, cwd, env_allowlist,
usage_source, stdin}`. The lake never originates an argv (spec §2.2c) and
neither does the uplink — a proposal carries the NAME and the box carries the
command (spec §2.1: *"the argv the kit names IS the harness"*). It is rendered
into the store by `home/tally-uplink.nix` and named by
`services.tally-uplink.kit`, so the table the unit resolves against is a
reviewed artifact and never a file edited on the box (Rule 9, dotfiles#293).

| ref | argv | state |
|---|---|---|
| `build:LOCAL-SMOKE` | a `writeShellScript` that writes one usage line and exits 0 | **ENABLED** |
| `scope(build:LOCAL-SMOKE)` | `/bin/sh -c true` | ENABLED (declared no-op) |
| `eval(build:LOCAL-SMOKE)` | `/bin/sh -c true` | ENABLED (declared no-op) |
| `claude:headless` | `claude -p --output-format json --permission-mode dontAsk --max-turns 20 --model opus` | **DESIGNED, NOT ENABLED** |

The refs are the acceptor's own taskId scheme — a worker cell is the label and
its two companions are `scope(<taskId>)` and `eval(<taskId>)`, which is what the
factory proposes today (`argv_ref ?? taskId`). The no-op is `/bin/sh -c true`
and **not** `/bin/true`: MEASURED on this box, `/bin` holds exactly one entry,
`sh`, so an argv naming `/bin/true` would attest a spawn failure rather than the
pass the cell is about.

**Why the enabled entry is local and not a seat.** The first unattended run
leases a row the served kernel actually serves — `mechanical`, one of the three
in `modules/tally-b.nix`. The seat rows (`cc`, `cc2`, `cc3`, `codex`,
`pi-qwencloud`) are `owner: tom`, written by the U-D12 feeders through the
meters dir (`tally docs/rows.md:41-55`; `modules/tally-b.nix:57-63` excludes
them deliberately), and a kernel lease on one of them would make `stamp_row`
write `owner: kernel` over a feeder-owned file — one file, two writers. D-B6
already bars unattended spend of the `codex` seat. `utility-model` (llama-swap,
`qwen3.6-35b-a3b` on the `gpu-coordinator` row) is the documented NEXT entry
and not tonight's: a cold weight load can outrun a short lease, and the first
unattended run should fail for a reason, not for a stopwatch.

**Why `claude:headless` is written out and left out.** It is a Nix attribute
behind `enableClaudeSeat = false`, so the design is reviewable rather than
reconstructed later, and so a proposal naming the ref is refused **by name**
against a kit file that visibly contains no such entry (`readKit(…).resolve`,
lake `apps/uplink/src/kit.mjs`). Whether the kernel may lease a Claude seat at
all, and through which row, is Tom's ruling and is asked in dotfiles#362.
D-B18's ruled text is `env CLAUDE_CONFIG_DIR=<seat root> claude -p
--output-format json --permission-mode bypassPermissions --model opus
<brief-file>`; the form recorded here is the conservative default this unit
states as an ASSUMPTION for Tom to overrule with one comment —
`--permission-mode dontAsk` (never prompts, and DENIES what was not
pre-allowed) rather than `bypassPermissions` (never prompts, and allows),
`--max-turns 20` as a second cheap bound on a runaway loop, the brief on the
kit's `stdin` rather than as a path this module invented, `cwd` the item's
worktree, `env_allowlist = ["HOME","PATH","CLAUDE_CONFIG_DIR","LANG","TERM"]`.
The runtime ceiling is the lease envelope's `seconds`, enforced by the kernel's
own SIGTERM → 30 s checkpoint grace → SIGKILL rail — no second timer is added
(dotfiles#162). The OPEN half of TL-18 is the `usage_source` wrapper: `claude
-p` writes its usage into its own session transcript, not to
`$TALLY_USAGE_SOURCE_PATH`, so enabling the entry means wrapping the binary in
a script that copies the session's usage line to the resolved path.

**`plan` stays null.** The plan body is the acceptor's, re-POSTed to arm and
re-arm; authoring one here would be the lake proposing from the wrong side of
the seam, and arming is Tom's act. The topology check asserts `cfg.plan == null`
and that the rendered argv carries no `--plan`.

## The usage_source join

This is the seam that has never once been exercised on this box, and closing it
is why the enabled entry exists at all.

```
kit entry            exec.run request        the child's env        the ledger
─────────            ────────────────        ───────────────        ──────────
argv, cwd,       →   {lease, argv, cwd,  →   TALLY_EXECUTION_ID  →  witness_record
env_allowlist,       env_allowlist,          TALLY_USAGE_SOURCE_    .usage_source
usage_source{        usage_source{kind,      PATH  (and NOTHING     {kind, path}
kind, path_glob},    path_glob}, stdin}      else: env_clear +
stdin                                        env_allowlist)
```

The kernel resolves `path_glob` textually and only twice: a leading `~/` becomes
`$HOME/`, and the **first** `*` becomes the execution id's digest (`tally
crates/tally-kernel/src/exec.rs:95-140`). It exports the result to the child as
`TALLY_USAGE_SOURCE_PATH` alongside `TALLY_EXECUTION_ID` (`:689`), and writes
`usage_source{kind, path}` into the `witness_record` at `conclude` (`:953-958`).
`kind` is an OPAQUE label the kernel carries and never reads (`tally
docs/transport.md §2`); nothing in this repository branches on it.

So the enabled job's whole task is to leave **one JSON line at that path
carrying the execution id it was given** — after which the artifact and the
receipt name each other. `env_allowlist` is EMPTY for it on purpose: with
`env_clear`, the child sees those two variables and nothing else, so every path
it touches is one the store already names.

**Tonight's receipt is `witness_record` + `lease_release`** in
`~/.local/state/tally-rewrite/ledger.jsonl`, checked with the kernel's own
`ledger.verify`. Not a verdict: `ExecKernel::run` is start-and-wait
(`exec.rs:1580-1583`), `conclude` writes the witness and releases the lease with
`Disposition::Pass` (`:833-838`, `:859-862`), and `derive_verdict` returns early
when no evaluator lock is configured (`tally-socket/src/server.rs:371-375`).
`tests/tally-uplink/probe-FT-3-kit.sh` clause K4 proves the child half of this
offline, with `env -i` and the two variables and nothing else.

## The token is a path, never a value

`tokenFile` names `~/.local/state/tally-rewrite/lake-token` and NOTHING in this
repository writes, reads, prints or stores its contents — not in `flake.nix`,
not on the unit, not in the store, not in a tmpfiles rule that would create it
empty. Creating it empty would be a stub standing in for a credential, and an
empty bearer is a 401 that reads like a lake outage; until Tom writes it the
unit fails with `cannot read the lake token file <path>`, which names the path.
The lake reads it into an `Authorization` header and every diagnostic goes
through its own `redact`. Clause G asserts all of this and never opens the file.
The lake ORIGIN in the unit (`https://tally-lake.thomasmecattaf.workers.dev`) is
not a credential: the Worker refuses every request, reads included, whose
Authorization is not the bearer (lake D-A22-1). `DEFERRED.md` DF-U-D14-2.

## Where the eval-time guard lives

`modules/tally-b.nix` could put its invariants in NixOS `assertions`.
Home Manager gives no option of that kind — MEASURED: no `options.assertions`
anywhere in the pinned home-manager's `modules/` — and a top-level `assert` over
`config` in a home module recurses. So the invariants over literals sit in
`home/tally-uplink.nix` (the state root carries `tally-rewrite`; the rows file is
not under the live root) and the invariants over the RENDERED unit sit in
`flake.nix`'s `tally-uplink-topology` check, which runs under `nix flake check
--offline --no-build` — the card's own first clause. That is where a
home-manager module's eval-time guard lives in this repository.

## Coexistence, as bytes

Three tally estates now evaluate side by side, and none of them was disturbed by
this unit: the live `tally-daemon.service` on tom's USER bus writing
`~/.local/state/tally/`; U-D13's `tally-kernel.service` on the SYSTEM bus
writing `~/.local/state/tally-rewrite/`; and this `tally-uplink.service`, on the
USER bus, in the rewrite's root, talking to that kernel over its 0600 socket.
The uplink is a user unit because it is tom's own loop — tom's token, tom's
state tree, admitted argv run as tom — and no system-bus twin of it exists.
Every path it names is under `~/.local/state/tally-rewrite/`; the served
kernel's own `Ledger::open` refuses branch (a)'s paths by name
(`crates/tally-kernel/src/ledger.rs:31-35`), and this unit makes that a red eval
rather than a boot-time discovery. Clause F re-reads all four statements from a
bare PATH.

## What is deliberately not here

- **No switch.** The unit is DECLARED; only U-D19's coordinator switch installs
  it (`DEFERRED.md` DF-U-D14-1). MEASURED 2026-09-07: `systemctl --user
  is-active tally-uplink.service` → `inactive`, the declared-but-not-switched
  state, which is the intended one. Nothing is hand-started (Rule 9).
- ~~**No timer.**~~ **SUPERSEDED by FIX-E12 (dotfiles#351, D-E24).** As
  written, this non-goal held that "no unit in this repository fires the uplink.
  What starts a run is a socket event, a verdict, or a timer somebody else owns
  — U-D18's filler lane (`DEFERRED.md` DF-U-D14-4)." That timer was never
  wired. MEASURED 2026-09-07/08: the service had been `failed` for 7h with
  `TriggeredBy=`, `WantedBy=`, `RequiredBy=` and `Wants=` all empty,
  `systemctl --user cat tally-uplink.timer` → rc 1 'No files found', its
  reverse-dependency tree the single line `tally-uplink.service`, and
  `grep -c uplink ~/research-methods/tools/e1-loop.sh` → 0 rc 1 — so with
  `wakes = 1` nothing on the box could ever start it again. `home/tally-
  uplink.nix` now declares **`tally-uplink.timer`** on the coordinator:
  `OnActiveSec` / `OnUnitInactiveSec` = `5min` (the drain's own declared
  cadence; the monotonic form measures from the END of the previous pass,
  failures included, so wakes cannot pile up behind a red run), `Persistent =
  false`, `Unit = tally-uplink.service`, `WantedBy = timers.target`. The
  SERVICE is unchanged — still `Type=oneshot`, still `wakes = 1`, still **no
  `Install` section of its own** — so the card's non-goal ("no scheduling logic
  in the uplink") still holds: the clock is a separate unit, and the uplink
  still waits only on the `next_wake_at` the lake handed back. Asserted by
  `tally-uplink-topology` and by `tests/tally-uplink/probe-FIX-E12.sh` (rc 0).
  It lands live at the next coordinator switch, like everything else here.
- ~~**No kit, no plan** (DF-U-D14-3).~~ **SUPERSEDED for the kit by FT-3
  (dotfiles#361, TL-18 / D-B18, dotfiles#304):** the box now carries a store
  kit with one enabled local entry, and `claude:headless` designed and
  disabled — see *The kit* above. **`plan` is still null** and still deliberate.
- **No evaluator lock, and that is now the settled state, not a gap.**
  `services.tally-kernel.evaluatorLock = null` (`modules/tally-b.nix:188-190`)
  is CORRECT: `exec.run` needs no verdict — it is start-and-wait, `conclude`
  writes the `witness_record` and releases the lease with `Disposition::Pass`,
  and `derive_verdict` returns early when no lock is configured
  (`tally-socket/src/server.rs:371-375`). Nothing here adds evaluator or
  verdict work.
- **No edit to `home/tally.nix`, `modules/tally-b.nix` or the feeders.**

## How to re-run the acceptance

```console
$ bash tests/tally-uplink/test-tally-uplink-input.sh   # U-D14, clauses A0/A/B/C/D/E/G/H/F
$ bash tests/tally-uplink/probe-FIX-E12.sh             # the WAKE, clauses S1..S5
$ bash tests/tally-uplink/probe-FT-3-kit.sh            # the KIT and the join, clauses K1..K7
```

Clauses: A0 lock-update no-op; A `nix flake check --offline --no-build`; B the
card's eval → `true`; C the lake's exports (the module, the packaged
`apps/uplink`, the recorded node); D the pin (flake.nix ↔ flake.lock ↔ pushed);
E the unit's shape; G the token as a path; H the rows file parsed by the very
code that will parse it; F the non-goals in every direction. MEASURED
2026-09-07 in the delivery worktree: **rc 0, 36 `[P]`, 0 `[F]`.**

The card's `mutation_hint` — "remove the module import → the eval is false" —
was MEASURED red: with `./tally-uplink.nix` dropped from `home/home.nix`, the
card's own eval prints exactly `false`, and the suite exits non-zero.
