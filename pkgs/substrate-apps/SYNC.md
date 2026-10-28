# Vendored scheduler execution programs

- Upstream: `agency-agency/substrate`, canonical checkout `~/mecattaf/substrate`.
- Source sha: `c815232f1d5b9420ff0683feed9aab0057311c71` (synced 2026-10-28T16:32:15Z, apps/puller present)

The source includes the existing fleet Gufo capacity contract imported upstream
in `18d287d` and the native DSH runner, persistent-session recovery and required
project MCP plugin, trusted fixed maintenance tools, and scoped lease admission. The earlier Gufo-only local delta is now represented by
upstream commits; no second patch must be applied after syncing this revision.

`sync.sh CHECKOUT SHA` archives the workspace metadata, source, protocols,
packages and the link/pusher/puller apps from an exact commit. It does not copy
credentials, installed dependencies, private transcript corpora or the deployed
Cloudflare Worker. The latter is built and deployed from the Substrate repo.
The native DSH plugins are part of the runner package source and must ship with
it; deleting a plugin as presumed test data breaks persistent sessions.

The pnpm lock did not change in this update. The existing dependency hash stays
in `default.nix`; verify it by building the real puller on strix-coordinator.
A dependency-lock change requires refreshing that fixed-output hash, never
silently accepting an unverified substitute or falling back to a NAS build.

The Nix module, runtime model catalog and queued session bindings have separate
roles. Updating the package does not convert an old Pi session into DSH or
rewrite an existing model catalog. Follow `docs/substrate-dsh-cutover.md`, audit
queued work before resuming a holder, and record actual live execution after a
controlled rollout. No Herdr/user-manager restart is part of this migration.
