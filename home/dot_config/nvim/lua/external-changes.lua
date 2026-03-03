local M = {}

local ns = vim.api.nvim_create_namespace('external_changes')
local fade_ms = 10000
local pending_timers = {}

local function capture_before_reload()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].buftype ~= '' then return end
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if ok then
    vim.b[bufnr]._ec_pre_reload = table.concat(lines, '\n') .. '\n'
  end
end

local function on_post_reload()
  local bufnr = vim.api.nvim_get_current_buf()
  local old_text = vim.b[bufnr]._ec_pre_reload
  if not old_text then return end

  local ok, new_lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok then return end
  local new_text = table.concat(new_lines, '\n') .. '\n'

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  if pending_timers[bufnr] then
    pending_timers[bufnr]:stop()
    pending_timers[bufnr]:close()
    pending_timers[bufnr] = nil
  end

  local hunks = vim.diff(old_text, new_text, { result_type = 'indices' })

  if not hunks or #hunks == 0 then
    vim.b[bufnr]._ec_pre_reload = nil
    return
  end

  local total_new = #new_lines

  for _, hunk in ipairs(hunks) do
    local new_start = hunk[3]
    local new_count = hunk[4]

    if new_count > 0 then
      local old_count = hunk[2]
      local hl_group = old_count == 0 and 'DiffAdd' or 'DiffChange'

      for i = new_start, math.min(new_start + new_count - 1, total_new) do
        pcall(vim.api.nvim_buf_add_highlight, bufnr, ns, hl_group, i - 1, 0, -1)
      end
    end
  end

  vim.b[bufnr].externally_modified_at = vim.loop.now()
  vim.b[bufnr].externally_modified_hunks = #hunks
  pcall(function() require('lualine').refresh() end)

  local timer = vim.loop.new_timer()
  pending_timers[bufnr] = timer
  timer:start(fade_ms, 0, vim.schedule_wrap(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end
    pending_timers[bufnr] = nil
    timer:stop()
    timer:close()
  end))

  vim.b[bufnr]._ec_pre_reload = nil
end

function M.lualine_component()
  local modified_at = vim.b.externally_modified_at
  if not modified_at then return '' end

  local elapsed = vim.loop.now() - modified_at
  if elapsed < fade_ms then
    local hunks = vim.b.externally_modified_hunks or 0
    return '  ' .. hunks .. (hunks == 1 and ' change' or ' changes')
  end
  return ''
end

function M.setup()
  local augroup = vim.api.nvim_create_augroup('ExternalChanges', { clear = true })

  vim.opt.autoread = true

  vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold', 'CursorHoldI' }, {
    group = augroup,
    pattern = '*',
    command = 'checktime',
  })

  vim.api.nvim_create_autocmd('FileChangedShell', {
    group = augroup,
    pattern = '*',
    callback = capture_before_reload,
  })

  vim.api.nvim_create_autocmd('FileChangedShellPost', {
    group = augroup,
    pattern = '*',
    callback = on_post_reload,
  })
end

return M
