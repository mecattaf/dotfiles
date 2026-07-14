# annex_watcher.py — kitty window watcher for the Ctrl+B annex (dotfiles#50).
#
# Attached via `launch --watcher annex_watcher.py`. on_close is the SOLE reaper
# for the sidebar picker and also performs the file-open-in-new-window step.
#
# on_close fires whether the annex self-reaped (file chosen -> nvim :qa! ->
# session self-reaps -> child exits -> window closes) or was force-closed
# (Ctrl+B dismiss). In both cases:
#   1. REAP: annex-cmd kill <session> — idempotent; cleans the leak path where a
#      force-closed split left server-side nvim running (dotfiles#33). A no-op
#      after a self-reap.
#   2. OPEN: if the pick file holds a path (a file was selected), open it in a
#      NEW niri window as a VISIBLE, roamable `term-*` zmx session (ruling 4:
#      durable edit = real niri window; niri tiles it, the original reflows).
#      Empty/absent pick file = a plain dismiss (open nothing).

import os
import subprocess
import time
import uuid


def _name(prefix):
    return "%s-%s-%s" % (prefix, time.strftime("%H%M%S"), uuid.uuid4().hex[:6])


def on_close(boss, window, data):
    home = os.path.expanduser("~")
    annex_cmd = os.path.join(home, ".local", "bin", "annex-cmd")
    uv = {}
    try:
        uv = window.user_vars or {}
    except Exception:
        uv = {}

    # 1. Sole reaper (idempotent).
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

    # 2. Open the selected file in a new niri window.
    pick = uv.get("annex_pick")
    if not pick:
        return
    path = ""
    try:
        if os.path.exists(pick):
            with open(pick) as f:
                path = f.readline().strip()
    except Exception:
        path = ""
    try:
        if os.path.exists(pick):
            os.unlink(pick)
    except Exception:
        pass
    if not path:
        return

    directory = os.path.dirname(path) or home
    vsess = _name("term")
    try:
        boss.call_remote_control(
            None,
            (
                "launch",
                "--type=os-window",
                "--cwd",
                directory,
                "--",
                annex_cmd,
                "exec",
                vsess,
                "nvim",
                path,
            ),
        )
    except Exception:
        pass
