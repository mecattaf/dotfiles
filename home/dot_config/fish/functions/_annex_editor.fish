# _annex_editor — shared, harness-agnostic scoping for the Ctrl+G externalized
# composer (dotfiles#49). Runs $argv (a harness invocation, e.g. `claude …` or
# `pi …`) with EDITOR/VISUAL pointed at the nvim-annex composer wrapper, and ONLY
# for the duration of that invocation. Both Claude Code and pi resolve the
# external editor as (externalEditorCommand ||) VISUAL || EDITOR, so setting both
# here makes nvim-annex their Ctrl+G editor without touching the global editor.
#
# WHY `set -lx`, NOT `set -x` (load-bearing bug fix): config.fish does
# `set -gx EDITOR nvim` GLOBALLY. Fish's `set` WITHOUT a scope flag mutates the
# innermost scope the variable ALREADY EXISTS in — which for EDITOR is the GLOBAL
# one — so a bare `set -x EDITOR nvim-annex` would PERMANENTLY clobber the user's
# editor (git commit, crontab -e, plain `nvim`/`vi` would all become the composer
# and stay that way for the rest of the shell). `set -lx` forces a NEW
# function-local exported var that shadows the global for child processes and is
# discarded on return. Verified: after the call, global EDITOR is back to `nvim`.
# This is exactly Tom's "do NOT make nvim-annex the global editor" requirement.
#
# Adding a harness = one thin wrapper: `function <h>; _annex_editor <h> $argv; end`.
# `command` runs the real binary, bypassing the same-named wrapper function (no
# recursion). Interactive-pure: no LLM/network/blocking work here.
#
# ABSOLUTE path (not the bare name): ~/.local/bin is NOT on the login PATH here,
# so the harness's editor spawn resolved `nvim-annex` via PATH and failed
# ("Executable not found in $PATH"). An absolute path sidesteps PATH entirely and
# matches the repo convention (niri calls ~/.local/bin/* by absolute path too).
# The basename stays `nvim-annex`, which is what Claude's terminal-editor regex
# classifies on — so the blocking spawnSync branch is still taken.
function _annex_editor --description 'Run a harness with EDITOR/VISUAL scoped to the nvim-annex Ctrl+G composer'
    set -lx EDITOR $HOME/.local/bin/nvim-annex
    set -lx VISUAL $HOME/.local/bin/nvim-annex
    command $argv
end
