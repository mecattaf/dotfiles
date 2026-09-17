{
  config,
  lib,
  ...
}:
# Theme switcher — the Nix half (2026-09-17, docs/theme-switcher-2026-09-17.md).
#
# Every theme's color fragments are written under ~/.config/themes/<name>/ in
# one generation (store-managed, re-emitted on switch). The RAW config files
# include ~/.config/theme/<fragment> — `theme`, singular, a plain symlink into
# `themes/` that ~/.local/bin/theme retargets at runtime and Home Manager never
# writes. Disjoint namespaces: HM owns the plural, the switcher owns the
# singular, so HM's cleanup can never eat the pointer and the pointer can never
# confuse HM's link step. Switching a theme therefore needs no rebuild; only
# adding a theme or changing a palette value does.
#
# The two precedents this copies: kitty-scrollback-nix.conf and niri-local.kdl
# (home.nix), generated files at a neutral ~/.config path pulled in by an
# absolute include from inside a whole-dir RAW symlink.
let
  themes = import ./themes { inherit lib; };
  cfgHome = config.xdg.configHome;
in
{
  xdg.configFile = lib.mapAttrs (_: text: { inherit text; }) themes.fragments;

  # Bootstrap and self-heal the pointer, never override a choice:
  #  - missing or dangling  → noir
  #  - pointing outside ~/.config/themes/ (a pre-switch preview render) → the
  #    theme of the same name if it exists, else noir
  #  - already a live theme → untouched
  home.activation.themePointer = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    theme_link="${cfgHome}/theme"
    themes_dir="${cfgHome}/themes"
    want=""
    if [[ ! -e "$theme_link" ]]; then
      want="noir"
    elif [[ "$(readlink -f "$theme_link")" != "$themes_dir"/* ]]; then
      want="$(basename "$(readlink "$theme_link")")"
      [[ -d "$themes_dir/$want" ]] || want="noir"
    fi
    if [[ -n "$want" ]]; then
      run ln -sfn $VERBOSE_ARG "$themes_dir/$want" "$theme_link.tmp"
      run mv -T $VERBOSE_ARG "$theme_link.tmp" "$theme_link"
    fi
  '';
}
