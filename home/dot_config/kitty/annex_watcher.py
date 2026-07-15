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

    # Harness niri window id = the focused niri window right now. The Ctrl+B
    # sidebar was an in-kitty vsplit INSIDE the harness's own kitty os-window, so
    # closing it returns focus to the harness within that same niri window —
    # `niri msg` reports it as focused here. Captured so annex-place can reap the
    # file view when the harness chat is later closed (the "file view dies with
    # its parent Claude chat" contract). Best-effort: empty on any failure, in
    # which case annex-place just skips the reap and still does the geometry.
    # One niri query yields both handles annex-place needs:
    #   harness_id — the reap parent (see above).
    #   fbase      — the file-view BASELINE: highest existing annex-fileview id, so
    #                annex-place acts only on the window we launch below (id>fbase),
    #                never a lingering earlier file view. Snapshot BEFORE the launch.
    harness_id = ""
    fbase = 0
    try:
        out = subprocess.check_output(
            ["niri", "msg", "-j", "windows"],
            stderr=subprocess.DEVNULL,
            timeout=1,
        )
        import json as _json

        for w in _json.loads(out):
            if w.get("is_focused"):
                harness_id = str(w.get("id", ""))
            if w.get("app_id") == "annex-fileview":
                fbase = max(fbase, w.get("id", 0))
    except Exception:
        harness_id = ""
        fbase = 0

    vsess = _name("term")
    try:
        boss.call_remote_control(
            None,
            (
                "launch",
                "--type=os-window",
                # Distinguishing niri app_id so annex-place (and any future
                # niri/piri rule) can match this window; kitty maps
                # --os-window-class to the Wayland app_id.
                "--os-window-class",
                "annex-fileview",
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

    # Fire the niri-native placer: right-half split beside the harness, then reap
    # this file view when the harness (harness_id) closes. Detached + silenced so
    # it outlives this watcher callback and never blocks kitty.
    try:
        place = os.path.join(home, ".local", "bin", "annex-place")
        subprocess.Popen(
            [place, "solo", "annex-fileview", str(fbase)]
            + ([harness_id] if harness_id else []),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception:
        pass
