# ax-conwip: the CONWIP scheduler as a user service

Module: `home/ax-conwip.nix`. Option namespace: `myAxConwip`. Check:
`checks.x86_64-linux.ax-conwip-topology` in `flake.nix`. Written 2026-09-23.

**Status: declared and OFF. `myAxConwip.enable` is set nowhere on this fleet, so
this module defines no unit on any host today.** The flake check asserts exactly
that, and it is written so that it goes red on the flip. Flipping it is Tom's.

## What the CONWIP is

`/home/tom/mecattaf/ax-conwip` is a CONWIP scheduler. CONWIP is constant
work-in-progress: a fixed number of slots, and a new item is admitted only when
a finished one gives its slot back. It is a cap on how much is in flight, not a
rate limit and not a queue discipline.

This one:

1. reads Claude ultracode workflow run records (`wf_*.json`);
2. derives one work item per `workflow_agent` entry of `workflowProgress`, never
   one per workflow. Phases become dependency edges between items;
3. resolves each item's full prompt out of the record's own `script` string, by
   scanning for the matching `agent(...)` call. It never parses and never
   evaluates that script: the dialect opens with `export const meta`, closes
   with a top-level `return`, and uses top-level `await`, which together mean no
   single JavaScript goal symbol will load it. A label that matches zero calls,
   or two, is a refusal with a named reason, not a guess;
4. admits items under a fixed work-in-progress cap, only on a free slot and only
   when every dependency edge into the item is satisfied;
5. dispatches each admitted item to an ax server as a Task over gRPC, using
   `UpdateTask`, which is an upsert. ax v0.3.0 has no `CreateTask` rpc at all;
6. gives the slot back when the Task reaches a phase the CONWIP calls terminal,
   which is `{Completed, Failed, Terminating}`. That is deliberately NOT ax's own
   terminal set, `{Running, Completed, Failed}`: a Running Task still occupies
   work-in-progress, so the end of the `WatchTask` stream is a signal to read the
   phase again, not a release;
7. writes an append-only ledger, one JSON object per line, deterministically
   serialized.

Read that repository's `DESIGN.md` first. It is the authority on all of the
above; this page only says what the module would run.

## Nothing is packaged, and why

**The `ax-conwip` repository has no remote.** It is a local git repository on the
coordinator, created with `git init`, and nothing has been pushed anywhere.

The consequences are the reason this module has the shape it has:

- **There is no flake input.** There is nothing for `inputs.ax-conwip` to point
  at. A `builtins.fetchGit` of a path that exists on one box is not a
  declaration; it is a machine-local accident that would break every other
  host's evaluation.
- **There is therefore no package.** There is no `pkgs/ax-conwip.nix` and no
  `.#ax-conwip`, because packaging follows the input.
- **So the unit runs a checkout in place.** `WorkingDirectory` is the
  `sourceDir` option, and `ExecStart` is `pnpm exec tsx src/serve.ts`, resolved
  against the `node_modules` that checkout already carries. That is a
  development shape, not a delivered one, and it is the single biggest reason
  `enable` must stay false.

This is the first thing to fix if the CONWIP is ever to be a real lane: give the
repository a remote, declare it as a flake input, package it, and change
`ExecStart` to name a store path. Until then, do not flip the gate on a host you
care about.

## What the module would run

One long-running user service, `ax-conwip.service`, on whichever host has the
gate set, running `src/serve.ts`.

Until 2026-09-23 the unit's `ExecStart` ran `src/cli.ts`, which reads the records
directory once, runs the loop over what it found, prints its ledger and exits: a
`Type = oneshot` in everything but name. `src/serve.ts` is the program that makes
the unit's own claim true. It polls the records directory every
`--poll-interval-ms` (2000 by default, and this module passes no other value),
derives each new `wf_*.json` exactly once keyed by absolute path, admits under a
cap that HOLDS FOR THE LIFE OF THE PROCESS rather than per tick, reads
`--meters` for seat admission through the same pure refusal rule the seat dry run
uses, and exits 0 on SIGTERM after appending a final `stop` line to its ledger.
Dispatch is DRY RUN by default; the live path needs all three of `--live`,
`AX_CONWIP_LIVE_HALOGEN=1` and a seat on the `["halogen"]` allow list in the
program's own `src/seats.ts`, and this module never passes `--live`.

Two startup refusals are worth knowing before flipping anything: a `recordsDir`
that does not exist is exit 2, not a watcher that polls nothing forever, and an
ax server unreachable at startup is exit 4, because `Restart = no` means a dead
process is a fact to read in the journal rather than a thing to paper over.

No timer: the release signal is a `WatchTask` stream, not a poll, so
there is nothing to wake on a cadence.

`Type=simple`, `Restart=no`, `Nice=10`. `Restart=no` is deliberate: the
scheduler holds slots for the life of the process, so restarting it silently
would re-derive and re-admit work that is already in flight. If it dies, that is
a fact to read in the journal.

**The unit carries no `Install` section.** Flipping `enable` DECLARES the unit;
it does not arm it and it does not start it. Starting it is a second, separate,
deliberate act. There are two gates here, not one, and that is on purpose.

### The options, and their defaults

| option | type | default | what it is |
|---|---|---|---|
| `enable` | bool | `false` | the gate. Set nowhere on this fleet. |
| `serverUrl` | str | `"127.0.0.1:8080"` | the ax server to dispatch to, as `host:port` |
| `metersDir` | path | `~/.local/state/tally-rewrite/meters` | the seat meters, READ ONLY. Passed both as `AX_CONWIP_METERS` and as the program's `--meters` |
| `wipCap` | positive int | `1` | how many Tasks may be admitted at once |
| `sourceDir` | path | `/home/tom/mecattaf/ax-conwip` | where the program lives, because it is not packaged |
| `recordsDir` | path | `~/.local/state/ax-conwip/records` | the `wf_*.json` run records to derive from, and to WATCH |
| `stateDir` | path | `~/.local/state/ax-conwip` | this module's own state root |

Three of those defaults are choices worth defending:

- **`serverUrl` defaults to loopback**, specifically the address the mock stack
  listens on by default (`ax-mockstack -addr 127.0.0.1:8080`). No default here
  points at a live host and none ever should: an accidental enable on a box with
  no mock stack running reaches nothing at all. On the coordinator the live
  ax-server proxy listens on `myAxFleet.apiListen` (127.0.0.1:8099), never on
  this default; ax-fleet-topology asserts that. Note that this is a gRPC target
  and not a URL. The transport is plain h2c with insecure credentials, so there
  is no scheme to write.
- **`wipCap` defaults to 1**, which is stricter than the program's own default
  of 2 and stricter than the seat dry run's 3. A cap is the one number where the
  conservative default costs only throughput.
- **`recordsDir` defaults to a path that does not exist**, so an accidental
  enable fails legibly instead of passing silently over an empty directory.

### The seat meters are an input and only an input

`metersDir` defaults to the REWRITE's meters directory,
`~/.local/state/tally-rewrite/meters` — the one `home/seat-feeder.nix` declares
and its three timers write. Not `~/.local/state/tally/meters`, which is branch
(a)'s and is pinned by `SHA256SUMS`. The two estates never share a path.

This module **never writes into either**. It declares no tmpfiles rule over the
meters directory and does not create it; `seat-feeder` owns that directory's
existence and its mode. The scheduler opens those files read-only. The flake
check asserts that no tmpfiles rule naming `ax-conwip` exists while the gate is
off.

## The sequence to enable it

Each step is separate and each is reversible. Do them in order.

1. **Decide the host.** The seat meters are per-user and the feeder timers that
   write them run on the coordinator only, so the coordinator is the only host
   where the default `metersDir` has anything in it.

2. **Put run records where the scheduler will look**, or point `recordsDir` at
   where they already are. The default path does not exist; `src/serve.ts` exits
   2 without `--records`, and exits 2 again if the directory it is pointed at
   does not exist. Records may also be dropped in AFTER the service is running:
   that is the whole point of the serve entry point, and a file is derived
   exactly once, so a record that is edited in place is not re-admitted.

3. **Set the option**, in the host's home-manager configuration:

   ```nix
   myAxConwip = {
     enable = true;
     serverUrl = "127.0.0.1:8099"; # or wherever the ax server actually listens
     wipCap = 1;
   };
   ```

4. **Edit `checks.x86_64-linux.ax-conwip-topology` in `flake.nix` in the same
   commit.** Its `enable == false` assertion goes red on the flip, deliberately,
   so that no gate on this fleet moves without a reviewer seeing it. Do not
   delete the check; narrow it to the hosts that are still off. Keep the
   flipped-unit assertions that follow it: they pin that `ExecStart` names
   `src/serve.ts`, carries `--meters`, does NOT carry `--live`, and that the
   flipped unit still has no `Install` section.

5. **Check it evaluates before rebuilding anything:**

   ```
   nix build --no-link .#checks.x86_64-linux.ax-conwip-topology
   nix eval .#nixosConfigurations.coordinator.config.home-manager.users.tom.systemd.user.services \
     --apply builtins.attrNames
   ```

   The second should now list `ax-conwip`. While the gate is off it does not,
   which is this module's whole present claim.

6. **Rebuild.** The usual switch, which is Tom's.

7. **Look at the unit before starting it.** It has no `Install` section, so the
   rebuild declares it and nothing wants it:

   ```
   systemctl --user cat ax-conwip.service
   systemctl --user status ax-conwip.service   # inactive (dead), as expected
   ```

8. **Start it by hand, once, and watch it:**

   ```
   systemctl --user start ax-conwip.service
   journalctl --user -u ax-conwip.service -f
   ```

   The ledger is printed to stdout and therefore lands in the journal. v1 keeps
   it in memory and writes nothing to `stateDir`.

9. **Stop it when you are done looking.** Nothing wants it, so a stop is final
   until the next manual start.

## What is deliberately not here

- No flake input, because the repository has no remote.
- No package, because packaging follows the input.
- No timer, because the release signal is a stream.
- Nothing enabled and nothing armed: the gate is off, and even with the gate on
  the unit has no `Install` section.
- No system-bus twin. This is a per-user scheduler reading per-user seat meters
  and it must never acquire a system unit. The check asserts that on all four
  hosts, the NAS included.
- No write to any meters directory, by this module or by the program.

## Related

- `home/seat-feeder.nix` — owns the rewrite's meters directory and its three
  feeder timers. R44: read-only from here.
- `modules/ax-client.nix` — the `myAxClient` gate that puts `kubectl` and the
  `ax` binaries on a host. Also off, also #454.
- dotfiles#455 — `nix flake check --no-build` aborts at
  `nixosConfigurations.client` before the `checks` output is reached. Until that
  is fixed, the check on this page must be built by hand:
  `nix build --no-link .#checks.x86_64-linux.ax-conwip-topology`.

## Unknowns and proposed defaults

- **Whether the scheduler should read the seat meters at all in v1.** The
  program's `DESIGN.md` section 10 lists "seat meters as an admission input"
  under what was DROPPED for v1: it admits on slots and edges only, and the
  meter refusal rule lives in the seat dry run, not in the loop. The module
  passes `metersDir` in as `AX_CONWIP_METERS` anyway. Proposed default: keep
  passing it, because the path is the thing worth declaring and reviewing, and
  an unread environment variable costs nothing. Revisit when the loop grows a
  meter gate.
- **Whether `recordsDir` should default to a real directory.** Proposed
  default: no. A path that does not exist is a legible failure; an empty
  directory that does exist is a silent pass.
- **Whether the ledger should be written to `stateDir` rather than printed.**
  Proposed default: printed, for as long as v1 keeps it in memory. When it is
  written, `stateDir` is where it goes and the tmpfiles rule already declared
  under the gate is what creates the directory.
- **Whether `Restart` should stay `no`.** Proposed default: yes, until the
  scheduler can reconcile against Tasks already in flight on the ax server. A
  restart that re-derives and re-admits is worse than a process that stays dead
  and legible.
- **Which host, if the gate is ever flipped.** Proposed default: the
  coordinator, because it is the only host whose feeder timers write the meters
  directory. Not measured against any real need; nobody has asked for this to
  run yet.
