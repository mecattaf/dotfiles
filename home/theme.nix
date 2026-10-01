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
  # is user CSS at ~/.config/gtk-4.0/gtk.css. Since scroll/transition
  # (2026-10-01) that file is the GENERATED, variables-only `gtk4.css` fragment
  # (home/themes/default.nix): libadwaita's own Adwaita sheet with Tom's
  # grounds and the exact clay accent painted through its CSS custom
  # properties. It used to be MacTahoe's whole gtk-4.0 sheet, which defines no
  # variables (unrestyled widgets kept Adwaita colours: mixed palettes) and
  # ships translucent surfaces that only looked right under niri's blur.
  # gtk-dark.css and assets/ went with it: libadwaita never loads the former
  # and only the MacTahoe sheet used the latter.
  # ~/.config/gtk-4.0/gtk.css points THROUGH the ~/.config/theme pointer, so
  # the one symlink flip re-themes GTK4 too (on the app's next start; GTK4
  # reads gtk.css once). GTK3 keeps MacTahoe and follows `gsettings gtk-theme`
  # live (written by ~/.local/bin/theme, the one writer).
  viaPointer = f: {
    source = config.lib.file.mkOutOfStoreSymlink "${cfgHome}/theme/${f}";
  };
in
{
  xdg.configFile = lib.mapAttrs (_: text: { inherit text; }) themes.fragments // {
    "gtk-4.0/gtk.css" = viaPointer "gtk4.css";
  };

  # Every theme's GTK3 package must be on the profile so GTK finds
  # share/themes/<dir> through XDG_DATA_DIRS (home.nix no longer pins a
  # gtk.theme.package: Home Manager's gtk module is off, see home.nix).
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
