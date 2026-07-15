-- claude_slash_highlight.lua — lightweight `/command` highlight, same
-- filetype gate as the claude_slash blink.cmp source (markdown/text/
-- gitcommit) but otherwise UNENTANGLED from it: this only decorates text
-- that already looks like a slash command, it does not read the palette
-- cache or know anything about completion. Deliberately its own module.
--
-- Lives in the same live-editable ~/.local/bin/nvim-lua/ dir as
-- claude_slash.lua (see that file's header for the hosting rationale) and is
-- required from init.lua, AFTER the 'plugins' module so package.path already
-- has the nvim-lua dir on it (plugins.lua.in is what appends it).
local M = {}

local FILETYPES = { markdown = true, text = true, gitcommit = true }

-- \/ + at least one word char, then any run of word/hyphen/underscore chars
-- — matches "/deep-research", "/model", "/code-review", etc. Deliberately
-- the same shape as the '/' + [%w_-]* the blink source itself accepts.
local PATTERN = [[\/\w[A-Za-z0-9_-]*]]

local function apply_hl()
  vim.api.nvim_set_hl(0, "ClaudeSlashCommand", { link = "Special" })
end

-- Colorscheme changes (catppuccin's :colorscheme call in plugins.lua.in)
-- clear ad-hoc highlight links, so reapply on every ColorScheme event too.
local function sync_match(filetype)
  local id = vim.w.claude_slash_hl_id
  if FILETYPES[filetype] then
    if not id then
      local ok, new_id = pcall(vim.fn.matchadd, "ClaudeSlashCommand", PATTERN, 10)
      if ok then
        vim.w.claude_slash_hl_id = new_id
      end
    end
  elseif id then
    pcall(vim.fn.matchdelete, id)
    vim.w.claude_slash_hl_id = nil
  end
end

function M.setup()
  apply_hl()
  local group = vim.api.nvim_create_augroup("claude_slash_highlight", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = apply_hl,
  })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function()
      sync_match(vim.bo.filetype)
    end,
  })
end

return M
