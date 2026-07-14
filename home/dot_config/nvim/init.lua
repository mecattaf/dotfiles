local api = vim.api

-- Prevent git from opening /dev/tty for credential prompts inside nvim
vim.env.GIT_TERMINAL_PROMPT = "0"

local modules = {
  'options',
  'mappings',
  'plugins',
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

-- Kitty annex pass-through marker (dotfiles#50). The Ctrl+B kitten cannot see
-- that nvim is running when nvim is launched by hand inside a zmx session: the
-- kitty-visible foreground process is the `zmx attach <sess> fish` CLIENT, and
-- nvim runs server-side (invisible to kitty). So nvim announces itself to kitty
-- via a per-window user-var (SetUserVar OSC), which rides nvim's stdout through
-- zmx to the owning kitty window for free. annex_toggle.py reads var:nvim=1 and
-- passes Ctrl+B / Ctrl+Shift+B through to nvim instead of opening the annex.
-- Guarded to kitty (KITTY_WINDOW_ID); other terminals consume/ignore the OSC.
-- Value is base64 (kitty requires it): "1" = "MQ==", empty clears the var.
local function kitty_annex_mark(b64)
  if not vim.env.KITTY_WINDOW_ID then return end
  local ok, out = pcall(function() return io.stdout end)
  if not ok or not out then return end
  out:write("\027]1337;SetUserVar=nvim=" .. b64 .. "\027\\")
  out:flush()
end
api.nvim_create_autocmd({"VimEnter", "VimResume"}, {
  callback = function() kitty_annex_mark("MQ==") end,  -- set nvim=1
})
api.nvim_create_autocmd({"VimLeavePre", "VimSuspend"}, {
  callback = function() kitty_annex_mark("") end,       -- clear
})

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

