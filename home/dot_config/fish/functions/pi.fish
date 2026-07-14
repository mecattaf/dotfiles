# pi.fish — earendil-works/pi with the same Ctrl+G composer scoped in
# (dotfiles#49; harness-agnostic per Tom 2026-07-15). A thin per-harness wrapper
# over `_annex_editor`, mirroring claude.fish — adding a harness is exactly this
# much code.
#
# pi resolves its Ctrl+G editor as `externalEditorCommand || VISUAL || EDITOR`
# (verified in pi 0.80.3's extension-editor.js). We leave pi's own
# externalEditorCommand unset so the VISUAL/EDITOR path (the uniform cross-harness
# scoping) wins.
#
# CRASH-SAFETY HOLDS FOR pi TOO (verified from the same bundle): pi spawns the
# editor ASYNC and awaits its close, then `if (status === 0) editor.setText(reread)`
# — so a NONZERO/errored editor exit does NOT re-read the tempfile and pi KEEPS
# the original prompt (and it never auto-submits — the text is only populated). A
# spawn error resolves status=null, also skipping the re-read. nvim-annex returns
# nonzero on any aborted/crashed compose (mtime unchanged), so pi keeps the
# original exactly as Claude does. nvim-annex's os-window + --wait-for-child-to-exit
# blocks until nvim exits, which is all pi's async-spawn-and-wait needs.
function pi --wraps pi --description 'pi with the Ctrl+G composer scoped to nvim-annex'
    _annex_editor pi $argv
end
