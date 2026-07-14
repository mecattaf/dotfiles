# annex_toggle.py — Ctrl+B / Ctrl+Shift+B universal sidebar picker (dotfiles#50).
#
# A no-UI kitten mapped in kitty.conf. main() is a no-op; all work happens in
# handle_result(), which runs IN the kitty process with boss/window access
# (@result_handler(no_ui=True) => no overlay window flashes, instant).
#
# Behavior in the focused window (order matters):
#   1. DISMISS-SELF: if the focused window IS the annex (var:annex=1), close it
#      (fires annex_watcher.py on_close -> reap). Checked first because the annex
#      payload is itself nvim, so "press again to dismiss" must win over
#      pass-through.
#   2. PASS-THROUGH: else, if a (zmx-wrapped) nvim editor is focused, forward the
#      raw key to the app — Ctrl+B -> \x02 (NvimTreeFocus), Ctrl+Shift+B ->
#      \x1b[66;5u (NvimTreeToggle, preserving today's kitty.conf behavior).
#      Detection scans the whole `zmx attach … nvim …` argv (see _is_nvim): the
#      foreground process is always the zmx client, never a bare nvim.
#   3. DISMISS: else, if an annex split (var:annex=1) is open elsewhere in this
#      tab, close it (fires annex_watcher.py on_close -> reap).
#   4. OPEN: else, launch a hidden, self-terminating RIGHT split (~25 cols)
#      running nvim-tree as the picker, with a watcher + user-vars for reaping
#      and file-open signaling.
#
# Ctrl+B AND Ctrl+Shift+B both toggle outside nvim (Tom thinks of them as one
# toggle); both pass through inside nvim. Ctrl+B inside Claude Code's TUI is
# SHADOWED (the annex toggle wins) — accepted, recorded on the issue.

import os
import re
import time
import uuid

from kittens.tui.handler import result_handler

_NVIM_RE = re.compile(r"^n?vim$")


def main(args):
    # All work is done in handle_result; main only forwards the chord arg.
    return args


def _is_annex(window):
    # The annex split stamps var:annex=1 at launch. Checked BEFORE nvim
    # pass-through because the annex payload is ITSELF nvim (nvim-tree): without
    # this, pressing the toggle while focused in the annex would pass through to
    # its nvim instead of honoring the "press again = dismiss" contract.
    try:
        return (window.user_vars or {}).get("annex") == "1"
    except Exception:
        return False


def _is_nvim(window):
    # PRIMARY signal: the per-window user-var `nvim=1` that nvim itself stamps on
    # VimEnter via a kitty SetUserVar OSC (see nvim init.lua kitty_annex_mark).
    # This is the ONLY reliable detector when nvim is launched by hand inside a
    # zmx session, because kitty's foreground_processes then reports the
    # `zmx attach <sess> fish` CLIENT — nvim runs server-side, invisible to kitty
    # (verified live). The OSC rides nvim's stdout through zmx to this window.
    try:
        if (window.user_vars or {}).get("nvim") == "1":
            return True
    except Exception:
        pass
    # FALLBACK: scan the visible foreground argv. Catches the windows this feature
    # opens as `zmx attach <sess> nvim <file>` (the 'nvim' token is in the client
    # argv) even before that nvim's VimEnter stamps the user-var — closes the
    # startup race. A file literally named 'vim'/'nvim' is a harmless false
    # positive (worst case: a pass-through where a toggle was wanted).
    try:
        for p in window.child.foreground_processes:
            for tok in (p.get("cmdline") or []):
                if tok and _NVIM_RE.match(os.path.basename(tok)):
                    return True
    except Exception:
        pass
    return False


def _annex_window_in_tab(window, boss):
    try:
        tab = window.tabref() if hasattr(window, "tabref") else None
    except Exception:
        tab = None
    windows = list(tab) if tab is not None else list(boss.all_windows)
    for w in windows:
        try:
            if (w.user_vars or {}).get("annex") == "1":
                return w
        except Exception:
            continue
    return None


def _name(prefix):
    # Self-contained + unique per press (mirrors annex-cmd name / new-terminal):
    # no fork, no network — instant in the interactive path.
    return "%s-%s-%s" % (prefix, time.strftime("%H%M%S"), uuid.uuid4().hex[:6])


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    which = args[1] if len(args) > 1 else "b"
    w = boss.window_id_map.get(target_window_id)
    if w is None:
        return

    # 1. Focused window IS the annex -> dismiss it (its watcher on_close reaps).
    #    MUST precede the nvim pass-through: the annex payload is itself nvim, so
    #    otherwise "press again to dismiss" would pass through instead.
    if _is_annex(w):
        boss.mark_window_for_close(w)  # accepts a Window; close_window() does not
        return

    # 2. Pass-through when a (zmx-wrapped) nvim editor is focused.
    if _is_nvim(w):
        if which == "shift":
            w.write_to_child(b"\x1b[66;5u")  # Ctrl+Shift+B -> NvimTreeToggle
        else:
            w.write_to_child(b"\x02")  # Ctrl+B -> NvimTreeFocus
        return

    # 3. Dismiss an annex open elsewhere in this tab (its watcher on_close reaps).
    existing = _annex_window_in_tab(w, boss)
    if existing is not None:
        # mark_window_for_close(window) is the correct API: Boss.close_window()
        # takes NO argument (always closes window_for_dispatch) and would raise
        # TypeError, and the old bare-except fell back to a GLOBAL var:annex=1
        # match that could close annexes in OTHER tabs. This is tab-scoped.
        boss.mark_window_for_close(existing)
        return

    # 3. Open a fresh annex sized to ~25 columns on the RIGHT.
    home = os.path.expanduser("~")
    try:
        cols = int(w.screen.columns)
    except Exception:
        cols = 120
    bias = int(round(25.0 / cols * 100.0)) if cols else 20
    bias = max(5, min(95, bias))

    sess = _name("annex")
    zmx_dir = os.environ.get("ZMX_DIR", "/tmp/zmx-%d" % os.getuid())
    pick = os.path.join(zmx_dir, "annex-pick-" + sess)
    annex_cmd = os.path.join(home, ".local", "bin", "annex-cmd")
    pick_lua = os.path.join(home, ".local", "bin", "annex-pick.lua")

    boss.call_remote_control(
        w,
        (
            "launch",
            "--type=window",
            "--location=vsplit",
            "--bias",
            str(bias),
            "--cwd=current",
            "--watcher",
            "annex_watcher.py",
            "--var",
            "annex=1",
            "--var",
            "annex_session=" + sess,
            "--var",
            "annex_pick=" + pick,
            "--env",
            "ANNEX_PICK=" + pick,
            "--",
            annex_cmd,
            "exec",
            sess,
            "nvim",
            "-c",
            "luafile " + pick_lua,
        ),
    )
