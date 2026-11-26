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
vim.env.XDG_STATE_HOME = tmp .. '/state'
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
-- Exercise the real launcher entry and JSON boundary while reusing a mock
-- native tunnel. No SSH command or UI switch is sent by this isolated test.
local originals = { servers = vim.fn.serverlist, connect = vim.fn.sockconnect,
  close = vim.fn.chanclose, rpc = vim.rpcrequest, command = vim.cmd.connect }
local connected
local tunnel = '/tmp/nvim-ssh.nas.ABCD'
vim.fn.serverlist = function(opts) assert(opts.peer); return { tunnel } end
vim.fn.sockconnect = function(kind, socket) assert(kind == 'pipe' and socket == tunnel); return 99 end
vim.fn.chanclose = function(channel) assert(channel == 99) end
vim.rpcrequest = function(channel, opts, method, code, args)
  assert(channel == 99 and opts.timeout == 5000 and method == 'nvim_exec_lua')
  assert(args[1].directory == project and args[1].files[1] == "quoted ' file.md")
  return true
end
vim.cmd.connect = function(opts) connected = opts.args[1] end
vim.env.NVIM_REMOTE_REQUEST = vim.json.encode({ directory = project, files = { "quoted ' file.md" }, commands = {} })
remote.start()
assert(connected == tunnel and vim.env.NVIM_REMOTE_REQUEST == nil)
vim.fn.serverlist, vim.fn.sockconnect, vim.fn.chanclose = originals.servers, originals.connect, originals.close
vim.rpcrequest, vim.cmd.connect = originals.rpc, originals.command
-- A changed internal command-vector seam must fail before any preflight.
local ssh = require('vim.net._ssh')
local old_ssh, old_exit, old_echo, old_system = ssh.ssh_cmd, vim.cmd.cquit, vim.api.nvim_echo, vim.system
local rejected, message
ssh.ssh_cmd = 'ssh'
vim.fn.serverlist = function() return {} end
vim.cmd.cquit = function() rejected = true end
vim.api.nvim_echo = function(chunks) message = chunks[1][1] end
vim.system = function() error('preflight ran before hook validation') end
vim.env.NVIM_REMOTE_REQUEST = vim.json.encode({ directory = project, files = {}, commands = {} })
remote.start()
assert(rejected and message:find('SSH command hook changed', 1, true))
ssh.ssh_cmd, vim.cmd.cquit, vim.api.nvim_echo, vim.system = old_ssh, old_exit, old_echo, old_system
vim.fn.serverlist = originals.servers
print('native file arguments, unsaved buffers, dd OSC52 and launcher entry: passed')
vim.cmd('qall!')
