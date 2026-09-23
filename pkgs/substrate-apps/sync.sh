#!/usr/bin/env bash
# pkgs/substrate-apps/sync.sh <substrate checkout> <sha>
# Re-vendors ./src from one commit of agency-agency/substrate: the workspace files plus apps/link,
# apps/pusher and, once it exists upstream, apps/puller. Then updates the sha line in SYNC.md and the
# sourceSha in default.nix. The pnpm hash is refreshed by hand (a failing build), never guessed.
set -euo pipefail
checkout=${1:?usage: sync.sh <substrate checkout> <sha>}
sha=${2:?usage: sync.sh <substrate checkout> <sha>}
here=$(cd "$(dirname "$0")" && pwd)
full=$(git -C "$checkout" rev-parse --verify "$sha^{commit}")
paths=(package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json tsconfig.json apps/link apps/pusher)
puller=absent
if git -C "$checkout" cat-file -e "$full:apps/puller" 2>/dev/null; then
  paths+=(apps/puller)
  puller=present
fi
rm -rf "$here/src"
mkdir -p "$here/src"
git -C "$checkout" archive "$full" "${paths[@]}" | tar -x -C "$here/src"
sed -i "s/^- Source sha: .*/- Source sha: \`$full\` (synced $(date -u +%FT%TZ), apps\/puller $puller)/" "$here/SYNC.md"
sed -i "s/^  sourceSha = \".*\";/  sourceSha = \"$full\";/" "$here/default.nix"
echo "vendored $full into $here/src: ${paths[*]} (apps/puller $puller)"
echo "next: set pnpmDeps.hash to lib.fakeHash in default.nix, nix build .#substrate-apps-link, paste the got: value, rebuild, commit"
