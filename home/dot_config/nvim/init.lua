local api = vim.api

-- Prevent git from opening /dev/tty for credential prompts inside nvim
vim.env.GIT_TERMINAL_PROMPT = "0"

-- Live-editable lua modules dir (~/.local/bin/nvim-lua, a whole-dir out-of-
-- store symlink into the dotfiles repo — see home.nix's `home.file
-- ".local/bin"`). plugins.lua.in also appends this same path (for blink.cmp's
-- lazily-required "claude_slash" source module); it is set here TOO, redundantly
-- but harmlessly, so init.lua's own require('claude_slash_highlight') below
-- never depends on plugins.lua having been rebuilt with that line yet.
package.path = package.path .. ";" .. vim.env.HOME .. "/.local/bin/nvim-lua/?.lua"

local modules = {
  'options',
  'mappings',
  'plugins',
  'claude_slash_highlight', -- see claude_slash_highlight.lua's own header
  'directory-watcher',
  'hotreload',
  'diffview-watcher',
  'external-changes',
}

for _, a in ipairs(modules) do
  local ok, mod = pcall(require, a)
  if not ok then
    error("Error calling " .. a .. mod)
  elseif type(mod) == 'table' and mod.setup then
    mod.setup()
  end
end

-- Auto commands
api.nvim_create_autocmd({"TermOpen", "TermEnter"}, {
  pattern = "term://*",
  command = "setlocal nonumber norelativenumber signcolumn=no | setfiletype term",
})

api.nvim_create_autocmd("BufEnter", {
  pattern = "term://*",
  command = "startinsert"
})

api.nvim_create_autocmd("VimLeave", {
  command = "set guicursor=a:ver20",
})

