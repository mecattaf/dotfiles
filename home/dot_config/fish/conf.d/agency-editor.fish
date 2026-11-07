# A killed editor cannot send VimLeavePre. Clear its Kitty identity when fish
# next draws a prompt, so Ctrl+B returns to the file picker after such a crash.
# Interactive-only: SSH commands and captured script output must stay clean.
if status is-interactive
    function __agency_editor_prompt --on-event fish_prompt
        if set -q KITTY_WINDOW_ID; or test "$TERM" = xterm-kitty
            printf '\033]1337;SetUserVar=nvim=\033\\'
        end
    end
end
