{
  lib,
  pkgs,
  ...
}:
# pi extensions — the nix-native, immutable analog of `pi install`.
#
# `pi install npm:@foo/bar` is the IMPURE path: it fetches over the network into
# ~/.pi/agent/{npm,git}/ and mutates ~/.pi/agent/settings.json. We do neither.
# Instead each extension is fetched into the store (fetchFromGitHub, pinned by
# rev+hash) and handed to pi as a `-e <store-path>` flag through a thin wrapper.
# pi reads the package's package.json `pi` manifest and loads its resources IN
# PLACE — no copy, no network, no npm install (see below). settings.json stays
# 100% pi-owned and mutable; the roster lives here, in git, reproducibly.
#
# WHY -e AND NOT settings.json `packages`/`extensions`: settings.json is state
# pi writes to (theme, lastChangelogVersion, `pi config` toggles). Managing it
# from home-manager would make it a read-only symlink and fight those writes.
# The wrapper keeps the two planes cleanly separated — declared here, state there.
#
# WHY NO BUILD STEP: these are pi packages, i.e. TypeScript that pi transpiles
# and runs itself. A package needs a Nix build only if it has real *runtime*
# dependencies. pi-llama-swap has none — every non-relative import is either
# `import type` (erased before module resolution) or a node: builtin, and its
# sole package.json dependency (undici-types) is types-only. So the store SOURCE
# *is* the loadable package. An extension that DID carry runtime deps would need
# pkgs.buildNpmPackage (with an npmDepsHash) to vendor node_modules — swap `src`
# for that derivation and the rest of this module is unchanged.
#
# LAZY LOADING (the nvim question): pi loads extensions eagerly at startup —
# they're cheap JS modules, so there is no per-keystroke `lazy`-style deferral to
# win here. The knobs that matter are (1) the `enable` flag below — the exact
# analog of commenting a plugin out of a lazy.nvim spec — and (2) genuinely
# conditional loading, which pi already does via project-local `.pi/settings.json`
# (`packages`/`extensions` arrays, loaded only in trusted project dirs). Reach for
# the latter to scope an extension to one repo instead of the whole fleet.
#
# NOT host-gated: like claude-code, pi is a general dev tool every host runs.
let
  # ── extension roster ─────────────────────────────────────────────────────
  # One entry per extension — the whole "standard": a name, an `enable` toggle,
  # and an immutable `src`. Add a package by adding a stanza; disable one by
  # flipping `enable = false` (or deleting it). Update by bumping rev + hash
  # (nix-prefetch-url --unpack <github-archive-url>, then nix hash to-sri).
  extensions = {
    # llama-swap provider with dynamic model discovery — feeds the local model
    # roster served on this box (see modules/llama-swap.nix) into pi as a
    # first-class provider. https://pi.dev/packages/@danielmeneses/pi-llama-swap
    pi-llama-swap = {
      enable = true;
      src = pkgs.fetchFromGitHub {
        owner = "danielmeneses";
        repo = "pi-llama-swap";
        rev = "915861a1fc2dfd01991720d1c8854bc974cb5322"; # v0.1.1
        hash = "sha256-z0KJYGrl5QF+IRdTXQv1mS/v4XC/XdslEjJ2WI2Xmyk=";
      };
    };
  };

  # Enabled specs → a flat `-e <store-path>` argv the wrapper prepends.
  enabled = lib.filterAttrs (_: e: e.enable) extensions;
  loadArgs = lib.concatLists (lib.mapAttrsToList (_: e: [ "-e" (toString e.src) ]) enabled);

  pi = pkgs.llm-agents.pi;

  # The wrapper IS the loader. Interactive/agent runs get the roster prepended;
  # management subcommands pass straight through so `pi install/remove/update/
  # list/config` still operate on the real (unshadowed) settings.json.
  piWrapped = pkgs.writeShellScriptBin "pi" ''
    case "''${1-}" in
      install | remove | uninstall | update | list | config)
        exec ${pi}/bin/pi "$@"
        ;;
    esac
    exec ${pi}/bin/pi ${lib.escapeShellArgs loadArgs} "$@"
  '';
in
{
  # Replaces the bare `pi` that home/home.nix used to pull from the llm-agents
  # buildEnv (that entry is dropped there so this is the only `pi` on PATH).
  home.packages = [ piWrapped ];
}
