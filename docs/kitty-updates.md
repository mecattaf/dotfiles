Kitty uses the separately qualified source recipe `pkgs/kitty-0.50.nix`.
Moving `nixpkgs-fresh` changes some build inputs but does not advance that
recipe's literal version/tag/source hash/Go vendor hash.

Watching `kovidgoyal/kitty` stable GitHub releases belongs to the master
agency's fleet update protocol, outside this repository (the `update-check`
program that used to do it here is retired). The watch compares complete
versions against the client and NAS packages, including patch releases, and
ignores drafts, prereleases and nonnumeric tags. One review issue is reused per
release; a previously closed issue remains closed. The watch never edits the
recipe, builds a candidate, switches a system or restarts a terminal.

Adoption remains a reviewed source change:

1. In an isolated dotfiles worktree, inspect the official release/tag and its
   build requirements. Change the recipe's version only for the chosen stable
   tag; review upstream Python/Go/shader requirements and the inherited package
   definition. Rebase or retire `kitty-memory-procfs-fallback.patch` according to
   the new upstream implementation.
2. Refresh the `fetchFromGitHub` source hash using that exact tag. A controlled
   Nix fixed-output hash check with `hash = pkgs.lib.fakeHash` reports the actual
   fetched tree hash; copy only the verified reported value into the source
   hash field. This is a Nix tree/NAR hash, not a raw GitHub tarball SHA256.
3. Independently refresh the `buildGo126Module` `vendorHash` for the selected
   source and compatible Go toolchain. Use a controlled fake vendor hash and
   the Go dependency derivation's reported fixed-output hash, then replace the
   placeholder. A changed source hash is not a substitute for the Go vendor
   hash. If upstream requires another Go builder, review that builder change
   before obtaining its dependency hash. No fake hash belongs in the final PR.
4. Build the candidate's client and NAS packages on compute using the existing
   SSH-builder policy. Before every Nix build, verify at least 25 GB free on the
   build host. Preserve the host kernel/Mesa/package-set pins and retain the
   matching old holder packages required by live saved sessions.
5. Run the upstream Kitty checks and isolated native qualification: managed
   SSH early-command/typeahead, OSC7/133/clipboard behavior, actual image
   paste/drop and stale-target refusal, copy feedback, full Neovim RPC/image
   reconnect/multiple-cell UI cases, and the actual Imagine entry chords.
   The Python drop/copy adapters accept only explicitly qualified versions;
   review their allowlists and private geometry/query/cwd/child interfaces.
6. Review and adopt the resulting source/hashes/gate receipts separately from
   deployment. The release watch never authorizes activation or replacement of
   a running Kitty or retained NAS process.

If the version-named recipe is renamed, update its overlay import and this
page together. Nothing in this repository watches Kitty releases or adds a
timer or service for it.
