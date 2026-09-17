# MacTahoe icon theme — stock default (blue folders) plus one folder-colour
# variant per claude.ai/imagine wallpaper accent.
#
# Stock build otherwise: MacTahoe (unlike whitesur-icon-theme / colloid-icon-theme)
# isn't in nixpkgs yet — re-check occasionally. Modeled on nixpkgs'
# whitesur-icon-theme derivation (same upstream author / same install.sh).
#
# The default build emits COLOR_VARIANTS=('' '-light' '-dark'): MacTahoe,
# MacTahoe-light, MacTahoe-dark. Folder colours are install.sh "themes": each
# stock one is a directory colors/color-<name>/ of 18 folder SVGs drawn in ONE
# hex (grey = #686868) over white/black overlays, copied over places/scalable.
# The accents below add colors/color-<accent>/ generated from the grey set with
# that hex swapped for the wallpaper's own ground — the darker of the two
# grounds Anthropic ships per theme (~/colors/waves/capture/imagine-background.css
# --bg-primary-dark) — so `wallpaper olive` can put olive folders in Nautilus.
# Emitted as MacTahoe-<accent>{,-light,-dark}; everything but the folders
# dedupes to one copy under jdupes. Consumed by ~/.local/bin/theme (`theme icons`).
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  gtk3,
  hicolor-icon-theme,
  jdupes,
}:
let
  # accent → folder hex: the imagine theme's --bg-primary-dark.
  accents = {
    oat = "#d9d1c3";
    olive = "#697751";
    cactus = "#b6c8c1";
    sky = "#6488b4";
    fig = "#a55b74";
    heather = "#c0bed2";
    coral = "#dec4c4";
  };
  accentVariants = lib.concatMapStringsSep " " (a: "'-${a}'") (lib.attrNames accents);
  mkAccent = a: hex: ''
    cp -r colors/color-grey colors/color-${a}
    sed -i "s/#686868/${hex}/g" colors/color-${a}/*.svg
    grep -q "${hex}" colors/color-${a}/folder.svg
  '';
in
stdenvNoCC.mkDerivation {
  pname = "mactahoe-icon-theme";
  version = "0-unstable-2026-06-19";

  src = fetchFromGitHub {
    owner = "vinceliuice";
    repo = "MacTahoe-icon-theme";
    rev = "355f23aaed196d8de3b321e8dacd8d06888d4d96";
    hash = "sha256-YCtpagkXhRwD9NJRvgskq7yf4qr4XqUxQYUfyKD7mUs=";
  };

  nativeBuildInputs = [
    gtk3
    jdupes
  ];

  buildInputs = [ hicolor-icon-theme ];

  # the icon set is ~20k files + symlinks; skip the slow, pointless fixups
  dontPatchELF = true;
  dontRewriteSymlinks = true;
  dontDropIconThemeCache = true;

  postPatch = ''
    patchShebangs install.sh
    # the accent folder sets, then make install.sh's `--theme all` mean
    # "default + the accents" (the stock colours are not built).
    ${lib.concatStrings (lib.mapAttrsToList mkAccent accents)}
    substituteInPlace install.sh \
      --replace-fail "THEME_VARIANTS=(''' '-blue' '-purple' '-green' '-red' '-orange' '-yellow' '-grey' '-nord')" \
                     "THEME_VARIANTS=(''' ${accentVariants})"
  '';

  installPhase = ''
    runHook preInstall
    # --name is required: without it the theme dirs inherit the build-dir name.
    ./install.sh --dest $out/share/icons --name MacTahoe --theme all
    jdupes --link-soft --recurse $out/share
    runHook postInstall
  '';

  # drop dangling symlinks upstream ships (same as nixpkgs whitesur-icon-theme)
  postFixup = ''
    find $out/share/icons -xtype l -delete
    # every accent came out
    for a in ${lib.concatStringsSep " " (lib.attrNames accents)}; do
      test -d $out/share/icons/MacTahoe-$a-dark
    done
  '';

  meta = {
    description = "MacTahoe icon theme (stock vinceliuice build, default blue folders + imagine-accent folder variants)";
    homepage = "https://github.com/vinceliuice/MacTahoe-icon-theme";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
