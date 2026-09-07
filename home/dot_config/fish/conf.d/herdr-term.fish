# herdr scrubs the terminal identity out of every pane, and that is what killed
# Ctrl+Backspace and Shift+Enter in Claude Code (#334).
#
# herdr's pane spawn (src/pane.rs) hard-codes TERM=xterm-256color +
# COLORTERM=truecolor and DELETES TERM_PROGRAM, KITTY_WINDOW_ID, STY and
# WT_SESSION. There is no config knob for it: TerminalConfig at 0.8.2 is exactly
# default_shell / shell_mode / new_cwd, which is why this lives here and not in
# dot_config/herdr/config.toml.
#
# Claude Code decides whether to turn the kitty keyboard protocol ON from that
# environment, never by querying the terminal:
#
#   H  = ["iTerm.app","kitty","WezTerm","ghostty","tmux","windows-terminal","WarpTerminal"]
#   Ej = H.includes(env-derived terminal) ? CSI<u + CSI>5u + CSI>4;2m : ""
#
# and the env-derived name is TERM~/kitty/ -> "kitty", else TERM_PROGRAM, else
# KITTY_WINDOW_ID -> "kitty". Under herdr none of those match, so `claude` emits
# NO CSI>5u, kitty stays on legacy encoding, and there Shift+Enter is
# byte-identical to Enter (\r) while Ctrl+Backspace collapses onto Backspace.
# MEASURED under a captured pty: TERM=xterm-kitty -> ESC[<u ESC[>5u;
# TERM=xterm-256color -> nothing; TERM=xterm-256color + KITTY_WINDOW_ID -> ESC[<u ESC[>5u.
#
# herdr itself is NOT the offender and needs no patch: its VT answers CSI?u,
# its encoder emits ESC[127;5u / ESC[13;2u once a pane has pushed the flags, and
# its client already pushes CSI>5u to the host kitty — the relay was measured
# byte-faithful end to end. Only the app's decision to enable it was lost.
#
# Why KITTY_WINDOW_ID and not TERM=xterm-kitty: TERM is terminfo, and raising it
# would advertise kitty graphics herdr does not render ([experimental]
# kitty_graphics) and would break `ssh` to any box without kitty's terminfo.
# This variable is presence-only for every consumer that matters — nothing in
# this repo reads it (every kitty caller here uses KITTY_LISTEN_ON), and a pane
# can be re-attached to a different kitty window at any time, so a real window
# id would be a lie with a shelf life. 0 matches no window, so anything that did
# try `kitten @ --match id:$KITTY_WINDOW_ID` fails closed instead of hitting the
# wrong window.
#
# Same variable also restores, in the same Claude Code build: synchronized
# output (SD() — no more tearing on redraw), OSC-8 hyperlinks, strikethrough,
# and the OSC 99 notification path.
if set -q HERDR_ENV; and not set -q KITTY_WINDOW_ID
    set -gx KITTY_WINDOW_ID 0
end
