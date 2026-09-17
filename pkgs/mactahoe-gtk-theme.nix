# MacTahoe GTK theme, recoloured at the SCSS source for the theme switcher.
#
# Built from upstream source (vinceliuice/MacTahoe-gtk-theme), NOT vendored.
# One derivation per `variant`; the only customisation is a set of colour
# substitutions in src/sass/_colors.scss (and, for claude, the accent in
# _colors-palette.scss), applied with --replace-fail so upstream drift is
# caught at build time. The grey/orange accent and the solid opacity variant
# are STOCK install.sh flags, not customisations.
#
#   oled   (default) — Tom's noir: upstream's dark surfaces (#242424
#          base/backdrop, #333333 bg/headerbar) forced to pure black
#          ("rgba(5,5,5,0.96) → #000000 for true OLED black"). Dark-only
#          branch of the if(...)s, so its Light variants are 100% stock.
#          Theme dirs: MacTahoe-{Dark,Light}[-solid]-grey[-(x)hdpi].
#   claude — both branches recoloured to claude.ai's own light and dark
#          tokens (~/colors/waves/capture/claude-code-theme/claude-tokens-
#          {light,dark}.json), accent = Anthropic clay #D97757 via the
#          `orange` slot. Theme dirs: MacTahoe-Claude-{Dark,Light}[-solid]-
#          orange[-(x)hdpi]. Consumed by home/themes/claude-{dark,light}.nix.
#
# Modeled on nixpkgs' whitesur-gtk-theme derivation — MacTahoe's install.sh is a
# direct fork of WhiteSur's, so the same sudo/$HOME/shebang fixups apply.
#
# Builds once, then content-addressed: a normal `switch` reuses the store path
# (0s); it only rebuilds when `rev`/a substitution changes, and CI→cache means
# other devices substitute the result instead of building.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  glib,
  gnome-themes-extra, # adwaita engine for the Gtk2 part
  jdupes,
  libxml2,
  sassc,
  util-linux,
  variant ? "oled",
}:
let
  variants = {
    oled = {
      pname = "mactahoe-gtk-theme-oled-grey";
      themeName = "MacTahoe";
      accent = "grey";
      description = "MacTahoe GTK theme, light + dark, grey accent, custom OLED-black dark surfaces";
      # Dark variant only; $darker is off so only the 3rd value in each
      # if(...) matters. base/backdrop → pure black, bg/headerbar → near-black
      # so surfaces stay distinguishable.
      colorsPatch = ''
        substituteInPlace src/sass/_colors.scss \
          --replace-fail '#1f1f1f, #242424))' '#1f1f1f, #000000))' \
          --replace-fail '#282828, #333333))' '#282828, #0a0a0a))' \
          --replace-fail '#1e1e1e, #333333))' '#1e1e1e, #0a0a0a))'
      '';
    };
    claude = {
      pname = "mactahoe-gtk-theme-claude";
      themeName = "MacTahoe-Claude";
      accent = "orange";
      description = "MacTahoe GTK theme recoloured to claude.ai's light and dark tokens, clay accent";
      # Light = 1st value of each if(...), dark = 3rd. Tokens: bg-000/100/200
      # (#FFFFFF/#F9F9F7/#F3F3F0 light; #20201F/#151515 dark), text-000/200/400,
      # cds-text-secondary, accent-100 (links). Dark page = bg-100 #151515 with
      # bg-000 #20201F as the raised surface (headerbar, bg, sidebar), the
      # relation MacTahoe's stock dark already has (base darker than bg).
      colorsPatch = ''
        substituteInPlace src/sass/_colors.scss \
          --replace-fail '#1f1f1f, #242424))' '#1f1f1f, #151515))' \
          --replace-fail "'light', #f5f5f5, if(" "'light', #F9F9F7, if(" \
          --replace-fail '#282828, #333333)' '#282828, #20201F)' \
          --replace-fail "'light', #f2f2f2," "'light', #F3F3F0," \
          --replace-fail "'light', #363636, #dadada)" "'light', #131313, #F9F9F7)" \
          --replace-fail "'light', #242424, #dedede)" "'light', #131313, #F9F9F7)" \
          --replace-fail "'light', #424242, #afafaf)" "'light', #383835, #C3C2B7)" \
          --replace-fail "'light', #565656, #999999)" "'light', #7B7974, #97958D)" \
          --replace-fail "'light', #ffffff, if(\$darker == 'true', #1e1e1e, #333333))" "'light', #F9F9F7, if(\$darker == 'true', #1e1e1e, #20201F))" \
          --replace-fail '#242424, #404040), #f5f5f5)' '#242424, #383835), #F3F3F0)' \
          --replace-fail "'light', #575757, #FDFDFD)" "'light', #52514E, #F9F9F7)" \
          --replace-fail '#eeeff2, #fefefe)' '#eeeff2, #F3F3F0)' \
          --replace-fail '#1a1a1a, #2a2a2a)' '#1a1a1a, #151515)' \
          --replace-fail '#5e81ac, #3484e2)' "#5e81ac, if(\$variant == 'light', #256ABF, #5598E7))"
        # accent: the `orange` slot becomes Anthropic clay (--accent-brand, the
        # same hex in Claude's light and dark tokens); built with --theme orange.
        substituteInPlace src/sass/_colors-palette.scss \
          --replace-fail '$theme_color_orange:  #E9873A;' '$theme_color_orange:  #D97757;'
      '';
    };
  };
  v = variants.${variant};
in
stdenvNoCC.mkDerivation {
  pname = v.pname;
  # Pinned rev (2026-06-19); bump deliberately to take upstream updates — then
  # `nix build` prints the new hash to paste below. The dark-only build was
  # verified in a nixos/nix container 2026-06-19 (6 variants, OLED-black
  # surfaces); the Light variants were added 2026-07-04 via the stock repeatable
  # --color flag and have not been build-verified yet.
  version = "0-unstable-2026-06-19";

  src = fetchFromGitHub {
    owner = "vinceliuice";
    repo = "MacTahoe-gtk-theme";
    rev = "3267b3dfd9b6c3e775ad9b1f3079f848fc076bf6";
    hash = "sha256-/XTUUq5Uyuxgr0cZTmkUmj2/NrM1GEZ7pgrnlqKI6K0=";
  };

  nativeBuildInputs = [
    glib
    jdupes
    libxml2
    sassc
    util-linux
  ];

  buildInputs = [ gnome-themes-extra ];

  postPatch = ''
    find -name "*.sh" -print0 | while IFS= read -r -d "" file; do
      patchShebangs "$file"
    done
    # the install script reaches for sudo + a real $HOME; neither exists/needed
    # in the sandbox (verbatim from nixpkgs whitesur-gtk-theme):
    substituteInPlace libs/lib-core.sh \
      --replace-fail '$(which sudo)' false
    substituteInPlace libs/lib-core.sh \
      --replace-fail 'MY_HOME=$(getent passwd "''${MY_USERNAME}" | cut -d: -f6)' 'MY_HOME=/tmp'
    # MacTahoe's install (unlike WhiteSur's) gates deps behind a package-manager
    # check whose fallback fetches remote time over the network (`exit 1` with no
    # internet) and sleeps 15s. All deps are provided via nativeBuildInputs, so
    # neuter both: prepare_deps (network) and installation_sorry (the 15s sleep).
    substituteInPlace libs/lib-install.sh \
      --replace-fail 'prepare_deps() {' 'prepare_deps() { return 0;' \
      --replace-fail 'installation_sorry() {' 'installation_sorry() { return 0;'

    # ── the recolouring (the whole reason this isn't just nixpkgs) ──
    ${v.colorsPatch}
  '';

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/themes
    # -c light/dark : both colors   -t grey : grey accent   -o normal/solid :
    # both opacities. install.sh also emits the -hdpi/-xhdpi variants
    # automatically, so all 6 dark directories are produced
    # (<name>-Dark-<accent>, -Dark-solid-<accent>, each + -hdpi/-xhdpi) plus
    # the matching 6 Light dirs.
    # MacTahoe's no-gnome-shell branch leaves SHELL_VERSION empty (upstream bug),
    # generating invalid SCSS ($GNOME_SHELL: ;). gnome-shell is never present in a
    # build sandbox, so set it explicitly — the overwriting line is gated behind
    # `command -v gnome-shell`, so this survives. (You run niri; the gnome-shell
    # theme produced is unused but must still compile for install.sh to finish.)
    export SHELL_VERSION=48
    # NB: --opacity/--color take ONE value per flag (install.sh does `shift 2`),
    # so multi-value variants must be passed as repeated flags, not space-listed.
    ./install.sh \
      --name ${v.themeName} \
      --color light --color dark \
      --theme ${v.accent} \
      --opacity normal --opacity solid \
      --dest $out/share/themes
    jdupes --quiet --link-soft --recurse $out/share
    runHook postInstall
  '';

  meta = {
    description = v.description;
    homepage = "https://github.com/vinceliuice/MacTahoe-gtk-theme";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
