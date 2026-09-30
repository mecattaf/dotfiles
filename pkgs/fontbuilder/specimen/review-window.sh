#!/usr/bin/env bash
# =====================================================================
# THE DEFINITION-OF-DONE REVIEW WINDOW (spec 10 step 13, gate G2).
#
# Targets the INSTALLED fonts, so it takes NO out-dir.  Run it only
# after `sudo nixos-rebuild switch` has put anthropic-mono-nerd into
# /run/current-system/sw/share/fonts.  Before that it REFUSES, loudly,
# which is exactly the behaviour to expect from a scout session.
#
# It changes NOTHING on disk: kitty.conf is untouched and every font
# setting arrives as a --override.  Close the window and the desktop is
# exactly as it was.
#
# WHY THE PRE-FLIGHT EXISTS.  A lost quote in these -o strings fails
# SILENTLY to Liga SFMono - the very font the review compares against -
# so the command gates itself through kitty's OWN resolver, with the
# SAME argv, before any window is created.
#
# THREE TRAPS, ALL MEASURED, ALL ENCODED BELOW:
#
#  * Join with \x1f, NEVER \0.  bash silently drops NUL bytes in a
#    variable; the first attempt passed the pre-flight while resolving
#    to Liga SFMono.
#
#  * `-u FONTCONFIG_CACHE` is DEAD CODE and is deliberately absent.
#    FONTCONFIG_CACHE is not a fontconfig variable - only <cachedir>
#    and XDG_CACHE_HOME control cache placement.  FONTCONFIG_FILE and
#    FONTCONFIG_PATH ARE unset, because a build/test harness exports
#    them and the window would then render from the scratch tree.
#
#  * XDG_RUNTIME_DIR="/run/user/$(id -u)" resolves to the PRIVATE tree
#    if this is ever run inside ~/.local/bin/runtime-test, and the
#    window then never reaches Tom's session.  THE REVIEW SPAWN MUST
#    COME FROM A SHELL WITH THE REAL /run/user/1000.
#
# Usage:
#   specimen/review-window.sh              spawn the window
#   specimen/review-window.sh --dry-run    pre-flight only, never spawns
#   specimen/review-window.sh <demo.sh>    use a different demo script
# =====================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
DEMO="$HERE/anthropic-demo.sh"
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *)  DEMO="$arg" ;;
  esac
done
[ -r "$DEMO" ] || { echo "no demo script at $DEMO" >&2; exit 2; }
ASSERT="$HERE/assert_ov.py"
[ -r "$ASSERT" ] || { echo "no pre-flight at $ASSERT" >&2; exit 2; }

# ONE source of truth for the override strings - pre-flight and spawn
# cannot diverge, because they read the same array.
OV=(
  --override 'font_family=family="AnthropicMono Nerd Font Mono"'
  --override 'bold_font=family="AnthropicMono Nerd Font Mono" style="SemiBold"'
  --override 'italic_font=family="AnthropicMono Nerd Font Mono" style="Italic"'
  --override 'bold_italic_font=family="AnthropicMono Nerd Font Mono" style="SemiBold Italic"'
  --override 'font_size=16.0'
  --override 'disable_ligatures=never'
  --override 'window_padding_width=14'
)
REVIEW_ARGV=$(printf '%s\x1f' "${OV[@]}")
export REVIEW_ARGV

echo "pre-flight: kitty's own resolver, same argv, live kitty.conf in place"
# kitty +runpy wants a tty; `script -qec` supplies one without a window.
# The pre-flight runs with the SAME environment scrubbing as the spawn below
# (-u FONTCONFIG_FILE -u FONTCONFIG_PATH), so it cannot pass against a build
# harness's private font tree and then open a window rendering system fonts.
if ! env -u FONTCONFIG_FILE -u FONTCONFIG_PATH \
     script -qec "kitty +runpy \"exec(compile(open('$ASSERT').read(), 'assert_ov', 'exec'), {'__name__': '__main__'})\"" /dev/null; then
  echo
  echo "REFUSING TO OPEN: the overrides do not resolve to the Anthropic faces."
  echo "  If the faces are not installed yet, that is the expected answer -"
  echo "  commit 1 (fonts.packages + home.packages) has not been switched."
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  echo "--dry-run: pre-flight passed, NOT spawning a window."
  exit 0
fi

exec env -u FONTCONFIG_FILE -u FONTCONFIG_PATH \
     WAYLAND_DISPLAY=wayland-1 \
     XDG_RUNTIME_DIR="/run/user/$(id -u)" \
  "${KITTY_SPAWN:-kitty}" \
    --title 'Anthropic Mono — review' \
    --class 'anthropic-review' \
    "${OV[@]}" \
    --hold \
    bash "$DEMO"

# --- side-by-side variant: same window, today's face, for the A/B -----
#   --override 'font_family=family="Liga SFMono Nerd Font"' \
#   --override 'bold_font=family="Liga SFMono Nerd Font" style="Semibold"' \
#   --override 'italic_font=family="Liga SFMono Nerd Font" style="Italic"' \
#   --override 'bold_italic_font=family="Liga SFMono Nerd Font" style="Semibold Italic"' \
#
# --- if the old line density is wanted back, add: --------------------
#   --override 'modify_font=cell_height -6%'   # 54 px -> 51 px @ 192 dpi
#
# REVERT IS A TWO-FILE OPERATION (spec 2.8): after switch #2 the
# monospace alias points at the Anthropic family, so reverting
# kitty.conf alone gives the wrong family for every non-exact line.
# Revert modules/common.nix defaultFonts AND kitty.conf together.
