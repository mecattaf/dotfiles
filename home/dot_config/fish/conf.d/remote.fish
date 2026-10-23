if test (hostname) != "nas"
    # Sessions live on the NAS; other boxes project that server over SSH.
    function desk
        # No name seed and no pre-create: herdr owns session identity, so the
        # old `term-<mmdd-HHMMSS>-<rand>` scheme retired with it. `desk-resume`
        # is gone too — herdr's own workspace/session pickers cover resume on
        # the remote tier (ruling B18).
        exec ~/.local/bin/herdr-projector
    end
else
    function desk
        exec herdr
    end
end
