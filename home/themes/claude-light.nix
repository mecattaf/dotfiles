# claude-light — Claude's own light mode, as claude.ai ships it.
#
# Accents are the Claude Light 12-role syntax palette from the app bundle
# (~/colors/waves/capture/claude-code-theme/claude-themes-SOURCE.json); grounds
# and chrome are the light-mode CSS tokens (claude-tokens-light.json). Claude's
# theme defines NO terminal.ansi* colors, so the 16-slot mapping below is
# designed, not copied — every slot passes WCAG AA for normal text on #FFFFFF
# (~/colors/theme-switcher-design.md §5). Tune in ~/colors/colorlab.
#
# color0/color7/color15 follow the noir convention (dark text slots, since herdr's
# `terminal` theme uses White/Gray as FOREGROUNDS) rather than Solarized's
# light-grey convention. The price, inherent to every light terminal theme:
# anything that paints bright-white-on-black gets #131313 on #2B303B.
{
  name = "claude-light";
  polarity = "light";
  catppuccinFlavour = "latte";
  claudeCode = "light";

  ground = {
    base = "#F9F9F7"; # --bg-100, the app's main surface
    dim = "#F3F3F0"; # --bg-200
    raised = "#FFFFFF"; # --bg-000
    desktop = "#F0EFEC"; # --bg-300
  };

  fg = "#131313"; # --text-000 (Claude Light syntax fg is #14181F, one step away)
  fgDim = "#52514E"; # --cds-text-secondary light
  comment = "#6E7687"; # Claude Light `comment`
  muted = "#A5A49A"; # --_gray-300

  red = "#B80A18"; # property
  green = "#008000"; # string
  yellow = "#A66A00"; # --warning-100 — the palette has no yellow role
  blue = "#0051C2"; # function
  magenta = "#8100C2"; # keyword
  cyan = "#007F80"; # number
  orange = "#B24A00"; # variable

  accent = "#0051C2";
  brand = "#D97757";

  ansi = {
    black = "#2B303B"; # punctuation
    white = "#52514E"; # --cds-text-secondary
    brightBlack = "#6E7687"; # comment
    brightWhite = "#131313"; # fg
  };

  selection = {
    bg = "#CDE2FB"; # --accent-900 light: Claude's own selection tint
    fg = "#131313";
  };
  cursor = "#131313";
  cursorText = "#F9F9F7";

  border = {
    active = "#A5A49A"; # --_gray-300
    inactive = "#D2D1C7"; # --_gray-150
    urgent = "#B80A18";
  };
  tabIndicator = {
    active = "#8100C2";
    inactive = "#97958D"; # --text-400 light
  };
  insertHint = "#8100C280";
}
