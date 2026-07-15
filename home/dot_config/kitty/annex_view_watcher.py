# annex_view_watcher.py — kitty window watcher for the Ctrl+SHIFT+O
# transcript viewer (annex_view.py).
#
# Attached via `launch --watcher annex_view_watcher.py` from annex_view.py's
# _act(). The viewer's payload (`claude --resume <sessionId>`, run through
# annex-cmd exec's `zmx attach`) is a genuinely long-lived interactive
# process — the whole point is that it sits there re-rendering the
# transcript for as long as the user wants to scroll it — so, exactly like
# annex_composer_watcher.py's role for the fast-return Ctrl+Shift+G composer,
# THIS on_close callback is the SOLE reaper for the viewer's zmx session.
#
# CLONE OF annex_composer_watcher.py's on_close, with the scratch-composer-
# file cleanup branch DROPPED: the viewer never mktemps a DRAFT file (it is
# READ-ONLY — it never sends text back, so there is no composer scratch file
# to ever clean up here; see annex_view.py's header).
#
# It DOES, however, clean up the throwaway TRANSCRIPT-SNAPSHOT jsonl that
# annex_view.py's _snapshot_transcript() copies the live session into before
# launch (the structural write-safety fix: the viewer resumes that copy,
# never the still-live original — see annex_view.py's _act()). That copy is
# single-use and has no other reader once this window closes, so it is
# reaped here exactly like annex_composer_watcher.py reaps its own scratch
# file: best-effort, a leftover is harmless clutter, never a leak of a
# running process.
#
# on_close fires whether the viewer self-reaped (user quit claude inside it
# -> zmx session self-reaps -> child exits -> window closes) or was
# force-closed (OS window killed with claude still running inside). Reaping
# via `annex-cmd kill` is IDEMPOTENT (dotfiles#33: the one leak path is a
# force-closed window with the server-side process still running; `kill` is
# a safe no-op after a genuine self-reap) — so this callback is safe to fire
# unconditionally on every close, including a self-reap that already beat it
# to the punch.

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

    # 2. Clean up the throwaway transcript-snapshot jsonl this viewer resumed
    # (see annex_view.py's _snapshot_transcript). Best-effort: a leftover
    # snapshot file is harmless clutter under projects/*/, never a leak of a
    # running process, and never the live original (which this never touches).
    snapshot = uv.get("annex_view_snapshot")
    if snapshot:
        try:
            if os.path.exists(snapshot):
                os.unlink(snapshot)
        except Exception:
            pass
