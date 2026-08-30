function navidrome-scan --description "Trigger a Navidrome library rescan and watch it finish"
    # Run this after a beets pass. It is the ONLY thing that reindexes the
    # library now: hosts/nas/media.nix sets Scanner.Schedule = "0" and
    # Scanner.ScanOnStartup = false, because ~34k tracks that change about
    # once a year do not justify re-walking a parked HDD on every service
    # start. Nothing rescans unless asked.
    #
    # --full rescans every file regardless of mtime, which is what a beets run
    # that rewrote tags in place actually needs; the default quick scan keys off
    # modification time and can miss tag-only edits.
    set -l full false
    if contains -- --full $argv
        set full true
    end

    set -l creds /run/agenix/navidrome-credentials
    if not test -r $creds
        echo "navidrome-scan: $creds unreadable (coordinator only)" >&2
        return 1
    end
    set -l user (grep '^NAVIDROME_USER=' $creds | string replace 'NAVIDROME_USER=' '')
    set -l pass (grep '^NAVIDROME_PASSWORD=' $creds | string replace 'NAVIDROME_PASSWORD=' '')

    set -l url $NAVIDROME_URL
    test -n "$url"; or set url http://coordinator.tail8dd1.ts.net:4533
    set -l auth "u=$user&p=$pass&v=1.16.1&c=cliamp&f=json"

    # First contact wakes the relay and the sleeping NAS service; the HDD may
    # also have to spin up, so allow a generous timeout here.
    echo "Requesting"(test $full = true; and echo " full"; or echo " quick")" scan on $url ..."
    curl -s -m 120 "$url/rest/startScan?$auth&fullScan=$full" >/dev/null; or begin
        echo "navidrome-scan: could not reach Navidrome at $url" >&2
        return 1
    end

    while true
        set -l json (curl -s -m 120 "$url/rest/getScanStatus?$auth")
        set -l scanning (echo $json | string match -rq '"scanning":true'; and echo yes; or echo no)
        set -l count (echo $json | string replace -rf '.*"count":([0-9]+).*' '$1')
        if test "$scanning" = no
            echo "Scan complete — $count tracks indexed."
            return 0
        end
        echo -n "  scanning... $count tracks so far\r"
        sleep 5
    end
end
