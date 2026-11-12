# Home Manager session variables (hm-session-vars.sh) for every fish.
#
# Herdr panes and Claude Code sessions are children of systemd user services
# and never run a login shell, so ~/.bash_profile never reaches them. This
# runs in every fish, interactive or not, before config.fish.
#
# - The per-user profile comes first: with useUserPackages the file lives
#   there. ~/.nix-profile is the fallback.
# - Each `export NAME="VALUE"` line becomes a global exported variable.
#   $HOME and ${HOME} are expanded; a value with any other shell syntax is
#   skipped, because only a shell can read it.
# - PATH is skipped. Fish keeps the PATH its parent gave it; the file's
#   ~/.nix-profile/bin prefix would put stale imperative tools first.
# - __HM_SESS_VARS_SOURCED guards it as it guards the shell file, so a
#   session that already read the file (a login bash, a parent fish) keeps
#   its values.
# Pure fish, no fenv, no output: `fish -c` callers stay fast and clean.
function __hm_session_vars
    set -q __HM_SESS_VARS_SOURCED; and return
    for file in /etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh \
        $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh
        test -r $file; or continue
        set -gx __HM_SESS_VARS_SOURCED 1
        for line in (string match -r '^export [A-Za-z_][A-Za-z0-9_]*=".*"$' <$file)
            set -l pair (string match -r -g '^export ([A-Za-z_][A-Za-z0-9_]*)="(.*)"$' -- $line)
            test (count $pair) -eq 2; or continue
            contains -- $pair[1] PATH __HM_SESS_VARS_SOURCED; and continue
            set -l value (string replace -ra -- '\$\{HOME\}|\$HOME\b' $HOME $pair[2])
            string match -qr '[$`"\\\\]' -- $value; and continue
            set -gx $pair[1] $value
        end
        return
    end
end
__hm_session_vars
functions -e __hm_session_vars
