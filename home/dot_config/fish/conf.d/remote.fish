if test (hostname) != "coordinator"
    # The coordinator is where sessions live. On another box (a thin client) a
    # terminal is a *projector*: it reaches the one herdr server on the
    # coordinator over the tailnet. If the network drops the client dies but
    # the session keeps running server-side — re-fire the keybinding to
    # reconnect with full state.
    function desk
        # No name seed and no pre-create: herdr owns session identity, so the
        # old `term-<mmdd-HHMMSS>-<rand>` scheme retired with it. `desk-resume`
        # is gone too — herdr's own workspace/session pickers cover resume on
        # the remote tier (ruling B18).
        exec herdr --remote coordinator
    end
end
