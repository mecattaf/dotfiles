# noir — Tom's catppuccin-noir: Claude Dark's accents on pure OLED black.
#
# The accents are Claude Dark's 12-role syntax palette, bit for bit
# (~/colors/waves/capture/claude-code-theme/claude-themes-SOURCE.json, extracted
# from the claude.ai bundle). The grounds are #000000 — panel-off black on the
# Zenbook's OLED, and the habit the whole colorscheme investigation started from
# (~/colors/HANDOFF.md §1). noir differs from claude-dark ONLY in `ground` and
# `muted`; everything else is shared by construction, see claude-dark.nix.
{
  name = "noir";
  polarity = "dark";
  catppuccinFlavour = "mocha";
  claudeCode = "dark"; # ~/.claude.json "theme"

  ground = {
    base = "#000000"; # terminal / editor background
    dim = "#000000"; # tab bar, one step below base
    raised = "#000000"; # popups, one step above base
    desktop = "#000000"; # niri background-color + overview backdrop
  };

  fg = "#EAECF0"; # Claude Dark `fg`
  fgDim = "#D3D7DE"; # Claude Dark `punctuation`
  comment = "#818898"; # Claude Dark `comment`
  muted = "#45475a"; # inactive UI text (catppuccin mocha surface1, as bufferline had it)

  red = "#F47B85"; # property
  green = "#9BE963"; # string
  yellow = "#f9e2af"; # catppuccin mocha yellow — Claude's palette has no yellow role
  blue = "#70B8FF"; # function
  magenta = "#CC7BF4"; # keyword
  cyan = "#5EEDED"; # number
  orange = "#FBAD60"; # variable

  accent = "#70B8FF"; # URLs, cursor trail
  brand = "#D97757"; # Anthropic clay — identical in Claude's light and dark tokens

  # The 16 ANSI slots. Bright 1–6 equal normal 1–6: Claude's palette has exactly
  # one hue per role, and that is how kitty.conf has always been.
  ansi = {
    black = "#000000";
    white = "#D3D7DE";
    brightBlack = "#818898";
    brightWhite = "#EAECF0";
  };

  selection = {
    bg = "#264F78"; # Claude Code's TUI selection highlight (also VS Code's default)
    fg = "#EAECF0";
  };
  cursor = "#EAECF0";
  cursorText = "#000000";

  border = {
    active = "#555451";
    inactive = "#373735";
    urgent = "#F47B85";
  };
  tabIndicator = {
    active = "#CC7BF4";
    inactive = "#818898";
  };
  insertHint = "#CC7BF480";

  # GTK: the OLED-black MacTahoe (pkgs/mactahoe-gtk-theme.nix, variant oled).
  gtk = {
    package = "mactahoe-gtk-theme"; # pkgs attr, resolved in home/theme.nix
    theme = "MacTahoe-Dark-grey";
    colorScheme = "prefer-dark";
  };
}
