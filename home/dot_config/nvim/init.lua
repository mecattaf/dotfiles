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

