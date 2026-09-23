# Colours come from the theme fragment ~/.config/theme/colors.fish, rendered by
# home/theme.nix from home/themes/<name>.nix for whichever theme ~/.config/theme
# points at (~/.local/bin/theme retargets it). This file only loads it — at
# startup, and again at the next prompt after the pointer has moved, so running
# shells follow a `theme` switch too. No universal variables: `set -U` would
# write fish_variables, which is tracked in this repo.
#
# The theme-independent bits stay here.
set -g fish_color_cwd_root red
set -g fish_color_history_current --bold
set -g fish_color_match --background=brblue
set -g fish_color_valid_path --underline
set -g fish_pager_color_selected_background -r

function __theme_load --description 'source ~/.config/theme/colors.fish if the pointer moved'
    set -l target (readlink ~/.config/theme 2>/dev/null)
    if test -n "$target" -a "$target" != "$__theme_loaded"
        set -g __theme_loaded $target
        if test -r ~/.config/theme/colors.fish
            source ~/.config/theme/colors.fish
        end
    end
end
__theme_load

function __theme_on_prompt --on-event fish_prompt
    __theme_load
end
