if test (hostname) != "harness-desktop"
    function desk
        set session (if test (count $argv) -gt 0; echo $argv[1]; else; echo "main"; end)
        kitty @ set-window-title "remote"
        kitten ssh harness-desktop -t shpool attach -c fish $session
        kitty @ set-window-title
    end
end
