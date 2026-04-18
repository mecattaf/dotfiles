if test (hostname) != "harness-desktop"
    function desk
        set session (if test (count $argv) -gt 0; echo $argv[1]; else; echo "main"; end)
        kitten ssh harness-desktop -t shpool attach $session
    end
end
