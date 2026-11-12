# greetd sessions for the physical seat (#734).
#
# greetd starts initial_session only when its runfile is absent. The client
# keeps that runfile in greetd's RuntimeDirectory, which systemd removes when
# greetd stops, so every greetd start runs initial_session: a user-class
# logind session. initial_session runs this guard in start mode; it starts
# Domicile unless Domicile has already started MAX times within WINDOW
# seconds this boot: then it opens a rescue login shell on this VT instead.
#
# When that session exits, greetd runs default_session, a greeter-class
# session. There this guard runs in --handoff mode: under the limit it exits
# without starting anything, greetd exits ("greeter exited without creating a
# session", status 0), systemd restarts it (Restart=on-success) and the new
# greetd runs initial_session again. Over the limit it opens the rescue shell.
# VT2-6 getty autologin stays the independent rescue (Ctrl+Alt+F2).
#
# usage: domicile-greetd-guard SESSION RESCUE [RESCUE-ARGS...]
#        domicile-greetd-guard --handoff RESCUE [RESCUE-ARGS...]
set -u
PATH=@coreutils@/bin:${PATH:-}

usage() {
  echo "usage: domicile-greetd-guard SESSION RESCUE [RESCUE-ARGS...]" >&2
  echo "       domicile-greetd-guard --handoff RESCUE [RESCUE-ARGS...]" >&2
  exit 2
}
handoff=0
if [ "${1:-}" = --handoff ]; then
  handoff=1
  shift
  [ "$#" -ge 1 ] || usage
else
  [ "$#" -ge 2 ] || usage
  session=$1
  shift
fi

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

if [ "$handoff" = 1 ]; then
  # Hand the seat back to greetd: its restart starts a user-class session.
  echo "Domicile session ended; restarting greetd to start it again." >&2
  exit 0
fi

mkdir -p "$state_dir" 2>/dev/null || true
{
  for line in "${recent[@]}"; do printf '%s\n' "$line"; done
  printf '%s %s\n' "$boot" "$now"
} >"$state.tmp" 2>/dev/null && mv -f "$state.tmp" "$state" 2>/dev/null || true
exec "$session"
