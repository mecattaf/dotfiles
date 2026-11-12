# greetd default_session for the physical seat (#734).
#
# greetd runs initial_session once per boot. After a greetd restart or a
# desktop exit it runs default_session, and restarts it whenever it exits.
# This guard starts Domicile there too, unless Domicile has already started
# MAX times within WINDOW seconds this boot: then it opens a rescue login
# shell on this VT instead of looping. VT2-6 getty autologin stays the
# independent rescue (Ctrl+Alt+F2).
#
# usage: domicile-greetd-guard SESSION RESCUE [RESCUE-ARGS...]
set -u
PATH=@coreutils@/bin:${PATH:-}

if [ "$#" -lt 2 ]; then
  echo "usage: domicile-greetd-guard SESSION RESCUE [RESCUE-ARGS...]" >&2
  exit 2
fi
session=$1
shift

max=${DOMICILE_GREETD_GUARD_MAX:-3}
window=${DOMICILE_GREETD_GUARD_WINDOW:-120}
state_dir=${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/domicile
state=$state_dir/greetd-starts
boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)
now=$(date +%s)

# Keep only this boot's starts inside the window.
recent=()
if [ -r "$state" ]; then
  while read -r b t; do
    if [ "$b" = "$boot" ] && [[ "$t" =~ ^[0-9]+$ ]] && [ $((now - t)) -lt "$window" ]; then
      recent+=("$b $t")
    fi
  done <"$state"
fi

if [ "${#recent[@]}" -ge "$max" ]; then
  echo "Domicile started ${#recent[@]} times in the last ${window}s; not starting it again yet." >&2
  echo "This is a rescue shell. Read: journalctl -t domicile-session -b; journalctl -u greetd -b" >&2
  echo "Type 'domicile' to retry now, or exit: after ${window}s greetd starts Domicile again." >&2
  exec "$@"
fi

mkdir -p "$state_dir" 2>/dev/null || true
{
  for line in "${recent[@]}"; do printf '%s\n' "$line"; done
  printf '%s %s\n' "$boot" "$now"
} >"$state.tmp" 2>/dev/null && mv -f "$state.tmp" "$state" 2>/dev/null || true
exec "$session"
