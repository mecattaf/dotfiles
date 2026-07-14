# claude.fish — Claude Code with the Ctrl+G composer scoped in (dotfiles#49).
#
# Thin per-harness wrapper over `_annex_editor` (the shared, harness-agnostic
# scoping helper). `cc`/`cac` are fish aliases that call `claude`, so they inherit
# the scoped composer automatically — config.fish's alias lines stay untouched.
#
# `nvim-annex` (not plain `nvim`) is load-bearing here: Claude classifies the
# editor by basename against /\b(vi|vim|nvim|nano|…)\b/ (verified in the 2.1.205
# bundle). `nvim-annex` matches \bnvim\b, so Claude takes the BLOCKING
# spawnSync({stdio:"inherit"}) branch and re-reads the tempfile ONLY on exit
# status 0 (`c.status!==0 || c.signal || c.error -> content:null -> keep the
# original prompt`; the edited text is POPULATED into the input, never
# auto-submitted). That exit-0 gate is what nvim-annex's mtime signal drives.
function claude --wraps claude --description 'claude-code with the Ctrl+G composer scoped to nvim-annex'
    _annex_editor claude $argv
end
