-- A remote editor cannot be identified by Kitty's local foreground argv (it
-- only sees ssh). Announce it through Kitty's own per-window user variables.
local M = {}

function M.setup()
  if not vim.env.KITTY_WINDOW_ID and vim.env.TERM ~= 'xterm-kitty' then return end
  local function mark(value)
    vim.api.nvim_ui_send('\027]1337;SetUserVar=nvim=' .. value .. '\027\\')
  end
  local group = vim.api.nvim_create_augroup('KittyEditorIdentity', { clear = true })
  vim.api.nvim_create_autocmd({ 'VimEnter', 'VimResume', 'UIEnter' }, {
    group = group, callback = function() mark('MQ==') end,
  })
  vim.api.nvim_create_autocmd({ 'VimLeavePre', 'VimSuspend' }, {
    group = group, callback = function() mark('') end,
  })
end

return M
