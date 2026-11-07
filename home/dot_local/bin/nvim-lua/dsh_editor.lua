-- Native Nvim owns the live editor; this module only checkpoints unsaved work.
-- Loaded explicitly by dsh-editor after the ordinary user config. Plain nvim,
-- $EDITOR subprocesses and Kitty scrollback overlays do not load it.
local M = {}
local api = vim.api
local uv = vim.uv
local timer
local state
local snapshots = {}
local restoring = false

local function write_atomic(path, contents)
  local temporary = path .. '.tmp'
  local descriptor = assert(uv.fs_open(temporary, 'w', 384)) -- 0600
  local ok, err = pcall(function()
    local offset = 0
    while offset < #contents do
      local written = assert(uv.fs_write(descriptor, contents:sub(offset + 1), offset))
      assert(written > 0, 'short recovery write')
      offset = offset + written
    end
    assert(uv.fs_fsync(descriptor))
  end)
  local closed, close_error = uv.fs_close(descriptor)
  assert(closed, close_error)
  if not ok then error(err) end
  assert(uv.fs_rename(temporary, path))
  -- A renamed snapshot is also durable across a clean host reboot; persist
  -- the directory entry, rather than only its file contents.
  local directory = assert(uv.fs_open(state, 'r', 448))
  local synced, sync_error = uv.fs_fsync(directory)
  assert(uv.fs_close(directory))
  assert(synced, sync_error)
end

local function error_notice(err)
  vim.notify('Editor recovery checkpoint failed: ' .. tostring(err), vim.log.levels.ERROR)
end

function M.checkpoint()
  if restoring or not state then return end
  local records = {}
  for _, buf in ipairs(api.nvim_list_bufs()) do
    local recoverable = vim.bo[buf].buftype == '' or vim.b[buf].dsh_recovery_original ~= nil
    if api.nvim_buf_is_loaded(buf) and recoverable and vim.bo[buf].modified then
      local name = api.nvim_buf_get_name(buf)
      -- A recovered buffer retains the original destination as metadata, while
      -- its display name makes it impossible to overwrite that file by :w.
      local original = vim.b[buf].dsh_recovery_original
      if original then name = original end
      local key = vim.b[buf].dsh_recovery_key or vim.fn.sha256(name ~= '' and name or ('unnamed:' .. buf))
      local tick = api.nvim_buf_get_changedtick(buf)
      local filename = key .. '.json'
      local previous = snapshots[buf]
      if not previous or previous.tick ~= tick or previous.key ~= key then
        write_atomic(state .. '/' .. filename, vim.json.encode({
          name = name, lines = api.nvim_buf_get_lines(buf, 0, -1, false),
          filetype = vim.bo[buf].filetype, endofline = vim.bo[buf].endofline,
          fileformat = vim.bo[buf].fileformat, saved_at = os.time(),
        }))
        snapshots[buf] = { tick = tick, key = key }
      end
      records[#records + 1] = filename
    end
  end
  -- Commit the index last. A crash during a checkpoint leaves the previous
  -- index, whose individual snapshots are each replaced atomically.
  write_atomic(state .. '/recovery.json', vim.json.encode({ version = 1, buffers = records }))
end

local function checkpoint()
  local ok, err = pcall(M.checkpoint)
  if not ok then error_notice(err) end
end

local function pending()
  if restoring then return end
  -- Typing only rearms an in-memory timer. No filesystem work runs in a
  -- keypress callback; checkpoint after two seconds of inactivity.
  timer:stop()
  timer:start(2000, 0, vim.schedule_wrap(checkpoint))
end

function M.recover()
  local manifest = state .. '/recovery.json'
  if vim.fn.filereadable(manifest) ~= 1 then return 0 end
  local data = vim.json.decode(table.concat(vim.fn.readfile(manifest), '\n'))
  assert(data.version == 1 and type(data.buffers) == 'table', 'unsupported recovery manifest')
  local recovered = 0
  restoring = true
  local ok, err = pcall(function()
    for _, filename in ipairs(data.buffers) do
      assert(filename:match('^%x+%.json$'), 'invalid recovery filename')
      local record = vim.json.decode(table.concat(vim.fn.readfile(state .. '/' .. filename), '\n'))
      local recovery_name = 'dsh-recovery://' .. filename:gsub('%.json$', '') .. '/' ..
        (record.name ~= '' and vim.fn.fnamemodify(record.name, ':t') or '[untitled]')
      if vim.fn.bufnr(recovery_name) ~= -1 then
        recovered = recovered + 1
      else
        local buf = api.nvim_create_buf(true, false)
        api.nvim_buf_set_name(buf, recovery_name)
        api.nvim_buf_set_lines(buf, 0, -1, false, record.lines)
        vim.bo[buf].filetype = record.filetype
        vim.bo[buf].fileformat = record.fileformat
        vim.bo[buf].endofline = record.endofline
        vim.bo[buf].modified = true
        vim.b[buf].dsh_recovery_original = record.name
        vim.b[buf].dsh_recovery_key = filename:gsub('%.json$', '')
        -- 'acwrite' refuses a bare :write; DshRecoverySave chooses a path.
        vim.bo[buf].buftype = 'acwrite'
        api.nvim_set_current_buf(buf)
        recovered = recovered + 1
      end
    end
  end)
  restoring = false
  if not ok then error(err) end
  return recovered
end

function M.setup()
  if M.configured then return end
  state = assert(vim.env.DSH_EDITOR_STATE, 'DSH_EDITOR_STATE is required')
  vim.fn.mkdir(state, 'p', 448)
  timer = assert(uv.new_timer())
  -- The normal config disables swaps. These editor daemons explicitly restore
  -- native crash recovery, with private per-directory files outside the repo.
  local swaps = state .. '/swap'
  vim.fn.mkdir(swaps, 'p', 448)
  vim.opt.directory = { swaps .. '//' }
  vim.opt.swapfile = true
  vim.opt.updatecount = 200
  vim.opt.hidden = true
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if vim.bo[buf].buftype == '' then vim.bo[buf].swapfile = true end
  end
  local group = api.nvim_create_augroup('DshEditorRecovery', { clear = true })
  api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'BufModifiedSet' }, { group = group, callback = pending })
  api.nvim_create_autocmd({ 'InsertLeave', 'BufLeave', 'BufWritePost', 'UILeave' }, { group = group, callback = checkpoint })
  api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      checkpoint()
      timer:stop()
      timer:close()
    end,
  })
  api.nvim_create_user_command('DshCheckpoint', checkpoint, { desc = 'Checkpoint unsaved editor buffers outside source files' })
  api.nvim_create_user_command('DshRecover', function()
    local ok, count = pcall(M.recover)
    if not ok then error_notice(count) else vim.notify('Recovered ' .. count .. ' buffer(s); :DshRecoverySave <path> chooses a destination') end
  end, { desc = 'Open unsaved checkpoints as protected recovery buffers' })
  api.nvim_create_user_command('DshRecoverySave', function(options)
    local buf = api.nvim_get_current_buf()
    assert(vim.b[buf].dsh_recovery_original ~= nil, 'this is not a recovered buffer')
    vim.bo[buf].buftype = ''
    local ok, err = pcall(vim.cmd.saveas, { args = { options.args }, bang = options.bang })
    if not ok then
      vim.bo[buf].buftype = 'acwrite'
      error(err)
    end
    vim.b[buf].dsh_recovery_original = nil
    vim.b[buf].dsh_recovery_key = nil
    checkpoint()
  end, { nargs = 1, complete = 'file', bang = true, desc = 'Save this recovered buffer to an explicitly chosen destination' })
  M.configured = true
  -- A crash/reboot is distinct from a normal detach: offer the old checkpoint
  -- before any new idle checkpoint can replace its index. Nothing writes to
  -- the original files, and recovered buffers cannot be saved accidentally.
  if vim.fn.filereadable(state .. '/recovery.json') == 1 then
    local ok, count = pcall(M.recover)
    if not ok then
      error_notice(count)
    elseif count > 0 then
      vim.schedule(function()
        vim.notify('Recovered ' .. count .. ' unsaved buffer(s). :DshRecoverySave <path> chooses where to keep them.')
      end)
    end
  end
  vim.g.dsh_editor_ready = 1
end

return M
