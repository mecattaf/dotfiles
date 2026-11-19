# Apply only at the client seat; NAS shells and other desktops stay independent.
if test -x /run/current-system/sw/bin/domicile-physical-session
    set -gx BROWSER /home/tom/.local/bin/desktop-web
end
