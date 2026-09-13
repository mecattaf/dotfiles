if test (hostname) != "coordinator"
    # The coordinator is where sessions live. On another box (a thin client) a
    # terminal is a *projector*: it reaches the one herdr server on the
    # coordinator over the tailnet. herdr-projector (~/.local/bin) runs
    # `herdr --remote coordinator --remote-keybindings server` and reattaches by
    # itself when the link drops; the session keeps running server-side
    # meanwhile. `--remote-keybindings server` is what keeps the tally popup
    # keys working from here (#385).
    function desk
        # No name seed and no pre-create: herdr owns session identity, so the
        # old `term-<mmdd-HHMMSS>-<rand>` scheme retired with it. `desk-resume`
        # is gone too — herdr's own workspace/session pickers cover resume on
        # the remote tier (ruling B18).
        exec ~/.local/bin/herdr-projector
    end
end
