-- Only launch glue: persistence, discovery, SSH, reconnect and UI transport
-- belong to Neovim 0.13. There is no editor daemon or terminal-holder backend.
local M = {}
local host = 'nas'
local marker = 'native_nvim_directory'

local function request(socket, code, args)
  local ok, channel = pcall(vim.fn.sockconnect, 'pipe', socket, { rpc = true, trust = false })
  if not ok or channel == 0 then return nil end
  local result = { pcall(vim.rpcrequest, channel, { timeout = 5000 }, 'nvim_exec_lua', code, args or {}) }
  pcall(vim.fn.chanclose, channel)
  if result[1] then return result[2] end
end

local function canonical(directory)
  local path = vim.uv.fs_realpath(directory)
  assert(path and vim.fn.isdirectory(path) == 1, 'NAS directory does not exist: ' .. directory)
  return path
end

local function open_files(data)
  data.directory = canonical(data.directory)
  vim.g[marker] = data.directory
  vim.api.nvim_set_current_dir(data.directory)
  if #data.files > 0 then
    local files = vim.tbl_map(function(file)
      return vim.fs.normalize(vim.fs.abspath(file, { cwd = data.directory }))
    end, data.files)
    -- :hide switches buffers without discarding unsaved text. Reopening the
    -- same name selects its existing modified buffer; never :edit! or reload.
    for _, file in ipairs(files) do
      vim.cmd('argadd ' .. vim.fn.fnameescape(file))
    end
    local buffer = vim.fn.bufadd(files[1])
    if vim.api.nvim_buf_is_loaded(buffer) then
      vim.api.nvim_set_current_buf(buffer)
    else
      vim.fn.bufload(buffer)
      vim.api.nvim_set_current_buf(buffer)
    end
  end
  for _, command in ipairs(data.commands) do vim.cmd(command) end
  -- This also runs over RPC before the next UI attaches. Set the actual
  -- channel explicitly rather than :detach! on the request's non-UI channel.
  local function detachable()
    for _, ui in ipairs(vim.api.nvim_list_uis()) do
      vim.api.nvim_chan_set(ui.chan, { detach = true })
    end
  end
  vim.api.nvim_create_autocmd('UIEnter', {
    group = vim.api.nvim_create_augroup('NativeRemoteEditor', { clear = true }),
    callback = detachable,
  })
  detachable()
end

-- Runs on the NAS after its normal configuration and native UI are ready.
function M.open(data)
  data.directory = canonical(data.directory)
  local candidates = {}
  for _, socket in ipairs(vim.fn.serverlist({ peer = true })) do
    if socket ~= vim.v.servername then
      local info = request(socket, "return {vim.g.native_nvim_directory, vim.v.useractive}")
      if info and info[1] == data.directory then
        candidates[#candidates + 1] = { socket = socket, active = info[2] or 0 }
      end
    end
  end
  table.sort(candidates, function(a, b) return a.active > b.active end)
  if candidates[1] then
    local socket = candidates[1].socket
    local opened = request(socket, "require('native_remote').open_files(...); return true", { data })
    assert(opened, 'Could not open files in the retained NAS editor')
    -- Native :connect relinks its SSH tunnel to the retained server, detaches
    -- stale UIs and closes this empty bootstrap. Neovim owns all lifetimes.
    -- Incoming socket UIs default detachable in 0.13. Only this disposable
    -- bootstrap must opt out, otherwise :connect leaves an empty server.
    for _, ui in ipairs(vim.api.nvim_list_uis()) do
      vim.api.nvim_chan_set(ui.chan, { detach = false })
    end
    vim.cmd.connect({ args = { socket } })
  else
    open_files(data)
  end
end

M.open_files = open_files

local function install_open(socket, data)
  return request(socket, [[
    local data = ...
    vim.api.nvim_create_autocmd('UIEnter', { once = true, callback = function()
      vim.schedule(function() require('native_remote').open(data) end)
    end })
    return true
  ]], { data })
end

function M.start()
  local raw = vim.env.NVIM_REMOTE_REQUEST
  vim.env.NVIM_REMOTE_REQUEST = nil
  local ok, error = pcall(function()
    assert(vim.fn.has('nvim-0.13') == 1, 'native remote vi requires Neovim 0.13 on both hosts')
    local data = vim.json.decode(assert(raw, 'missing native editor request'))
    local before = {}
    -- Reuse a native local tunnel when it still exists. On a new laptop or a
    -- broken link, the native SSH opening below discovers the NAS server.
    for _, socket in ipairs(vim.fn.serverlist({ peer = true })) do
      before[socket] = true
      if socket:match('/nvim%-ssh%.' .. host .. '%.%x+$') then
        local same = request(socket, [[
          local data = ...
          if vim.g.native_nvim_directory ~= vim.uv.fs_realpath(data.directory) then return false end
          require('native_remote').open_files(data)
          return true
        ]], { data })
        if same then
          vim.cmd.connect({ args = { socket } })
          return
        end
      end
    end
    -- NixOS must use its declared remote binary, not a downloaded glibc
    -- release. Check the non-login PATH that native :connect itself will use.
    local remote = vim.system({ 'ssh', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
                                host, 'nvim --version' }, { text = true }):wait(15000)
    local version = remote.code == 0 and vim.version.parse(remote.stdout or '')
    assert(version and vim.version.ge(version, vim.version()),
      'NAS must provide Neovim >= the local version; update the fleet rather than auto-installing on NixOS')
    -- The documented command is synchronous until the native tunnel exists;
    -- the UI switch is queued. Set the request through public RPC before that
    -- switch. URI paths are not cwd/file arguments in Neovim 0.13.
    vim.cmd.connect({ args = { 'ssh://' .. host } })
    local sockets = {}
    for _, socket in ipairs(vim.fn.serverlist({ peer = true })) do
      if not before[socket] and socket:match('/nvim%-ssh%.' .. host .. '%.%x+$') then
        sockets[#sockets + 1] = socket
      end
    end
    assert(#sockets == 1, 'SSH connection cancelled, failed, or did not expose one native tunnel')
    assert(install_open(sockets[1], data), 'Could not pass the file request to the NAS editor')
  end)
  if not ok then
    vim.api.nvim_echo({ { 'vi: ' .. tostring(error), 'ErrorMsg' } }, true, {})
    vim.cmd.cquit({ args = { '2' } })
  end
end

return M
