# pkgs/substrate-link/src: vendored source

- Upstream: the ax-conwip repository (now named "substrate", Tom 2026-09-23 E10), local only at the time of
  vendoring: `/home/tom/mecattaf/ax-conwip-wt-link`, branch `eval/2026-09-23-link`.
- Source sha: `a02100344205fcd20c93c0f9bdc87902adbbcd4e` (`a021003`), "link: final pass, fence every journaled
  earlier attempt and re-time the heartbeat sleep".
- Taken with `git archive a021003 package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.json apps/link`, unchanged.
  The root `src/`, `test/` and `proto/` (the CONWIP scheduler) are not vendored: `apps/link` imports none of them.
- Verified upstream at that sha (REPORTED `evals-2026-09-23/link/LINK-FINAL-2026-09-23.md`): `tsc --noEmit` rc 0,
  link suite 134 pass.
- The bundle uses `apps/link/proto/ax-p1.proto`, a superset of stock ax v0.3.0's API (it adds P1's
  `GetTaskResult`). On this fleet ax carries no patch, so that RPC answers Unimplemented and the link's
  `completion` defaults to `guest` (hosts/nas/substrate-link.nix).

To resync: `git -C <substrate checkout> archive <sha> package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.json
apps/link | tar -x -C pkgs/substrate-link/src`, update the sha above, then refresh `pnpmDeps.hash` in
`default.nix` (set it to `lib.fakeHash`, build, paste the `got:` value).

## Unknowns and proposed defaults

- When the substrate repository gets its remote (agency-agency/substrate), whether to switch this vendored copy to a
  flake input. Default: keep the vendored copy (E1: the code that wraps ax lives in dotfiles) and resync by sha.
