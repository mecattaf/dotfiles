# annex_ctrlg.py — Ctrl+SHIFT+G kitty-level composer, Option 3 (an ALTERNATIVE
# to — no longer a replacement of — the $EDITOR round trip for the Ctrl+G
# composer, dotfiles#49 follow-up #2).
#
# DEMOTED from plain Ctrl+G to Ctrl+Shift+G (Tom 2026-07-15). The two composers
# are now interchangeable, split by chord: plain Ctrl+G is left UNBOUND at the
# kitty layer and reaches the harness natively (Claude's/pi's own
# Ctrl+G->$EDITOR = nvim-annex, blocking); Ctrl+Shift+G is this kitten. See the
# PLACEHOLDER LIMITATION note below for why the split exists.
#
# PLACEHOLDER LIMITATION (the reason plain Ctrl+G was freed): this kitten
# reconstructs the draft by SCREEN-SCRAPING the visible input box (Window
# .as_text() -> parse_draft) and re-delivers it via `kitten @ send-text`. Claude
# Code does not render pasted text or clipboard images inline — it shows only a
# placeholder TOKEN ("[Pasted text #N +M lines]", "[Image #N]") that indexes
# content held in its own memory. A screen-scrape sees only the token; send-text
# re-types the token as literal characters, which Claude does NOT re-associate
# with the stored bytes -> the paste/image content is LOST. This is structural,
# not a bug here: ONLY an in-place edit of Claude's OWN tempfile (the native
# Ctrl+G->nvim-annex path) round-trips the tokens so Claude re-maps them. Use
# plain Ctrl+G for drafts containing pastes/images; Ctrl+Shift+G for quick
# plain-text edits with no alt-screen blank.
#
# A no-UI kitten mapped in kitty.conf, modeled 1:1 on annex_toggle.py (the
# Ctrl+B sidebar picker): main() is a no-op, all work happens in
# handle_result() running IN the kitty process with boss/window access
# (@result_handler(no_ui=True) => instant, no overlay window).
#
# WHY THIS EXISTS (vs. the already-shipped Option 1/2 $EDITOR-based composer,
# nvim-annex + claude.fish/_annex_editor.fish): those mechanisms depend on
# Claude/pi's OWN Ctrl+G keybinding firing spawnSync($EDITOR) — which
# unconditionally leaves the alt-screen for however long the editor takes
# (Option 2/ANNEX_FAST shrinks that to a sub-second blink, but can't remove
# it; see nvim-annex's header). Option 3 removes the blink entirely by never
# letting the keypress reach Claude/pi at all: kitty's own keymap intercepts
# Ctrl+G FIRST, scrapes the harness's visible draft straight off the screen
# (get-text-equivalent, in-process via Window.as_text()), and opens the SAME
# fast-return send-text composer (annex_composer_watcher.py +
# annex-deliver.lua, REUSED UNCHANGED) directly via call_remote_control —
# Claude/pi's internal $EDITOR handling is bypassed, not merely mirrored.
#
# SHADOW (narrow, since the demotion): `map ctrl+shift+g kitten annex_ctrlg.py`
# makes kitty the sole arbiter of Ctrl+SHIFT+G only — a chord nothing else binds
# in nvim/shell/fzf/bash. Plain Ctrl+G is NO LONGER touched by this kitten, so
# it reaches every program (including Claude's/pi's native Ctrl+G->$EDITOR)
# exactly as if this file did not exist. The non-harness fallback therefore
# SWALLOWS Ctrl+Shift+G (emitting nothing) rather than forwarding 0x07 — see
# handle_result: a stray BEL on a Ctrl+SHIFT+G press would be a spurious
# reverse-search abort / nvim bell, whereas the old plain-Ctrl+G shadow could
# safely forward 0x07 because Ctrl+G is meaningful everywhere.
#
# FAIL-SAFE ORDERING (mirrors nvim-annex's ANNEX_FAST branch: "launch first,
# truncate the harness box only on success", nvim-annex:130-136): the
# composer is remote-control-launched BEFORE the harness's own visible input
# box is touched. If the launch fails for any reason (remote control down,
# mktemp failure, ...) the harness box is untouched and the OUTER exception
# handler forwards the raw Ctrl+G byte (0x07) to the harness itself — so
# Claude's/pi's native Ctrl+G->$EDITOR path (nvim-annex, still scoped via
# claude.fish/_annex_editor.fish, UNTOUCHED by this feature) fires exactly as
# if this kitten didn't exist, reading its OWN unmolested tempfile. Only once
# the launch is CONFIRMED (call_remote_control raises on failure — see
# kitty's boss.py) do we clear the harness's visible draft, because by then
# it is durably captured in the composer's scratch file.
#
# STRUCTURE: harness-detection, draft-parsing, clear-sequence sizing, and
# launch-argv construction are all PURE functions (plain strings/lists in,
# plain values out) so they're unit-testable without a live kitty boss — see
# the module docstring split below. The kitty-boss glue (_act, handle_result)
# is the only impure part, and is intentionally thin.
#
# UNVERIFIED, CALL OUT BEFORE RELYING ON BLIND (recorded per the live probe
# that informed this file — no live keypress was ever sent to a real kitty
# during development, per the task's constraints):
#   * Ctrl+U (0x15) as the harness input-clear keystroke is a convention-based
#     guess (emacs-style kill-to-start-of-line), NOT confirmed against this
#     Claude Code build. If it's unbound, the code below falls back to a
#     deterministic N-backspace (0x7f) sequence, verified via a live
#     re-capture in between — see _clear_harness_input.
#   * No live "pi" harness process was ever observed; its argv0/cmdline shape
#     is assumed (by this repo's own convention, mirrored from nvim-annex) to
#     match plain `pi`, same as `claude`.
#   * No non-empty MULTI-LINE draft was ever captured live, so parse_draft's
#     multi-line branch is defensive/inferred, not empirically verified.
# A REQUIRED live single-keystroke smoke test is spelled out in this feature's
# final report — do not consider Option 3 "shipped" until that's been run by
# a human.

import os
import re
import subprocess
import tempfile
import time
import uuid

from kittens.tui.handler import result_handler

_HARNESS_RE = re.compile(r"^(claude|pi)$")

_BORDER_CHAR = "─"  # ─
_PROMPT_CHAR = "❯"  # ❯
_NBSP = "\u00a0"  # non-breaking space (U+00A0) — kitty's empty-input-box filler
_MIN_BORDER_LEN = 10  # fallback threshold when `columns` is 0/unavailable


def main(args):
    # All work is done in handle_result; main only forwards the (unused) args.
    return args


# ─────────────────────────── pure functions ────────────────────────────────
# Everything below takes plain inputs (strings/lists/dicts) and returns plain
# outputs — no boss/window objects — so it can be exercised with fixtures.


def is_harness_cmdline(foreground_processes):
    """Pure. Scan kitty's Child.foreground_processes shape
    (list of {'pid':.., 'cmdline': [...], 'cwd':..} dicts) for a claude/pi
    harness anywhere in the list. Live-verified (probe): kitty reports
    MULTIPLE simultaneous foreground processes for a real claude window
    (claude itself + wl-copy clipboard-helper children it spawns) — so this
    scans every entry, not just index 0."""
    try:
        for p in foreground_processes or ():
            for tok in (p.get("cmdline") or ()):
                if tok and _HARNESS_RE.match(os.path.basename(tok)):
                    return True
    except Exception:
        pass
    return False


def _is_border_line(line, columns):
    """Pure. A box-border line is made ENTIRELY of U+2500 ('─'). Prefer an
    exact `columns`-length match (the real capture showed both borders at
    exactly the window's reported column count — 220 chars for 220 columns);
    fall back to 'long run of only U+2500' when columns is 0/unavailable, so
    an ASCII '---' markdown divider (hyphens, not U+2500) can never be
    mistaken for the real box border."""
    if not line:
        return False
    if columns:
        return len(line) == columns and line.count(_BORDER_CHAR) == columns
    stripped = line.rstrip()
    return len(stripped) >= _MIN_BORDER_LEN and set(stripped) == {_BORDER_CHAR}


def parse_draft(text, columns):
    """Pure. Implements the probe's draft_parse_recipe against a raw
    get-text/as_text() screen capture:
      1. Scan bottom-up for the input box's U+2500 bottom border.
      2. Scan further up for the matching top border.
      3. The line(s) strictly between them are the draft. Strip the leading
         '❯' and exactly one separator char from the first such line: NBSP
         (with nothing else non-whitespace following) => empty draft; a
         plain space followed by real content => that content, right-
         trimmed of get-text's fixed-width padding.
    Returns "" when: no box found, no '❯' on the draft line, or an
    NBSP-only (truly empty) draft. Multi-line handling (more than one
    content line between the borders) is DEFENSIVE/UNVERIFIED — no live
    multi-line draft was ever captured to confirm kitty's wrapping shape."""
    if not text:
        return ""
    lines = text.split("\n")

    bottom_idx = None
    for i in range(len(lines) - 1, -1, -1):
        if _is_border_line(lines[i], columns):
            bottom_idx = i
            break
    if bottom_idx is None or bottom_idx == 0:
        return ""

    top_idx = None
    for i in range(bottom_idx - 1, -1, -1):
        if _is_border_line(lines[i], columns):
            top_idx = i
            break
    if top_idx is not None:
        content = lines[top_idx + 1 : bottom_idx]
    else:
        # Defensive: no top border found (unexpected) — assume single-line.
        content = lines[bottom_idx - 1 : bottom_idx]
    if not content:
        return ""

    first = content[0]
    idx = first.find(_PROMPT_CHAR)
    if idx == -1:
        return ""
    rest = first[idx + 1 :]
    if not rest:
        first_draft = ""
    else:
        sep, body = rest[0], rest[1:]
        if sep == _NBSP and body.strip() == "":
            first_draft = ""
        else:
            first_draft = body.rstrip()

    if len(content) == 1:
        return first_draft
    return "\n".join([first_draft] + [l.rstrip() for l in content[1:]])


def backspace_count(draft):
    """Pure. N backspaces to clear `draft`, biased up by +2 (probe's
    documented asymmetry: overshoot is a harmless no-op past an empty input
    in virtually every text-input implementation; undershoot leaves a stale
    fragment that a subsequent write would append onto and submit garbled)."""
    return len(draft) + 2


def build_composer_argv(
    annex_cmd, deliver_lua, sess, composer_file,
    harness_window_id, harness_listen_on, harness_host,
):
    """Pure. The exact `launch` remote-control argv (reuse-map §1), sourced
    from the FOCUSED harness window rather than an inherited shell env (this
    kitten runs inside the same kitty process as that window, so there is no
    subprocess/env-inheritance step to do — unlike nvim-annex, which reads
    its OWN $KITTY_WINDOW_ID/$KITTY_LISTEN_ON because it runs as an external
    process). Consumed unchanged by annex_composer_watcher.py (--var
    annex_session/annex_composer_file) and annex-deliver.lua (--env
    KITTY_HARNESS_*) — see this file's header."""
    return (
        "launch",
        "--type=os-window",
        "--cwd=current",
        "--watcher",
        "annex_composer_watcher.py",
        "--var",
        "annex_session=" + sess,
        "--var",
        "annex_composer_file=" + composer_file,
        "--env",
        "KITTY_HARNESS_WINDOW_ID=" + str(harness_window_id),
        "--env",
        "KITTY_HARNESS_LISTEN_ON=" + (harness_listen_on or ""),
        "--env",
        "KITTY_HARNESS_HOST=" + harness_host,
        "--",
        annex_cmd,
        "exec",
        sess,
        "nvim",
        "-c",
        "luafile " + deliver_lua,
        composer_file,
    )


def _name(prefix):
    # Copied verbatim from annex_toggle.py — self-contained + unique per
    # press (mirrors annex-cmd name / new-terminal): no fork, no network.
    return "%s-%s-%s" % (prefix, time.strftime("%H%M%S"), uuid.uuid4().hex[:6])


# ─────────────────────────── kitty-boss glue ───────────────────────────────


def _is_harness(window):
    try:
        return is_harness_cmdline(window.child.foreground_processes)
    except Exception:
        return False


def _clear_harness_input(w, draft, columns):
    # Clear the harness's input box so the composer's send-text delivery lands
    # in an empty box. Best-effort and NON-BLOCKING: this runs on kitty's main
    # thread, so we must never sleep/poll here (that would stall the whole
    # terminal, and kitty can't reparse the box's post-clear redraw mid-handler
    # anyway). We send BOTH sequences, unconditionally and in order: Ctrl+U
    # (kill-line — clears in one shot if this build honors it) THEN
    # len(draft)+2 backspaces. If Ctrl+U already emptied the box, the trailing
    # backspaces are harmless no-ops on an empty input; if it didn't, the
    # backspaces are the real workhorse. Neither byte is Enter (0x0d), so
    # nothing is ever submitted. (Ctrl+U is an UNVERIFIED convention — see the
    # module header; the backspace fallback is what makes this robust.)
    for chunk in (b"\x15", b"\x7f" * backspace_count(draft)):  # Ctrl+U, then DELs
        try:
            w.write_to_child(chunk)
        except Exception:
            pass


def _act(w, boss):
    home = os.path.expanduser("~")
    annex_cmd = os.path.join(home, ".local", "bin", "annex-cmd")
    deliver_lua = os.path.join(home, ".local", "bin", "annex-deliver.lua")

    try:
        cols = int(w.screen.columns)
    except Exception:
        cols = 0

    try:
        text = w.as_text(add_history=False)
    except Exception:
        text = ""
    draft = parse_draft(text, cols)

    sess = _name("annex")
    fd, composer_file = tempfile.mkstemp(
        prefix="annex-compose.", dir=os.environ.get("TMPDIR", "/tmp")
    )
    try:
        if draft:
            os.write(fd, draft.encode("utf-8"))
    finally:
        os.close(fd)

    try:
        harness_host = subprocess.check_output(["hostname"], text=True).strip() or "unknown"
    except Exception:
        harness_host = "unknown"

    argv = build_composer_argv(
        annex_cmd, deliver_lua, sess, composer_file,
        w.id, boss.listening_on or "", harness_host,
    )

    # Launch FIRST; only clear the harness's visible box AFTER a CONFIRMED
    # success (call_remote_control raises on failure — kitty's boss.py). See
    # module header's FAIL-SAFE ORDERING note: this is what keeps a failed
    # launch from ever destroying a draft that hasn't been durably captured
    # yet, exactly mirroring nvim-annex's own "truncate only on success".
    try:
        boss.call_remote_control(w, argv)
    except Exception:
        try:
            os.unlink(composer_file)
        except Exception:
            pass
        raise

    # Success: the draft is durably captured in composer_file now — safe to
    # clear the box the composer is taking over from.
    _clear_harness_input(w, draft, cols)


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    w = None
    is_harness = False
    try:
        w = boss.window_id_map.get(target_window_id)
        if w is not None:
            is_harness = _is_harness(w)
        if is_harness:
            _act(w, boss)
            return
    except Exception:
        pass

    # FALLBACK — chord-aware since the demotion to Ctrl+Shift+G (Tom 2026-07-15):
    #   * HARNESS window but _act() raised (remote control down, mktemp failed,
    #     launch failed, ...) -> forward raw Ctrl+G (BEL, 0x07) so Claude's/pi's
    #     OWN native Ctrl+G->$EDITOR composer fires as graceful degradation. The
    #     user pressed Ctrl+Shift+G, but the intent ("give me a composer") is
    #     honored, and the native path additionally PRESERVES paste/image
    #     placeholders that this screen-scrape kitten cannot (see module header).
    #   * NON-harness window (nvim, a plain shell, fzf, bash reverse-search), or
    #     w is None -> Ctrl+Shift+G means nothing there; SWALLOW it. We must NOT
    #     emit 0x07 here: on plain Ctrl+G the shadow was harmless because Ctrl+G
    #     IS meaningful everywhere, but injecting BEL for a Ctrl+SHIFT+G press
    #     would abort a bash reverse-search / ring nvim's bell out of nowhere.
    try:
        if w is not None and is_harness:
            w.write_to_child(b"\x07")
    except Exception:
        pass
