#!/usr/bin/env bash
# Print each failure-marker episode once per user. The root-owned marker files
# remain available for inspection, while opening another interactive shell does
# not turn one incident into an indefinitely repeated warning.
set -euo pipefail

marker_dir="${1:?usage: failure-marker-report <marker-dir>}"
[ -d "$marker_dir" ] || exit 0

state_home="${XDG_STATE_HOME:-${HOME:?HOME must be set}/.local/state}"
state_dir="$state_home/fleet-deploy"
seen_file="$state_dir/failure-episodes.seen"

umask 077
install -d -m 0700 "$state_dir"
[ -e "$seen_file" ] && first_run=0 || first_run=1
touch "$seen_file"
chmod 0600 "$seen_file"

# Two terminals can start together. Only the first one gets the episode; the
# second observes the receipt written under this lock and stays quiet.
exec 9>"$state_dir/failure-episodes.lock"
flock 9

new_digests="$(mktemp "$state_dir/.failure-episodes.new.XXXXXX")"
merged_digests="$(mktemp "$state_dir/.failure-episodes.merged.XXXXXX")"
trap 'rm -f -- "$new_digests" "$merged_digests"' EXIT

shopt -s nullglob
for marker in "$marker_dir"/*; do
  [ -f "$marker" ] || continue
  name="$(basename -- "$marker")"
  if ! digest="$({ printf '%s\0' "$name"; cat -- "$marker"; } | sha256sum | cut -d ' ' -f 1)"; then
    continue
  fi
  if grep -Fqx -- "$digest" "$seen_file"; then
    continue
  fi

  first_line="$(head -n 1 -- "$marker" 2>/dev/null || true)"
  [ -n "$first_line" ] || first_line="$name (empty marker)"
  # The first run happens immediately after deploying this feature. Markers
  # already present then have already been shown by the old shell hook, so
  # baseline them silently instead of replaying yesterday's warning once more.
  if [ "$first_run" -eq 0 ]; then
    printf '%s\n' "$first_line"
  fi
  printf '%s\n' "$digest" >>"$new_digests"
done

if [ -s "$new_digests" ]; then
  {
    cat -- "$seen_file"
    cat -- "$new_digests"
  } | sort -u >"$merged_digests"
  chmod 0600 "$merged_digests"
  mv -f -- "$merged_digests" "$seen_file"
fi
