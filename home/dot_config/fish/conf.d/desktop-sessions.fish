# The client keeps Sway as a manual fallback beside its default Domicile desk.
# Other hosts share this raw fish directory but have no Domicile seat launcher.
if not test -x /run/current-system/sw/bin/domicile-physical-session
    return
end

function domicile
    if test (count $argv) -eq 0
        set -e DOMICILE_CONFIG_FILE
        set -e DOMICILE_CONSOLE_TRIAL_PATH
        set -e DOMICILE_DESKTOP_CLIENT_CONFIG
        set -e DOMICILE_ENGINE
        set -e DOMICILE_ENGINE_ARGS
        exec /run/current-system/sw/bin/domicile-physical-session
    else
        command /run/current-system/sw/bin/domicile $argv
    end
end

function sway
    if test (count $argv) -eq 0
        exec /run/current-system/sw/bin/sway-physical-session
    else
        command /run/current-system/sw/bin/sway $argv
    end
end
