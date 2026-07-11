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
        # Arg → attach that exact session id. No arg → fresh session: a
        # deterministic `term-<mmdd-HHMMSS>` name, best-effort upgraded to an
        # LLM title by zmx-title. zmx-title hits flm at $FLM_HOST (default
        # 127.0.0.1) with a hard ~2s cap and, on ANY failure, prints the
        # timestamp name byte-for-byte — so on a box with no local flm this
        # stays exactly `term-…`. Set FLM_HOST=coordinator to title fresh
        # remote sessions against the coordinator's NPU.
        if test (count $argv) -gt 0
            set session $argv[1]
        else
            set session (~/.local/bin/zmx-title (date +term-%m%d-%H%M%S) "remote terminal session")
        end
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
