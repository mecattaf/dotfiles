# MacTahoe GTK theme — dark + grey accent, with the custom OLED-black surfaces.
#
# Built from upstream source (vinceliuice/MacTahoe-gtk-theme), NOT vendored.
# The ONLY customization is OLED black: upstream's dark surface colors in
# src/sass/_colors.scss (#242424 base/backdrop, #333333 bg/headerbar) forced to
# pure black, exactly the change behind the old harnessRPM `mactahoe-oled`
# tarball (changelog: "rgba(5,5,5,0.96) → #000000 for true OLED black"). The
# grey accent and the solid opacity variant are STOCK install.sh flags, not
# customizations.
#
# Modeled on nixpkgs' whitesur-gtk-theme derivation — MacTahoe's install.sh is a
# direct fork of WhiteSur's, so the same sudo/$HOME/shebang fixups apply.
#
# Builds once, then content-addressed: a normal `switch` reuses the store path
# (0s); it only rebuilds when `rev`/the OLED swap changes, and CI→cache means
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
}:

stdenvNoCC.mkDerivation {
  pname = "mactahoe-gtk-theme-oled-grey";
  # Pinned rev (2026-06-19); bump deliberately to take upstream updates — then
  # `nix build` prints the new hash to paste below. Build-verified in a nixos/nix
  # container 2026-06-19: produces all 6 variants with OLED-black surfaces.
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

    # ── the OLED customization (the whole reason this isn't just nixpkgs) ──
    # Dark variant only; $darker is off so only the 3rd value in each
    # if(...) matters. base/backdrop → pure black, bg/headerbar → near-black
    # so surfaces stay distinguishable. --replace-fail catches upstream drift.
    substituteInPlace src/sass/_colors.scss \
      --replace-fail '#1f1f1f, #242424))' '#1f1f1f, #000000))' \
      --replace-fail '#282828, #333333))' '#282828, #0a0a0a))' \
      --replace-fail '#1e1e1e, #333333))' '#1e1e1e, #0a0a0a))'
  '';

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/themes
    # -c dark : dark only   -t grey : grey accent   -o normal/solid : both
    # opacities. install.sh also emits the -hdpi/-xhdpi variants automatically,
    # so all 6 dirs the old RPM shipped are produced.
    # MacTahoe's no-gnome-shell branch leaves SHELL_VERSION empty (upstream bug),
    # generating invalid SCSS ($GNOME_SHELL: ;). gnome-shell is never present in a
    # build sandbox, so set it explicitly — the overwriting line is gated behind
    # `command -v gnome-shell`, so this survives. (You run niri; the gnome-shell
    # theme produced is unused but must still compile for install.sh to finish.)
    export SHELL_VERSION=48
    # NB: --opacity takes ONE value per flag (install.sh does `shift 2`), so the
    # two opacity variants must be passed as repeated flags, not space-listed.
    ./install.sh \
      --color dark \
      --theme grey \
      --opacity normal --opacity solid \
      --dest $out/share/themes
    jdupes --quiet --link-soft --recurse $out/share
    runHook postInstall
  '';

  meta = {
    description = "MacTahoe GTK theme, dark + grey accent, custom OLED-black surfaces";
    homepage = "https://github.com/vinceliuice/MacTahoe-gtk-theme";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
