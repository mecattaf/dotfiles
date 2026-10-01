{
  config,
  lib,
  pkgs,
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
  # GTK4 / libadwaita apps ignore gtk-theme-name; the only override they honour
  # is user CSS at ~/.config/gtk-4.0/. Each theme dir carries its MacTahoe
  # variant's gtk-4.0/ (a store path), and ~/.config/gtk-4.0/{gtk.css,
  # gtk-dark.css,assets} point THROUGH the ~/.config/theme pointer at it, so
  # the one symlink flip re-themes GTK4 too (on the app's next start; GTK4
  # reads gtk.css once). GTK3 follows `gsettings gtk-theme` live instead.
  gtk4Dirs = lib.mapAttrs' (
    name: t:
    lib.nameValuePair "themes/${name}/gtk-4.0" {
      source = "${pkgs.${t.gtk.package}}/share/themes/${t.gtk.theme}/gtk-4.0";
    }
  ) themes.checked;
  viaPointer = f: {
    source = config.lib.file.mkOutOfStoreSymlink "${cfgHome}/theme/gtk-4.0/${f}";
  };
in
{
  xdg.configFile =
    lib.mapAttrs (_: text: { inherit text; }) themes.fragments
    // gtk4Dirs
    // {
      "gtk-4.0/gtk.css" = viaPointer "gtk.css";
      "gtk-4.0/gtk-dark.css" = viaPointer "gtk-dark.css";
      "gtk-4.0/assets" = viaPointer "assets";
    };

  # Every theme's GTK package must be on the profile so GTK finds
  # share/themes/<dir> through XDG_DATA_DIRS (home.nix's gtk.theme.package
  # covers noir's; the claude variants ride along here).
  # (unique on the attr NAMES: lib.unique on derivations compares attrsets and
  # recurses forever.)
  home.packages = map (n: pkgs.${n}) (lib.unique (lib.mapAttrsToList (_: t: t.gtk.package) themes.checked));

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
