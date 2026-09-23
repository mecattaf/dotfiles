# pkgs/substrate-apps/src: vendored source

- Upstream: agency-agency/substrate (private; the repo formerly named ax-conwip, Tom 2026-09-23 E10), local
  checkout `/home/tom/mecattaf/substrate`, branch `main`.
- Source sha: `dc7cd1d05b1e3938dace9d3d3cddc1a22d98d6cc` (synced 2026-09-23T21:40Z, apps/puller absent)
  "capacity: floor capacity service, gentle seats pusher, floor as the gate's default (G4)".
- Taken with `git archive <sha> package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json tsconfig.json
  apps/link apps/pusher`, unchanged (`./sync.sh /home/tom/mecattaf/substrate <sha>` does exactly this). The root
  `src/`, `test/`, `proto/`, `packages/*` and `apps/floor` are not vendored: the link bundle imports none of them,
  the pusher's bin and src import only node: builtins and each other (MEASURED grep), and the floor is the
  Cloudflare Worker, deployed from the substrate repo itself.
- Not vendored on purpose: the pusher's own vitest suite depends on `@substrate/planning` and `@substrate/factory`
  (workspace packages); it runs upstream (1530 passed at this sha, REPORTED substrate/RECEIPT.md). The nix
  checkPhase runs one dry tick against `apps/pusher/test/fixtures/seats-v1.json` instead.
- `apps/link` at this sha differs from the copy in `pkgs/substrate-link/src` (a021003) only in tests,
  `tsconfig.json` and `vitest.config.ts` (MEASURED `git diff --stat a021003 dc7cd1d -- apps/link`: 7 files, no
  `src/` change). The NAS module `hosts/nas/substrate-link.nix` keeps `pkgs/substrate-link` as its default until a
  follow-up re-points it here; `.#substrate-apps-link` is the same program from the newer sha.

## Programs and where they run

| attr | upstream | host | dotfiles module |
|---|---|---|---|
| `link` | `apps/link` | NAS (system unit) | `hosts/nas/substrate-link.nix` (still on pkgs/substrate-link a021003) |
| `pusher` | `apps/pusher/bin/substrate-pusher.mjs` | coordinator (user unit) | `modules/substrate.nix` `services.substrate.pusher` |
| `puller` | `apps/puller` | coordinator (user unit) | `modules/substrate.nix` `services.substrate.puller` |

## Pending: apps/puller

At the pinned sha no branch of agency-agency/substrate has `apps/puller` (MEASURED `git ls-tree` over every ref,
2026-09-23 about 21:35Z; Lane B's Interfaces round was still open). The floor handoff names it: "the coordinator
puller (interpreter host). It leases runtime:interpreter, GETs /runs/:id/script, runs the interpreter with a floor
backend that POSTs /runs/:id/jobs and polls /runs/:id/events or /jobs/:id/output, then Completes the run." When it
lands: `./sync.sh <checkout> <sha>` picks it up, add a `puller` derivation here (bundle `apps/puller/src/main.ts`
the way `link` is bundled, or install its files the way `pusher` is), export it in the set, and drop the
`puller.package = null` default in `modules/substrate.nix`.

## To resync

1. `./sync.sh /home/tom/mecattaf/substrate <sha>` (rewrites `src/`, the sha line above and `sourceSha`).
2. In `default.nix` set `pnpmDeps.hash = lib.fakeHash`, `nix build .#substrate-apps-link`, paste the `got:` value.
3. `nix build .#substrate-pusher .#substrate-apps-link --no-link` and `nix flake check --no-build`.
4. Commit with the sha in the message.

## Unknowns and proposed defaults

- Whether the vendored copy should become a flake input once the repo is public-shaped. Default: keep vendoring by
  sha (E1: the code that wraps ax lives in dotfiles; a private input would also need a token on every build host).
- Whether `pkgs/substrate-link` (a021003) is retired in favour of this set's `link`. Default: yes, in the follow-up
  that re-points `hosts/nas/substrate-link.nix`, after Lane A's 4-VM test is green on ax/fleet-zero; not in this lane
  (hosts/ is Lane A's).
