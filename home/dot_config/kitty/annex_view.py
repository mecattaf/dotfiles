# annex_view.py — Claude Code transcript viewer in a SEPARATE kitty OS-window,
# so Tom can scroll/search his conversation history WITHOUT blanking the live
# chat. Bound to TWO chords (see handle_result):
#   * Ctrl+G       (`… annex_view.py compose`) — open/refresh the viewer AND
#     forward Ctrl+G so Claude's native composer opens too. One press = edit in
#     nvim (paste + images preserved by the native tempfile round-trip) WHILE
#     the viewer keeps the conversation visible. This retired the old
#     Ctrl+Shift+G overlay composer (dotfiles#77): the overlay existed only to
#     avoid the alt-screen blank, but the viewer window now covers that need, so
#     the strictly-better native composer wins outright.
#   * Ctrl+Shift+O (`… annex_view.py`) — view-only; press again in the viewer's
#     tab to dismiss.
#
# RESUME-MENU: large sessions (>70min idle AND >100k tokens) otherwise gate
# behind Claude's "resume from summary / as-is" menu (default = summary = model
# work). _act's launch payload sets CLAUDE_CODE_RESUME_TOKEN_THRESHOLD=999999999
# so the gate never fires — resumes as-is, zero keystrokes, zero tokens
# (undocumented internal; see the note in _act). Supersedes the module's older
# "CRITICAL DEVIATION" worry below that the menu was unavoidable.
#
# A no-UI kitten mapped in kitty.conf, modeled 1:1 on annex_ctrlg.py (the
# Ctrl+Shift+G composer) and annex_toggle.py (the Ctrl+B sidebar picker):
# main() is a no-op, all work happens in handle_result() running IN the kitty
# process with boss/window access (@result_handler(no_ui=True) => instant, no
# overlay window flashes).
#
# WHY THIS EXISTS: Claude Code's own Ctrl+O (app:toggleTranscript) is a
# static, scrollable, searchable full re-render of the conversation
# (thinking/tools/images) from its IN-MEMORY conversation array — but it only
# replaces the CURRENT alt-screen, so scrolling the transcript means losing
# sight of (and being unable to type into) the live chat. That in-memory
# array is persisted live, message-by-message, to
# <CLAUDE_CONFIG_DIR or ~/.claude>/projects/<cwd-slug>/<sessionId>.jsonl — so
# a SECOND, independent `claude` process can be pointed at the SAME
# sessionId via `--resume` and will re-render that transcript with Claude's
# OWN renderer (native Ctrl+O, native inline images, native search) inside
# its own window, leaving the original untouched. This kitten's only job is
# resolving WHICH sessionId belongs to the focused harness window and
# launching that second process in a new OS window.
#
# CRITICAL DEVIATION FROM THE ORIGINAL DESIGN — read before touching the
# launch argv: the design called for
# `claude --resume <sessionId> --no-session-persistence`, reasoned to be an
# INERT resume (renders, writes nothing, costs nothing). Live verification
# (real PTY, this session) falsified that:
#   `--no-session-persistence` is print-mode-only — `claude --help` says so
#   outright, and `claude --resume <id> --no-session-persistence` in a real
#   PTY exits immediately with "Error: --no-session-persistence can only be
#   used with --print mode." It never renders anything. That flag is DROPPED
#   from the argv below entirely — using it here would make the whole
#   feature dead on arrival.
# Its removal has a real UX cost, also live-verified: plain
# `claude --resume <sessionId>` (no extra flags) is NOT an instant re-render
# for any session with meaningful age/size — it gates behind a blocking,
# interactive confirmation menu ("This session is 3h 31m old and 309.8k
# tokens... 1. Resume from summary (recommended) / 2. Resume full session
# as-is / 3. Don't ask me again"), with "Resume from summary" HIGHLIGHTED
# BY DEFAULT — not the verbatim transcript this viewer exists for, and
# likely to trigger real model work (summarization) unless the user arrows
# down to option 2 every time. No CLI flag exists to preselect "as-is"
# non-interactively (checked --help in full + grepped the wrapped binary).
# What happens after confirming "as-is" against the STILL-LIVE source
# session (whether it appends anything to the jsonl the original pid is
# using) is UNVERIFIED — flagged as an open risk, not confirmed safe. Up to
# that confirmation gate, nothing is written (md5-identical jsonl + registry
# entry before/after a killed resume attempt, verified live). This is
# option (1) from the risk writeup (drop the flag, accept + document the
# menu) rather than (2) hunting for an undocumented flag or (3) blocking the
# whole feature on a synchronous escalation — ship it, document the gap
# loudly, revisit if a real flag surfaces later.
#
# REUSED BYTE-FOR-BYTE from annex_ctrlg.py: _HARNESS_RE and
# is_harness_cmdline() (harness detection — kitty reports MULTIPLE
# simultaneous foreground processes for a real claude window, e.g. claude
# itself plus a wl-copy clipboard-helper child, so this scans every entry,
# not just index 0). REUSED from annex_toggle.py: _name() (self-contained
# unique session-name generator) and the SHAPE of _annex_window_in_tab
# (renamed _view_window_in_tab here, same tab-scoped-not-global contract).
#
# SESSION RESOLUTION (see resolve_session's docstring for the full
# tie-break rationale — this was live-probed against the real
# ~/.claude/sessions/*.json registry on this box, not designed blind):
# read every <root>/sessions/*.json, drop entries whose pid is dead
# (os.kill(pid, 0) raises), drop entries with no matching
# projects/*/<sessionId>.jsonl (a freshly-started session can go idle before
# its first message is ever persisted — confirmed live, `--resume` on such
# an id fails outright with "No conversation found with session ID: ..."),
# filter to the focused harness window's OWN cwd, then break ties by
# preferring status=="busy" and then max statusUpdatedAt. That two-stage
# tie-break is NOT defensive paranoia — on this exact machine, at probe
# time, THREE registry entries shared this repo's cwd and TWO of them were
# simultaneously status=="busy", so a "cwd + busy-only" rule would still
# leave an unresolved tie.
#
# HARNESS CWD, corrected against real kitty 0.47.4 source (not the design's
# original assumption): `window.cwd` is NOT a real attribute on kitty's
# Window class (grepped kitty/window.py — only cwd_of_child, cwd_of_child
# property, get_cwd_of_child(), get_cwd_of_root_child() exist). Preferred
# source is the SPECIFIC foreground_processes[i]['cwd'] entry whose cmdline
# matched the harness pattern (is_harness_cmdline tells you THAT one
# matched, not WHICH one — foreground_processes[0] is not guaranteed to be
# the harness itself), falling back to window.cwd_of_child (itself tries
# get_foreground_cwd() then current_cwd) only if no entry matched.
#
# SWALLOW-ON-NON-HARNESS FAIL-SAFE (mirrors annex_ctrlg.py's non-harness
# fallback, not its harness-error fallback): Ctrl+Shift+O has no meaning
# outside a claude/pi harness window, and — unlike plain Ctrl+G, which is
# meaningful everywhere — there is no safe raw byte to forward for a chord
# nothing else binds. A non-harness focused window, a harness window whose
# session can't be resolved, or ANY exception anywhere in this path all
# SWALLOW: do nothing, emit no byte, never crash the terminal. This is a
# strictly no-op-on-failure feature, not a graceful-degradation-to-native
# one (there is no "native" Ctrl+Shift+O to degrade to).
#
# THIN-CLIENT NOTE: annex-cmd's `exec` subcommand is REUSED UNCHANGED (its
# `exec <sess> claude --resume <id>` fits the existing command-agnostic
# "zmx attach the payload" contract exactly, no edit needed) and inherits
# its coordinator-vs-thin-client host branch for free. But session
# RESOLUTION in THIS file (the sessions/*.json registry + projects/*.jsonl
# glob) only ever runs on the LOCAL kitty host, reading local paths — on a
# thin client (worker/zenbook) that registry lives on the coordinator, not
# locally, so resolve_session() will legitimately find zero candidates and
# this kitten SWALLOWS. That matches every other annex feature's fail-safe
# default for v1: no cross-host registry read exists yet, so thin-client
# invocation is a documented no-op, not a crash.

import glob
import json
import os
import re
import shlex
import shutil
import subprocess
import time
import uuid

from kittens.tui.handler import result_handler

_HARNESS_RE = re.compile(r"^(claude|pi)$")


def main(args):
    # All work is done in handle_result; main only forwards the (unused) args.
    return args


# ─────────────────────────── pure functions ────────────────────────────────
# Everything below takes plain inputs (strings/lists/dicts) and returns plain
# outputs — no boss/window objects — so it can be exercised with fixtures.


def is_harness_cmdline(foreground_processes):
    """Pure. REUSED BYTE-FOR-BYTE from annex_ctrlg.py. Scan kitty's
    Child.foreground_processes shape (list of {'pid':.., 'cmdline': [...],
    'cwd':..} dicts) for a claude/pi harness anywhere in the list.
    Live-verified (probe): kitty reports MULTIPLE simultaneous foreground
    processes for a real claude window (claude itself + wl-copy
    clipboard-helper children it spawns) — so this scans every entry, not
    just index 0."""
    try:
        for p in foreground_processes or ():
            for tok in (p.get("cmdline") or ()):
                if tok and _HARNESS_RE.match(os.path.basename(tok)):
                    return True
    except Exception:
        pass
    return False


def harness_cwd(foreground_processes):
    """Pure. Returns the cwd of the SPECIFIC foreground_processes entry
    whose cmdline matched the claude/pi harness pattern — is_harness_cmdline
    only tells you THAT some entry matched, not WHICH one, and
    foreground_processes[0] is not guaranteed to be the harness (kitty can
    report a wl-copy clipboard-helper child alongside claude itself; ordering
    is not part of kitty's documented contract). Returns None if nothing
    matches, so the caller can fall back to window.cwd_of_child."""
    try:
        for p in foreground_processes or ():
            for tok in (p.get("cmdline") or ()):
                if tok and _HARNESS_RE.match(os.path.basename(tok)):
                    return p.get("cwd")
    except Exception:
        pass
    return None


def harness_pid(foreground_processes):
    """Pure. Parallel to harness_cwd(): returns the OS pid of the SAME
    foreground_processes entry that matched the claude/pi harness pattern.
    This is the disambiguator the cwd-only heuristic below cannot be: kitty's
    foreground_processes pid for the harness IS the exact key the live
    registry is written under (<root>/sessions/<pid>.json = {"pid": <this
    same pid>, "sessionId": ..., ...}), so matching on it is exact and
    deterministic per focused window, unlike cwd+busy/newest which can only
    guess when multiple claude sessions share one cwd (see resolve_session
    and the module header's live 3-same-cwd/2-busy probe). Returns None if
    nothing matched, so the caller falls back to the cwd heuristic alone."""
    try:
        for p in foreground_processes or ():
            for tok in (p.get("cmdline") or ()):
                if tok and _HARNESS_RE.match(os.path.basename(tok)):
                    return p.get("pid")
    except Exception:
        pass
    return None


def resolve_session(session_dicts, target_cwd, target_pid=None):
    """Pure. Takes a plain list of session-registry dicts (each with at
    least 'pid', 'cwd', 'sessionId', 'status', 'statusUpdatedAt' — already
    filtered for a live pid and an existing jsonl by the impure loader below,
    see _live_sessions), a target cwd string, and (preferably) the focused
    harness window's exact claude pid; returns the winning sessionId or None.

    EXACT PATH (preferred): if target_pid is given and some entry's 'pid'
    equals it, that entry IS the focused window's own registry record —
    return its sessionId directly, no tie-break needed. This is what makes
    resolution deterministic per window: the registry is keyed by this same
    pid, so a pid match can never be ambiguous the way cwd is.

    FALLBACK (only when target_pid is None or matches nothing — e.g. kitty
    didn't report a pid for this build): filters to target_cwd, then applies
    the two-stage tie-break (prefer status=='busy', then max
    statusUpdatedAt) that a live probe of this exact box's ~/.claude/sessions/
    registry showed is NECESSARY in practice, not merely defensive: three
    same-cwd entries were live simultaneously, and TWO of them were
    status=='busy' at once, so a cwd+busy-only rule alone would still leave
    an unresolved tie — this heuristic is a best-effort guess, not a real
    disambiguator, which is exactly why the pid path above takes priority.
    now-agnostic: takes no wall-clock input, so it is deterministic and
    unit-testable against a fixed fixture list."""
    if target_pid is not None:
        for d in session_dicts:
            if d.get("pid") == target_pid:
                return d.get("sessionId")

    matches = [d for d in session_dicts if d.get("cwd") == target_cwd]
    if not matches:
        return None
    matches.sort(key=lambda d: (d.get("status") == "busy", d.get("statusUpdatedAt", 0)))
    return matches[-1].get("sessionId")


def _name(prefix):
    # Copied verbatim from annex_toggle.py/annex_ctrlg.py — self-contained +
    # unique per press (mirrors annex-cmd name / new-terminal): no fork, no
    # network.
    return "%s-%s-%s" % (prefix, time.strftime("%H%M%S"), uuid.uuid4().hex[:6])


# ─────────────────────────── impure I/O helpers ────────────────────────────
# Thin wrappers around the filesystem/process table — kept separate from the
# pure functions above so the tie-break logic itself stays fixture-testable.


def _config_root():
    return os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")


def _has_jsonl(root, sid):
    """Impure. True iff a persisted transcript exists for sid. A brand-new
    conversation gets a sessions/<pid>.json registry entry BEFORE its first
    message is ever written to projects/*/<sid>.jsonl (live-confirmed:
    `--resume` on such an id fails with "No conversation found …"). So this is
    exactly what distinguishes 'fresh/empty session — nothing to view' from a
    resolvable one — see _act's exact-pid empty-session handling."""
    return bool(sid) and bool(
        glob.glob(os.path.join(root, "projects", "*", sid + ".jsonl"))
    )


def _pid_alive_sessions(root):
    """Impure. Every <root>/sessions/*.json whose pid is still alive
    (os.kill(pid, 0) succeeds — a dead pid means the process exited without
    cleaning up its registry file). NO jsonl filter here, deliberately: the
    exact-pid path in _act needs to SEE a fresh/empty session (pid alive, no
    jsonl yet) so it can SWALLOW rather than mis-resolve to a different
    same-cwd session (the exact wrong-session bug seen live)."""
    out = []
    for f in glob.glob(os.path.join(root, "sessions", "*.json")):
        try:
            with open(f) as fh:
                d = json.load(fh)
        except Exception:
            continue
        try:
            os.kill(d.get("pid"), 0)
        except Exception:
            continue
        out.append(d)
    return out


def _snapshot_transcript(root, session_id):
    """Impure. Makes the viewer's write-safety guarantee STRUCTURAL instead
    of merely unconfirmed (see the module header's CRITICAL DEVIATION note:
    whether an interactive `--resume` of a STILL-LIVE session eventually
    writes to that session's own jsonl, once the user answers the "resume
    from summary / as-is" gate, is UNVERIFIED). Copies the resolved
    session's live projects/*/<session_id>.jsonl to a THROWAWAY sessionId's
    jsonl file in the SAME project directory (so `claude --resume` finds it
    under the same cwd-slug) and returns that throwaway id. The launched
    viewer is then pointed at the COPY, never the original — whatever the
    resumed process might append to "its own" jsonl can only land in a file
    nothing else is reading or writing, so the still-live original is
    physically unreachable from the viewer, no matter what --resume does
    past its confirmation gate. Returns (None, None) if no live jsonl exists
    for session_id (caller must SWALLOW, never fall back to resuming the
    original directly — that would silently drop this whole safety net)."""
    matches = glob.glob(os.path.join(root, "projects", "*", session_id + ".jsonl"))
    if not matches:
        return None, None
    src = matches[0]
    project_dir = os.path.dirname(src)
    snap_id = str(uuid.uuid4())
    dst = os.path.join(project_dir, snap_id + ".jsonl")
    # `claude --resume <id>` resolves the session by FILENAME within the current
    # cwd's project slug (verified live: a plain copy resumes fine by its new
    # name; the internal sessionId field is NOT what it matches on). So a straight
    # copy into the same project dir is resumable — the load-bearing half of the
    # fix is cd-ing the viewer into that cwd (see _act's payload). This only ever
    # writes the throwaway copy; the live original is never touched.
    try:
        shutil.copy2(src, dst)
    except Exception:
        return None, None
    return snap_id, dst


# ─────────────────────────── kitty-boss glue ───────────────────────────────


def _is_harness(window):
    try:
        return is_harness_cmdline(window.child.foreground_processes)
    except Exception:
        return False


def _view_window_in_tab(window, boss):
    # Tab-scoped, mirrors annex_toggle.py's _annex_window_in_tab EXACTLY
    # (NOT a global match — a viewer left open in some OTHER tab/OS-window
    # must not be found from here). Because the viewer is launched as a
    # SEPARATE --type=os-window (its own tab), this only ever matches when
    # focus is already INSIDE that viewer's own tab — i.e. it implements
    # "press Ctrl+Shift+O again while looking at the viewer to dismiss it";
    # it does NOT reach across OS windows from the original harness's tab.
    try:
        tab = window.tabref() if hasattr(window, "tabref") else None
    except Exception:
        tab = None
    windows = list(tab) if tab is not None else list(boss.all_windows)
    for w in windows:
        try:
            if (w.user_vars or {}).get("annex_view") == "1":
                return w
        except Exception:
            continue
    return None


def _view_window_for_sid(boss, session_id):
    """Global (all windows, NOT tab-scoped) search for an already-open viewer
    of THIS exact session, marked var:annex_view_sid=<session_id> at launch.
    Unlike _view_window_in_tab (the Ctrl+Shift+O press-again-to-dismiss check,
    which is deliberately tab-scoped), this must span OS windows: the compose
    chord (Ctrl+G) fires from the HARNESS's tab but the viewer lives in its own
    os-window/tab, so dedup has to look everywhere to avoid stacking a second
    viewer on every composer-open."""
    for w in list(boss.all_windows):
        try:
            if (w.user_vars or {}).get("annex_view_sid") == session_id:
                return w
        except Exception:
            continue
    return None


def _resolve_session_id(w, boss):
    """Impure. Resolve the focused harness window's sessionId, or None to
    SWALLOW. Coordinator-only (thin-client registry isn't locally readable).
    EXACT-PID path is authoritative: the focused window's own claude pid IS the
    registry key, so its sessions/<pid>.json entry is unambiguous — if that
    session has a jsonl, resume it; if it's fresh/empty (pid alive, no jsonl
    yet), SWALLOW rather than fall back to cwd (which would mis-resolve to a
    DIFFERENT same-cwd session — the exact bug seen live). Only when the focused
    pid isn't in the registry at all do we cwd-fallback."""
    try:
        host = subprocess.check_output(["hostname"], text=True).strip()
    except Exception:
        host = ""
    if host != "coordinator":
        return None  # thin client -> SWALLOW, never mis-route to the coordinator

    try:
        fps = w.child.foreground_processes
    except Exception:
        fps = ()

    target_cwd = harness_cwd(fps)
    if not target_cwd:
        # window.cwd is NOT a real kitty API; cwd_of_child tries
        # get_foreground_cwd() then current_cwd internally.
        try:
            target_cwd = w.cwd_of_child
        except Exception:
            target_cwd = None

    target_pid = harness_pid(fps)
    root = _config_root()
    alive = _pid_alive_sessions(root)

    if target_pid is not None:
        pid_entry = next((d for d in alive if d.get("pid") == target_pid), None)
        if pid_entry is not None:
            sid = pid_entry.get("sessionId")
            if _has_jsonl(root, sid):
                return sid
            return None  # fresh/empty conversation for THIS window -> SWALLOW

    if not target_cwd:
        return None
    resolvable = [d for d in alive if _has_jsonl(root, d.get("sessionId"))]
    return resolve_session(resolvable, target_cwd, None)


def _niri_max_id(app_id):
    """Highest niri window id currently carrying <app_id>, or 0. This is the
    BASELINE annex-place needs to tell a genuinely-new window from a lingering
    same-class one (a view-only viewer from an earlier Ctrl+Shift+O, say): snapshot
    it BEFORE launching, so the about-to-open window is strictly greater and
    annex-place acts on it alone — never on the pre-existing one. See annex-place's
    header."""
    try:
        out = subprocess.check_output(
            ["niri", "msg", "-j", "windows"], stderr=subprocess.DEVNULL, timeout=1
        )
        ids = [w.get("id", 0) for w in json.loads(out) if w.get("app_id") == app_id]
        return max(ids) if ids else 0
    except Exception:
        return 0


def _fire_place(args):
    """Fire annex-place detached (start_new_session) + silenced so it outlives
    this kitten callback and never blocks kitty. Best-effort."""
    try:
        place = os.path.join(os.path.expanduser("~"), ".local", "bin", "annex-place")
        subprocess.Popen(
            [place] + [str(a) for a in args],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception:
        pass


def _act(w, boss):
    """Resolve + launch (or, if a viewer for this session is already open, leave)
    the viewer os-window. Returns the resolved sessionId on success else None;
    handle_result uses that only for its own flow — the compose chord forwards
    Ctrl+G regardless of what this returns."""
    home = os.path.expanduser("~")
    annex_cmd = os.path.join(home, ".local", "bin", "annex-cmd")

    root = _config_root()
    session_id = _resolve_session_id(w, boss)
    if not session_id:
        return None

    # DEDUP (global, by sessionId): the compose chord (Ctrl+G) fires on EVERY
    # composer-open, so without this a fresh viewer os-window would stack on
    # each press. If one is already open for this exact session, leave it.
    if _view_window_for_sid(boss, session_id) is not None:
        return session_id

    # Structural write-safety (see _snapshot_transcript): never resume the live
    # session_id directly — resume a throwaway COPY of its jsonl, so the viewer
    # physically cannot write to the still-live original.
    snap_id, snap_path = _snapshot_transcript(root, session_id)
    if not snap_id:
        return None  # can't make write-safety structural -> SWALLOW

    # Payload (coordinator-local). Two things folded into the launched command:
    #   1. CLAUDE_CODE_RESUME_TOKEN_THRESHOLD=999999999 — structurally suppress
    #      the large-session "resume from summary / as-is" menu. Verified in the
    #      2.1.205 bundle: the gate needs BOTH >70min idle AND >100k tokens; a
    #      huge threshold makes it never fire -> resumes as-is, zero keystrokes,
    #      zero tokens (the summary path is the only token-spender). No official
    #      flag/setting exists — this env var is an undocumented internal, so
    #      guard/version-pin it (fallback: user clicks "Don't ask me again" once,
    #      which persists resumeReturnDismissed:true = safe as-is lock).
    #   2. Best-effort AUTO-Ctrl+O: after a short settle, send-text Ctrl+O (0x0F)
    #      to this very window (KITTY_WINDOW_ID is set by kitty in the launched
    #      child) so it lands in the STATIC transcript view, not interactive.
    #      The 1.3s delay is a coordinator-local guess and MAY NEED TUNING (if it
    #      fires before claude has drawn, the match no-ops and the user presses
    #      Ctrl+O once). Degrades safely: an unset/empty KITTY_WINDOW_ID makes
    #      `--match id:` match nothing (harmless). Cross-host auto-Ctrl+O + env
    #      threading is deferred (#78/#72).
    #   3. cd into the SESSION's cwd first. `claude --resume` resolves the session
    #      by scanning ONLY the current cwd's project slug
    #      (~/.claude/projects/<cwd-slug>/<id>.jsonl) — verified live: the SAME
    #      snapshot resumes from the repo cwd but errors "No conversation found
    #      with session ID" from $HOME or /tmp. The viewer runs claude through
    #      `annex-cmd exec` -> `zmx attach`, and the kitty `--cwd=current` does NOT
    #      survive that zmx hop, so claude was landing in the wrong cwd and never
    #      finding the snapshot (the exact failure Tom hit). The harness/session
    #      cwd's slug is exactly the snapshot's project dir, so cd-ing there makes
    #      the resume resolve. Best-effort: no cd if the cwd can't be resolved.
    try:
        target_cwd = harness_cwd(w.child.foreground_processes)
    except Exception:
        target_cwd = None
    if not target_cwd:
        try:
            target_cwd = w.cwd_of_child
        except Exception:
            target_cwd = None
    cd_prefix = ("cd " + shlex.quote(target_cwd) + " 2>/dev/null; ") if target_cwd else ""

    payload_sh = (
        cd_prefix
        + '(sleep 1.3 && kitten @ send-text --match id:"$KITTY_WINDOW_ID" '
        '"$(printf \'\\017\')") >/dev/null 2>&1 & '
        "exec env CLAUDE_CODE_RESUME_TOKEN_THRESHOLD=999999999 "
        "claude --resume " + snap_id
    )

    sess = _name("annexview")
    argv = (
        "launch",
        "--type=os-window",
        # Distinguishing niri app_id (kitty maps --os-window-class to the Wayland
        # app_id) so annex-place can match/position this viewer: right-half on its
        # own (Ctrl+Shift+O), or stacked above the composer (Ctrl+G, arranged by
        # nvim-annex's compose placer, which also reaps this viewer on composer
        # close).
        "--os-window-class",
        "annex-viewer",
        "--cwd=current",
        "--watcher",
        "annex_view_watcher.py",
        "--var",
        "annex_view=1",
        "--var",
        "annex_session=" + sess,
        "--var",
        "annex_view_sid=" + session_id,
        "--var",
        "annex_view_snapshot=" + snap_path,
        "--",
        annex_cmd,
        "exec",
        sess,
        "sh",
        "-c",
        payload_sh,
    )
    boss.call_remote_control(w, argv)
    return session_id


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    # Two chords share this kitten (Tom 2026-07-15 merge):
    #   * `map ctrl+g       kitten annex_view.py compose`  -> COMPOSE mode:
    #     open/refresh the viewer AND forward Ctrl+G so Claude's native composer
    #     fires too (edit in nvim with paste+images preserved, while the viewer
    #     window keeps the conversation visible — this is why the old
    #     Ctrl+Shift+G overlay was retired: no blank to avoid anymore).
    #   * `map ctrl+shift+o kitten annex_view.py`          -> VIEW-ONLY mode:
    #     just the transcript viewer, press-again-in-tab to dismiss, swallow
    #     everywhere else.
    compose = "compose" in (args or ())

    w = None
    try:
        w = boss.window_id_map.get(target_window_id)
    except Exception:
        w = None

    try:
        if w is not None and _is_harness(w):
            if compose:
                # COMPOSE: launch/dedup the viewer, then place the composer +
                # viewer via annex-place. Baselines are snapshotted HERE — before
                # the viewer launches (via _act) and before the composer launches
                # (later, when the Ctrl+G forwarded below reaches nvim-annex) — so
                # annex-place's `stack` acts ONLY on the genuinely-new windows and
                # never disturbs/reaps a pre-existing viewer: a swallow or dedup
                # (no new viewer) degrades to placing the composer solo. This is
                # why compose geometry lives here and NOT in nvim-annex — only this
                # point sees both baselines pre-launch. Forwarding of Ctrl+G still
                # happens unconditionally below so the native composer always fires.
                cbase = _niri_max_id("annex-composer")
                vbase = _niri_max_id("annex-viewer")
                _act(w, boss)
                _fire_place(["stack", cbase, vbase])
            else:
                # VIEW-ONLY: press-again-in-viewer-tab dismisses (tab-scoped);
                # else launch and place it as a right-half. Baseline snapshotted
                # BEFORE _act so a dedup-hit (no new window) is a safe no-op in
                # annex-place (nothing newer than the baseline appears).
                existing = _view_window_in_tab(w, boss)
                if existing is not None:
                    boss.mark_window_for_close(existing)
                else:
                    vbase = _niri_max_id("annex-viewer")
                    _act(w, boss)
                    _fire_place(["solo", "annex-viewer", vbase])
    except Exception:
        # Any error -> fall through. In compose mode we still forward Ctrl+G
        # (the composer must never be lost to a viewer-launch failure); in
        # view-only mode there is nothing to degrade to, so we simply swallow.
        pass

    # COMPOSE forwards the raw Ctrl+G byte (BEL, 0x07) to whatever is focused —
    # in the harness it opens Claude's/pi's own Ctrl+G->$EDITOR (nvim-annex,
    # paste/image preserving); in nvim/shell it behaves as a normal Ctrl+G. This
    # is why binding Ctrl+G here does NOT regress the demotion's "Ctrl+G reaches
    # the app" behavior — every press is still forwarded. VIEW-ONLY (Ctrl+Shift+O)
    # forwards nothing: there is no native Ctrl+Shift+O to degrade to.
    if compose:
        try:
            if w is not None:
                w.write_to_child(b"\x07")
        except Exception:
            pass
