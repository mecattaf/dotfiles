#!/bin/sh
# Fixture test for the crm and mail wrappers (home/dot_local/bin): the default
# comes from cli.json, an explicit environment wins, and a missing cli.json
# keeps the CLI's own config. A fake CLI reports what it was given.
# Usage: test.sh <crm wrapper> <mail wrapper>
set -eu
crm=$1 mail=$2
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

home="$root/home"
bin="$home/.local/state/agency/communications/cli/bin"
cfgdir="$home/.config/agency/communications"
mkdir -p "$bin" "$cfgdir/tokens" "$root/alt"
for n in crm mail; do
  cat > "$bin/$n" <<'FAKE'
#!/bin/sh
printf 'CRM_URL=%s\nCRM_TOKEN_FILE=%s\nEMAIL_URL=%s\nEMAIL_TOKEN=%s\nARGS=%s\n' \
  "${CRM_URL-<unset>}" "${CRM_TOKEN_FILE-<unset>}" "${EMAIL_URL-<unset>}" "${EMAIL_TOKEN-<unset>}" "$*"
FAKE
  chmod +x "$bin/$n"
done
printf 'fixture-mail-token\n' > "$cfgdir/tokens/mail"
printf 'fixture-crm-token\n' > "$cfgdir/tokens/crm"
printf 'alt-mail-token\n' > "$root/alt/mail"

run() { env -i HOME="$home" PATH="$PATH" "$@"; }
has() { printf '%s\n' "$1" | grep -qxF -- "$2" || fail "$3: expected '$2' in: $1"; }

# 1. No cli.json: nothing is set, today's behaviour.
out=$(run "$crm" status); has "$out" "CRM_URL=<unset>" "absent crm"
has "$out" "ARGS=status" "absent crm args"
out=$(run "$mail" inbox); has "$out" "EMAIL_URL=<unset>" "absent mail"
has "$out" "EMAIL_TOKEN=<unset>" "absent mail token"

# 2. cli.json with a url and the default token dir (trailing slash dropped).
printf '{"url":"http://svc.example.org:9/"}\n' > "$cfgdir/cli.json"
out=$(run "$crm" status --json); has "$out" "CRM_URL=http://svc.example.org:9/crm" "crm url"
has "$out" "CRM_TOKEN_FILE=$cfgdir/tokens/crm" "crm token file"
has "$out" "ARGS=status --json" "crm args"
printf '%s\n' "$out" | grep -q fixture-crm-token && fail "crm token value leaked into the env"
out=$(run "$mail" inbox); has "$out" "EMAIL_URL=http://svc.example.org:9/mail" "mail url"
has "$out" "EMAIL_TOKEN=fixture-mail-token" "mail token"

# 3. token_dir with a ~/ prefix.
printf '{"url":"https://svc.example.org","token_dir":"~/alt"}\n' > "$cfgdir/cli.json"
mkdir -p "$home/alt"; cp "$root/alt/mail" "$home/alt/mail"
out=$(run "$crm" status); has "$out" "CRM_TOKEN_FILE=$home/alt/crm" "crm ~ token dir"
out=$(run "$mail" status); has "$out" "EMAIL_TOKEN=alt-mail-token" "mail ~ token dir"

# 4. An explicit environment wins, untouched.
out=$(run CRM_URL=https://other.example.net/crm "$crm" status)
has "$out" "CRM_URL=https://other.example.net/crm" "crm override"
has "$out" "CRM_TOKEN_FILE=<unset>" "crm override token"
out=$(run CRM_TOKEN_FILE=/x/tok "$crm" status); has "$out" "CRM_URL=<unset>" "crm token-file override"
out=$(run EMAIL_URL=https://other.example.net "$mail" status)
has "$out" "EMAIL_URL=https://other.example.net" "mail override"
has "$out" "EMAIL_TOKEN=<unset>" "mail override token"
out=$(run EMAIL_TOKEN=given "$mail" status); has "$out" "EMAIL_URL=<unset>" "mail token override"

# 5. COMMS_CONFIG selects another client config.
printf '{"url":"https://alt.example.com","token_dir":"%s"}\n' "$root/alt" > "$root/alt.json"
out=$(run COMMS_CONFIG="$root/alt.json" "$mail" status)
has "$out" "EMAIL_URL=https://alt.example.com/mail" "COMMS_CONFIG url"
has "$out" "EMAIL_TOKEN=alt-mail-token" "COMMS_CONFIG token"

# 6. A cli.json without a usable url, or a missing mail token, stops with 3.
printf '{"url":"ftp://x"}\n' > "$cfgdir/cli.json"
rc=0; run "$crm" status >/dev/null 2>&1 || rc=$?; [ "$rc" = 3 ] || fail "crm bad url rc=$rc"
rc=0; run "$mail" status >/dev/null 2>&1 || rc=$?; [ "$rc" = 3 ] || fail "mail bad url rc=$rc"
printf '{"url":"https://svc.example.org","token_dir":"%s/none"}\n' "$root" > "$cfgdir/cli.json"
rc=0; run "$mail" status >/dev/null 2>&1 || rc=$?; [ "$rc" = 3 ] || fail "mail missing token rc=$rc"

echo "communications-cli: ok"
