-- Run with runtime-test -- nvim-0.13 --headless -u NONE -l this.lua CHECKOUT.
-- UI bytes are captured here; this test never touches a desktop clipboard.
local root = assert(arg[1])
package.path = package.path .. ';' .. root .. '/home/dot_local/bin/nvim-lua/?.lua'
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
local project = tmp .. "/it's a $(touch NEVER) `touch NEVER` directory"
vim.fn.mkdir(project, 'p')
local file = project .. "/a 'quoted' [literal];file.md"
vim.fn.writefile({ 'one', 'two' }, file)
local remote = require('native_remote')
remote.open_files({ directory = project, files = { vim.fs.basename(file) }, commands = {} })
assert(vim.fn.getcwd() == project)
assert(vim.api.nvim_buf_get_name(0) == file)
local buffer = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'unsaved buffer', 'still here' })
remote.open_files({ directory = project, files = { vim.fs.basename(file) }, commands = {} })
assert(vim.api.nvim_get_current_buf() == buffer)
assert(vim.bo.modified)
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { 'unsaved buffer', 'still here' }))
remote.open_files({ directory = project, files = { 'other file.md' }, commands = {} })
assert(vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] == 'unsaved buffer')
assert(vim.api.nvim_get_option_value('modified', { buf = buffer }))

vim.env.NVIM_APPNAME = 'nvim-remote'
vim.env.SSH_TTY, vim.env.HERDR_ENV, vim.env.DSH_EDITOR_ROOT = nil, nil, nil
local sent = {}
vim.api.nvim_ui_send = function(bytes) sent[#sent + 1] = bytes end
dofile(root .. '/home/dot_config/nvim/lua/options.lua')
assert(vim.g.clipboard.name == 'osc52-copy-only')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'clipboard line', 'kept line' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd('normal! dd')
assert(table.concat(sent):find('\027]52;c;' .. vim.base64.encode('clipboard line\n'), 1, true))
assert(vim.api.nvim_get_current_line() == 'kept line')
local before = #sent
vim.cmd('normal! p')
assert(#sent == before, 'cached put must not query the clipboard')
assert(vim.api.nvim_get_current_line() == 'clipboard line')
assert(vim.fn.filereadable(project .. '/NEVER') == 0)
print('native file arguments, unsaved buffers and dd OSC52: passed')
vim.cmd('qall!')
