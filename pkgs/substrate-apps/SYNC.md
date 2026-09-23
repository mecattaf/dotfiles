# pkgs/substrate-apps/src: vendored source

- Upstream: agency-agency/substrate (private; the repo formerly named ax-conwip, Tom 2026-09-23 E10), local
  checkout `/home/tom/mecattaf/substrate`, branch `main`.
- Source sha: `b1051790f376c103ba4e901619ba11efeb78cef6` (synced 2026-09-23T21:27:53Z, apps/puller present)
  "docs: DEPLOY.md, deploying your own floor from a fresh clone to a verified live Worker"; the puller landed one
  commit earlier, 017893d "interfaces: typed HTTP API with /openapi.json, substrate CLI, MCP server in code mode,
  coordinator puller (E11)". First vendored at dc7cd1d (link and pusher only), resynced the same night.
- Taken with `git archive <sha> package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json tsconfig.json
  src proto packages deploy apps/link apps/pusher apps/puller`, unchanged (`./sync.sh /home/tom/mecattaf/substrate
  <sha>` does exactly this; 303 files, 3.2 MB). The puller imports the workspace root (`substrate/src/...`),
  `@substrate/api`, `@substrate/link`, `@substrate/interpreter` and `@substrate/runners`, hence `src/`, `proto/` and
  `packages/*`. Not vendored: `test/`, `tools/`, `docs/`, `apps/floor` (the Cloudflare Worker, deployed from the
  substrate repo), `apps/cli` and `apps/mcp` (operator interfaces, not services of a box).
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
