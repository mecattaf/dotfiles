#!/usr/bin/env bash
# A login bash (home/dot_bash_profile) and every fish
# (fish/conf.d/hm-session-vars.fish) read Home Manager's session variables:
# the per-user profile first, then ~/.nix-profile. Fixtures only: the copies
# under test have the per-user root rewritten into a temporary directory.
set -euo pipefail

: "${BASH_PROFILE:?}" "${FISH_READER:?}"

fail() {
  echo "hm-session-vars: $*" >&2
  exit 1
}

root=$(mktemp -d)
export HOME="$root/home" USER=fixture
export XDG_CONFIG_HOME="$root/config" XDG_DATA_HOME="$root/data" XDG_CACHE_HOME="$root/cache"
unset __HM_SESS_VARS_SOURCED SCHEDULED_INBOX HM_FIXTURE_HOME HM_FIXTURE_SHELL XDG_RUNTIME_DIR
mkdir -p "$HOME" "$XDG_CONFIG_HOME/fish/conf.d" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

per_user="$root/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
fallback="$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
mkdir -p "$(dirname "$per_user")" "$(dirname "$fallback")"

rewrite() {
  sed "s|/etc/profiles/per-user/|$root/profiles/per-user/|g" "$1" >"$2"
  grep -q "$root/profiles/per-user/" "$2" || fail "$1 no longer reads the per-user profile"
}
rewrite "$BASH_PROFILE" "$HOME/.bash_profile"
rewrite "$FISH_READER" "$XDG_CONFIG_HOME/fish/conf.d/hm-session-vars.fish"

# The shape Home Manager writes, with one value only a shell can read. The
# PATH entry is a marker, so the host's own PATH cannot mask the result.
vars() {
  cat <<EOF
# Only source this once.
if [ -n "\${__HM_SESS_VARS_SOURCED-}" ]; then return; fi
export __HM_SESS_VARS_SOURCED=1

export HM_FIXTURE_HOME="\$HOME/inbox"
export HM_FIXTURE_SHELL="\${XDG_RUNTIME_DIR:-/run}/x"
export SCHEDULED_INBOX="$1"
export PATH="/hm-fixture/bin\${PATH:+:}\$PATH"
EOF
}
vars /per-user/inbox >"$per_user"
vars /fallback/inbox >"$fallback"

probe='printf "%s|%s|%s|" "${SCHEDULED_INBOX-}" "${HM_FIXTURE_HOME-}" "${HM_FIXTURE_SHELL-}"; case ":$PATH:" in *":/hm-fixture/bin:"*) printf path ;; esac'
fish_probe='printf "%s|%s|%s|" "$SCHEDULED_INBOX" "$HM_FIXTURE_HOME" "$HM_FIXTURE_SHELL"; contains -- /hm-fixture/bin $PATH; and printf path; functions -q __hm_session_vars; and printf leaked; true'

expect() {
  local name=$1 want=$2 have=$3
  [ "$have" = "$want" ] || fail "$name: want '$want', have '$have'"
}

expect "bash -l, per-user first" "/per-user/inbox|$HOME/inbox|/run/x|path" "$(bash -lc "$probe")"
# fish skips PATH and the value it cannot expand.
expect "fish -c, per-user first" "/per-user/inbox|$HOME/inbox||" "$(fish -c "$fish_probe")"
expect "fish -c is silent" "" "$(fish -c true 2>&1)"

rm "$per_user"
expect "bash -l, fallback" "/fallback/inbox|$HOME/inbox|/run/x|path" "$(bash -lc "$probe")"
expect "fish -c, fallback" "/fallback/inbox|$HOME/inbox||" "$(fish -c "$fish_probe")"

# A session that already read the file keeps what it has.
expect "bash -l, guarded" "|||" "$(__HM_SESS_VARS_SOURCED=1 bash -lc "$probe")"
expect "fish -c, guarded" "|||" "$(__HM_SESS_VARS_SOURCED=1 fish -c "$fish_probe")"

rm "$fallback"
expect "bash -l, no file" "|||" "$(bash -lc "$probe")"
expect "fish -c, no file" "|||" "$(fish -c "$fish_probe")"

echo "hm-session-vars: ok"
