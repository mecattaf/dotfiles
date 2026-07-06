function cliamp --wraps cliamp --description "cliamp with navidrome credentials from agenix"
    set -l creds /run/agenix/navidrome-credentials
    if test -r $creds
        set -lx NAVIDROME_USER (grep '^NAVIDROME_USER=' $creds | string replace 'NAVIDROME_USER=' '')
        set -lx NAVIDROME_PASSWORD (grep '^NAVIDROME_PASSWORD=' $creds | string replace 'NAVIDROME_PASSWORD=' '')
    end
    command cliamp $argv
end
