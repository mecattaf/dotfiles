if test (hostname) != "harness-desktop"
    function desk
        # No arg → fresh UUID, like `claude` spawning a new session.
        # Arg → reattach to that session id, like `claude --resume <uuid>`.
        # Each Mod+Shift+Return invocation gets its own session this way.
        set session (if test (count $argv) -gt 0; echo $argv[1]; else; cat /proc/sys/kernel/random/uuid; end)
        kitty @ set-window-title "remote"
        kitten ssh harness-desktop -t shpool attach -c fish $session
        kitty @ set-window-title
    end
end
