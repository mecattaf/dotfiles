# One zmx session universe per user, on every entry path. zmx uses
# $XDG_RUNTIME_DIR/zmx when that var is set and /tmp/zmx-$UID otherwise; entry
# paths differ (niri/login shells have XDG_RUNTIME_DIR, the kitten-ssh attach
# env and the session daemons' captured env don't), which silently split
# sessions across two socket dirs (found 2026-07-12: five desk-created
# sessions in /tmp/zmx-1000, one local spawn in /run/user/1000/zmx —
# invisible to each other's pickers). Canonical dir = /tmp/zmx-$UID: it's
# zmx's own fallback, so even an entry path that misses this export agrees.
# /run/user was rejected: systemd removes it when the user's last login
# session ends, which would strand running session daemons.
# The zmx scripts (new-terminal, zmx-resume, zmx-annotate) export the same
# default, and remote.fish pins it inside its ssh commands.
set -q ZMX_DIR; or set -gx ZMX_DIR /tmp/zmx-(id -u)
