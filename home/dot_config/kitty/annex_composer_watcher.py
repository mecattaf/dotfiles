# annex_composer_watcher.py — kitty window watcher for the Option 2 fast-return
# Ctrl+G composer (dotfiles#49 follow-up).
#
# Attached via `launch --watcher annex_composer_watcher.py` from nvim-annex's
# ANNEX_FAST branch. Because that branch does NOT `--wait-for-child-to-exit`
# (fast-return: nvim-annex has already exited long before the user is done
# composing) and deliberately does NOT register nvim-annex's own
# `trap cleanup EXIT` (which would otherwise fire almost immediately and kill
# the composer out from under the user — see nvim-annex's ANNEX_FAST branch
# comments), THIS on_close callback is the SOLE reaper for the fast-return
# composer — mirroring annex_watcher.py's role for the Ctrl+B sidebar exactly.
#
# on_close fires whether the composer nvim self-reaped (delivered or
# dismissed -> :qa! -> zmx session self-reaps -> child exits -> window
# closes) or was force-closed (window killed with the compose still open).
# Idempotent, same guarantee as annex-cmd kill's own --force reap (dotfiles#33:
# the one leak path is a force-closed window with server-side nvim still
# running; `kill` is a safe no-op after a genuine self-reap).

import os
import subprocess


def on_close(boss, window, data):
    home = os.path.expanduser("~")
    annex_cmd = os.path.join(home, ".local", "bin", "annex-cmd")
    uv = {}
    try:
        uv = window.user_vars or {}
    except Exception:
        uv = {}

    # 1. Sole reaper (idempotent — safe no-op after a genuine self-reap).
    sess = uv.get("annex_session")
    if sess:
        try:
            subprocess.Popen(
                [annex_cmd, "kill", sess],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception:
            pass

    # 2. Clean up the scratch composer file nvim-annex mktemp'd for this
    # compose (seeded with the original draft, separate from the harness's
    # own — already truncated — tempfile; see nvim-annex's ANNEX_FAST branch).
    # Best-effort: a leftover scratch file is harmless clutter, never a leak
    # of a running process.
    composer_file = uv.get("annex_composer_file")
    if composer_file:
        try:
            if os.path.exists(composer_file):
                os.unlink(composer_file)
        except Exception:
            pass
