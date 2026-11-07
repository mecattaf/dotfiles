function vi --description 'Local native Neovim UI for the retained NAS directory editor'
    if set -q DSH_EDITOR_VI; and test "$DSH_EDITOR_VI" = 1
        if not set -q AGENCY_KITTY_COMMAND; or test -z "$AGENCY_KITTY_COMMAND"
            printf 'vi: native NAS editor command is unavailable\n' >&2
            return 127
        end
        command $AGENCY_KITTY_COMMAND vi --directory (pwd -P) -- $argv
    else
        command nvim $argv
    end
end
