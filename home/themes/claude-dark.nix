# claude-dark — Claude's own dark mode, as claude.ai ships it.
#
# Same 12-role accent palette as noir (they are the same palette — Claude Dark
# was recovered from the app bundle and Tom's hand-sampled noir accents matched
# it bit for bit, ~/colors/waves/capture/claude-code-theme/README-THEMES.md).
# What changes is the ground: claude.ai's code blocks sit on #1A1A1A (--bg-000
# at 50% over the page) and the page itself on #20201F (--bg-000 dark), with
# #151515 (--bg-100) one step below. Sources: claude-tokens-dark.json.
let
  noir = import ./noir.nix;
in
noir
// {
  name = "claude-dark";
  ground = {
    base = "#1A1A1A"; # code-block ground: the closest analogue to a terminal
    dim = "#151515"; # --bg-100
    raised = "#20201F"; # --bg-000
    desktop = "#20201F"; # the desktop reads one step above the terminal
  };
  muted = "#52514E"; # --_gray-600
  cursorText = "#1A1A1A";
  ansi = noir.ansi // {
    black = "#1A1A1A";
  };
}
