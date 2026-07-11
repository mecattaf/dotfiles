if test (hostname) != "coordinator"
    # The coordinator is where sessions live. On any other box (worker, the
    # zenbook thin-client), a terminal is a *projector*: it reaches a persistent
    # LOCAL zmx session on the coordinator via `kitten ssh ... -t zmx attach`.
    # kitten ssh
    # (over the tailnet) gives reliable kitty terminfo/graphics/clipboard while
    # attached. There is no UDP roaming — that was zmosh's only addition, and
    # zmosh is unmaintained; zmx is local-only. If the network drops, the client
    # dies but the session keeps running server-side — re-fire the keybinding to
    # re-attach with full state. (Unchanged since the shpool era but shpool→zmx.)
    function desk
        # No arg → fresh session (timestamp name). Arg → attach that session id.
        set session (if test (count $argv) -gt 0; echo $argv[1]; else; date +term-%m%d-%H%M%S; end)
        kitty @ set-window-title "remote"
        # `zmx attach` creates the session if it doesn't exist, so no pre-create.
        kitten ssh coordinator -t zmx attach $session fish
        kitty @ set-window-title
    end

    function desk-resume
        # Mod+Ctrl+Shift+Return counterpart to `desk`: list the coordinator's
        # live sessions over ssh, fzf-pick one locally (snappier than a remote
        # picker), then attach over kitten ssh.
        kitty @ set-window-title "remote"
        # login shell (bash -lc) so the home-manager nix profile (where zmx
        # lives) is on PATH; a bare `ssh host zmx …` runs non-login and may not
        # find it. Plain ssh (no -t) keeps the list clean for fzf.
        set session (ssh coordinator 'bash -lc "zmx list --short"' | fzf --prompt='attach> ' --no-sort)
        test -n "$session"; and kitten ssh coordinator -t zmx attach $session fish
        kitty @ set-window-title
    end
end
