# A directory change is metadata, never a per-key or output transport. Use the
# physical NAS path so the file picker and editor share the same identity.
if status is-interactive; and set -q AGENCY_KITTY_SESSION; and test "$AGENCY_KITTY_HOST" = nas
    function __agency_kitty_directory --on-variable PWD
        set -l agency_physical_directory (pwd -P)
        set -l agency_encoded_directory (printf '%s' "$agency_physical_directory" | command base64 --wrap=0)
        printf '\033]1337;SetUserVar=agency_directory=%s\033\\' "$agency_encoded_directory"
    end
    __agency_kitty_directory
end
