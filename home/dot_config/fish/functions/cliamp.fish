function cliamp --wraps cliamp --description "cliamp wired to the NAS Navidrome (credentials from agenix)"
    # Every variable here is declared at function scope BEFORE the if, then
    # assigned inside it. fish scopes `set -l` to the enclosing block, so
    # exporting from within the `if` would drop the values before the final
    # `command cliamp` ever runs — the provider would silently vanish and cliamp
    # would fall back to the radio browser.
    set -l url $NAVIDROME_URL
    set -l user ""
    set -l pass ""

    # URL is the coordinator's tailnet name, never localhost or `nas`: Navidrome
    # runs on the NAS (hosts/nas/media.nix), which is Ethernet-only on the
    # 10.77.0.0/24 private link, so the coordinator's navidrome-relay socket
    # (hosts/coordinator/nas-client.nix) is the sole front door for every box.
    test -n "$url"; or set url http://coordinator.tail8dd1.ts.net:4533

    set -l creds /run/agenix/navidrome-credentials
    if test -r $creds
        set user (grep '^NAVIDROME_USER=' $creds | string replace 'NAVIDROME_USER=' '')
        set pass (grep '^NAVIDROME_PASSWORD=' $creds | string replace 'NAVIDROME_PASSWORD=' '')
    else
        # Only the coordinator gets the secret (secrets.nix). Anywhere else,
        # say so instead of opening a silently Navidrome-less browser.
        echo "cliamp: $creds unreadable — Navidrome disabled, local files only" >&2
    end

    # config.toml's [navidrome] block interpolates ${NAVIDROME_USER} and
    # ${NAVIDROME_PASSWORD}, so those two names must match its placeholders
    # exactly. NAVIDROME_URL/USER/PASS feed navidrome.NewFromEnv(), the
    # config-less fallback main.go tries second — it needs all three non-empty
    # or it returns nil. Exporting both sets means cliamp connects whether or
    # not config.toml is present, and both paths name the same server.
    set -lx NAVIDROME_URL $url
    set -lx NAVIDROME_USER $user
    set -lx NAVIDROME_PASSWORD $pass
    set -lx NAVIDROME_PASS $pass

    command cliamp $argv
end
