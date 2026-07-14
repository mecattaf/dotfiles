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
        # Arg → attach that exact session id. No arg → fresh, UNIQUE session:
        # `term-<mmdd-HHMMSS>-<rand>`. Self-contained (no flm, no network, no
        # blocking call) so the launch is instant and every Mod+Shift+Return is
        # a BRAND-NEW independent session — two presses in the same second never
        # collide onto (mirror) an existing session. The random suffix is 6 hex
        # from the kernel RNG. (Cosmetic LLM titling is a coordinator-local,
        # async concern — see `zmx-retitle`; the remote window's identity is the
        # white "remote" border set below, not an LLM name.)
        if test (count $argv) -gt 0
            set session $argv[1]
        else
            set session term-(date +%m%d-%H%M%S)-(cut -c1-6 /proc/sys/kernel/random/uuid)
        end
        kitty @ set-window-title "remote"
        # `zmx attach` creates the session if it doesn't exist, so no pre-create.
        # bash -lc + explicit ZMX_DIR pins the coordinator's canonical socket
        # dir (see conf.d/zmx.fish) — the raw kitten-ssh env lacks
        # XDG_RUNTIME_DIR while login shells have it, which used to split
        # sessions across two socket dirs.
        kitten ssh coordinator -t 'bash -lc "ZMX_DIR=/tmp/zmx-$(id -u) zmx attach '$session' fish"'
        kitty @ set-window-title
    end

    function desk-resume
        # Mod+Ctrl+Shift+Return counterpart to `desk`: list the coordinator's
        # live sessions over ssh, fzf-pick one locally (snappier than a remote
        # picker), then attach over kitten ssh.
        kitty @ set-window-title "remote"
        # zmx-annotate (repo-owned ~/.local/bin, on the coordinator) emits
        # `name\t<flm-title · ~dir · age · attached|dormant>` per session —
        # the same annotated list zmx-resume shows locally, so both devices
        # see identical pickers. fzf shows only the display field; we attach
        # by field 1. login shell (bash -lc) so the home-manager profile
        # (zmx) and ~/.local/bin (zmx-annotate) are on PATH; a bare
        # `ssh host …` runs non-login and may not find them. Plain ssh (no
        # -t) keeps the list clean for fzf.
        set lines (ssh coordinator 'bash -lc "zmx-annotate"' 2>/dev/null)
        # Fallback for a coordinator that predates zmx-annotate: plain name
        # list (ZMX_DIR pinned — see conf.d/zmx.fish), duplicated into both
        # fields so the same fzf still renders.
        if test -z "$lines"
            set lines (ssh coordinator 'bash -lc "ZMX_DIR=/tmp/zmx-$(id -u) zmx list --short"' | awk '!/^annex-/{printf "%s\t%s\n", $0, $0}')
        end
        set line (printf '%s\n' $lines | fzf --prompt='attach> ' --no-sort --delimiter='\t' --with-nth='2..')
        if test -n "$line"
            set parts (string split \t -- $line)
            set session $parts[1]
            # Carry the flm title into this window's identity (cosmetic; the
            # session name is untouched). Keep the "remote" prefix so the
            # (currently disabled) white-border rule in window-rules.kdl —
            # an unanchored regex on "remote" — still matches if re-enabled.
            if test (count $parts) -ge 2
                set title (string split ' · ' -- $parts[2])[1]
                test -n "$title"; and kitty @ set-window-title "remote: $title"
            end
            kitten ssh coordinator -t 'bash -lc "ZMX_DIR=/tmp/zmx-$(id -u) zmx attach '$session' fish"'
        end
        kitty @ set-window-title
    end
end
