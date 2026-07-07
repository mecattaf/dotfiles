if test (hostname) != "harness-desktop"
    # The coordinator (harness-desktop) is where sessions live. On any other box
    # (laptops), a terminal is a *projector*: zmosh bootstraps over SSH then
    # switches to encrypted UDP, so the session survives Wi-Fi/cellular/VPN
    # changes and sleep-wake — no reconnect, no lost state. This supersedes the
    # old `kitten ssh harness-desktop -t shpool attach` (plain TCP, died on any
    # network change). Tailnet just provides the stable host + SSH reach.
    function desk
        # No arg → fresh session (timestamp name). Arg → project that session id.
        set session (if test (count $argv) -gt 0; echo $argv[1]; else; date +term-%m%d-%H%M%S; end)
        kitty @ set-window-title "remote"
        # `zmosh serve` (remote side) attaches to an EXISTING daemon socket — it
        # does NOT create one — so ensure the session exists first (`run` creates
        # it with a login shell, then returns), then project it over UDP.
        ssh harness-desktop zmosh run $session true >/dev/null 2>&1
        zmosh attach -r harness-desktop $session
        kitty @ set-window-title
    end

    function desk-resume
        # Mod+Ctrl+Shift+Return counterpart to `desk`: list the coordinator's
        # live sessions, fzf-pick one locally (snappier than a remote picker),
        # then project it over UDP.
        kitty @ set-window-title "remote"
        set session (ssh harness-desktop zmosh list --short | fzf --prompt='project> ' --no-sort)
        test -n "$session"; and zmosh attach -r harness-desktop $session
        kitty @ set-window-title
    end
end
