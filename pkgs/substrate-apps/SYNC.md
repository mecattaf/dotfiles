# pkgs/substrate-apps/src: vendored source

- Upstream: agency-agency/substrate (private; the repo formerly named ax-conwip, Tom 2026-09-23 E10), local
  checkout `/home/tom/mecattaf/substrate`, branch `main`.
- Source sha: `fc2f8bd5d1492343585914b4ed343d001a192f33` (synced 2026-09-24T12:01:48Z, apps/puller present)
  "DECISIONS: D-S13, queued jobs never expire (ruling M2)", committed 2026-09-24 09:04 CEST. It is 6f681d3 (the
  checkout the live coordinator puller and pusher were hand-started from on 2026-09-24) plus two floor-only commits
  (78b285d, fc2f8bd), so the box-side programs here are the ones proven live. History: first vendored at dc7cd1d
  (link and pusher only), then b105179 (2026-09-23, puller added), then this resync (63 commits later).
- Taken with `git archive <sha> package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json tsconfig.json
  src proto packages deploy apps/link apps/pusher apps/puller`, unchanged (`./sync.sh /home/tom/mecattaf/substrate
  <sha>` does exactly this; 332 files, 3.6 MB at fc2f8bd). The puller imports the workspace root (`substrate/src/...`),
  `@substrate/api`, `@substrate/link`, `@substrate/interpreter` and `@substrate/runners`, hence `src/`, `proto/` and
  `packages/*`. Not vendored: `test/`, `tools/`, `docs/`, `apps/floor` (the Cloudflare Worker, deployed from the
  substrate repo), `apps/cli` and `apps/mcp` (operator interfaces, not services of a box), `apps/evaluator` (new
  at fc2f8bd, the mechanical receipt evaluator; nothing on the box imports it). pnpm tolerates the lockfile
  importers of the apps not vendored.
- Not vendored on purpose: the pusher's own vitest suite depends on `@substrate/planning` and `@substrate/factory`
  (workspace packages); it runs upstream (1530 passed at b105179, REPORTED substrate/RECEIPT.md; not re-counted at fc2f8bd). The nix
  checkPhase runs one dry tick against `apps/pusher/test/fixtures/seats-v1.json` instead.
- `apps/link` at this sha differs from the copy in `pkgs/substrate-link/src` (a021003) only in tests,
  `tsconfig.json` and `vitest.config.ts` (MEASURED `git diff --stat a021003 dc7cd1d -- apps/link`: 7 files, no
  `src/` change). The NAS module `hosts/nas/substrate-link.nix` keeps `pkgs/substrate-link` as its default until a
  follow-up re-points it here; `.#substrate-apps-link` is the same program from the newer sha.

## What changed between b105179 and fc2f8bd that matters to the box

From `git log --oneline b105179..fc2f8bd -- apps/puller apps/pusher packages/runners packages/api deploy` (24
commits) and the config diffs. The pnpm dependency tree did not change (the lockfile only gains the
`apps/evaluator` importer), so `pnpmDeps.hash` is the same value as at b105179 (MEASURED with lib.fakeHash).

- Seat routing by `agent()` option (be42f18, merging eb956de and 22c4ae8): `agent(p, { seat: "codex" })` or
  `runsOn: ["seat:codex"]` runs on the one runtime `runtimes.toml` permits for that seat (the phase or default
  runtime first), else it is refused with the runtime=seat list. A runtime table's `seat` wins over `[seats]`; the
  floor refuses an unserved seat (d112022: runs-on carries the seat the runtime spends).
- `[credentials.seats]` (RG-1) and its alias `seat_dirs` (TX5), one map seat id -> Claude config dir, merged at
  load; a seat both spell with different dirs, or one dir claimed by two seats, is a load error; entries must be
  absolute after `~` expansion. With the map present every claude runtime with a local credential must name a seat
  in it and a call whose seat has no entry is refused. Without it, `[credentials].claude` serves only when set
  explicitly and at most one claude seat is bound. Also new in `[credentials]`: `context` (list of absolute paths
  bound read-only into gVisor jobs).
- `codexSandbox` (runtime tables, codex harness only): `"read-only"` (default) or `"workspace-write"`; set on any
  other harness it is a load error.
- `runtimes.toml` top level also gains `cancel_grace_ms` (default 10000; SIGTERM then SIGKILL, G-BK1) and
  `[hooks]` `pre_start` / `pre_exit` argv with `timeout_ms` (G-BK8). A runtime named `locked` is reserved for the
  untrusted shape (gvisor, `credential = false`, network not host).
- `peerCacheDir` (pusher.json; `--peer-cache-dir`): the seats oracle's `SEATS_PEER_CACHE_DIR`. Default now
  `~/.local/state/substrate/seats-peer-cache` (D-S09, a substrate-owned cache); `"inherit"` keeps the oracle's own
  default; a `tally-rewrite` path is refused (exit 2). The live pusher config sets `"inherit"`.
- New `[puller]` keys (`packages/api/src/config.ts`, `deploy/client.config.example.toml`), all optional:
  - `demand_dir`: marker dir touched while a run is held so the pusher reads at its active cadence (example
    `~/.local/state/substrate/demand`, the pusher's own `--demand-dir` default).
  - `capacity_wait_s`: how long a node waits on a stale or refused capacity reading before it fails. Default 600.
  - `drain_timeout_s`: first SIGTERM lets in-flight runs finish this long, then aborts them with the cancel
    grace; a second signal aborts, a third kills. Default 60; 0 aborts at once (G-BK4).
  - `health_addr`: loopback `host:port` serving `GET /status.json` and `/metrics`. Absent: no endpoint (G-BK7).
  - Top level (not `[puller]`): `read_token_file` (or `SUBSTRATE_READ_TOKEN_FILE`), the read-only bearer for
    `substrate watch` (TX4); the puller does not read it.
- Puller behaviour: streams the run's `events.jsonl` to the floor's live log while it holds the lease (G-BK3),
  uploads every local node's transcript before the verdict (TX2), run-scoped writes under the run's interpreter
  lease (G-BK5), self-fences before `reassignSeconds`, graceful drain ladder (G-BK2/G-BK4), marks pusher demand
  while a run is held and waits on capacity instead of nulling a node (0ba7550). Runners archive each job's
  harness transcript outside the run dir before cleanup and record finished attempts by stable id for resume (C3-4).
- Unchanged contract: the puller with no config exits 78 with a `config-invalid` line (`apps/puller/src/main.ts`;
  exit 3 pidfile held, 75 holder session conflict). The pusher still imports only `node:` builtins and its own
  files. Upstream `packages/runners/package.json` names a bin `bin/substrate-runners.mjs` that does not exist
  (the file is `bin/ax-conwip-runners.mjs`); pnpm warns and skips it, harmless for the puller.

## Programs and where they run

| attr | upstream | host | dotfiles module |
|---|---|---|---|
| `link` | `apps/link` | NAS (system unit) | `hosts/nas/substrate-link.nix` (still on pkgs/substrate-link a021003) |
| `pusher` | `apps/pusher/bin/substrate-pusher.mjs` | coordinator (user unit) | `modules/substrate.nix` `services.substrate.pusher` |
| `puller` | `apps/puller/bin/substrate-puller.mjs` | coordinator (user unit) | `modules/substrate.nix` `services.substrate.puller` |

## How the puller is installed

Upstream starts it as `node apps/puller/bin/substrate-puller.mjs`, which registers tsx's ESM loader and imports
`src/main.ts`; nothing is bundled upstream. The derivation keeps that: `pnpm install --prod --offline
--frozen-lockfile` from the shared `pnpmDeps`, then the whole tree with its production `node_modules` is copied to
`$out/lib/substrate-apps` and `bin/substrate-puller` wraps node over it. Its checkPhase starts it with no config
and requires exit 78 with a `config-invalid` line: every import resolved through tsx and the workspace links, and
`main()` ran to its first config check. Its configuration is the `[puller]` table of a client `config.toml`
(`packages/api/src/config.ts`, `deploy/client.config.example.toml`), which the module renders.

## To resync

1. `./sync.sh /home/tom/mecattaf/substrate <sha>` (rewrites `src/`, the sha line above and `sourceSha`), then
   `git add pkgs/substrate-apps`: the flake only sees tracked files, and a new upstream file left untracked fails
   the puller check with ERR_MODULE_NOT_FOUND (it did at fc2f8bd: `packages/api/src/seats.ts`).
2. In `default.nix` set `pnpmDeps.hash = lib.fakeHash`, `nix build .#substrate-apps-link`, paste the `got:` value.
3. `nix build .#substrate-pusher .#substrate-puller .#substrate-apps-link --no-link` and `nix flake check --no-build`.
4. Commit with the sha in the message.

## Unknowns and proposed defaults

- Whether the vendored copy should become a flake input once the repo is public-shaped. Default: keep vendoring by
  sha (E1: the code that wraps ax lives in dotfiles; a private input would also need a token on every build host).
- Whether `pkgs/substrate-link` (a021003) is retired in favour of this set's `link`. Default: yes, in the follow-up
  that re-points `hosts/nas/substrate-link.nix`, after Lane A's 4-VM test is green on ax/fleet-zero; not in this lane
  (hosts/ is Lane A's).
