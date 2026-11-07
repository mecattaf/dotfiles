-- image.nvim1.5.1 uses its process stdout and ioctl FD1. A retained headless
-- server has neither a terminal nor terminal pixels. Keep the upstream image
-- backend, but route its writes through Nvim's native UI and query exact cell
-- pixels from the attached Kitty. No key/output proxy or approximate geometry.
local M = { prepared = false, bytes_sent = 0, query_count = 0, generation = 0 }
local api = vim.api
local query_name = 'kitty-query-agency_font_cell_size'
local query_hex = query_name:gsub('.', function(c) return string.format('%02x', string.byte(c)) end)
local fingerprints = {
  ['lua/image/backends/kitty/helpers.lua'] = '27430b1d95d7a1ad417fb709c4f8e38eeac7b0487d4933fe372931d5e89ea3c1',
  ['lua/image/utils/term.lua'] = '35a9feffded501a429e321c5b2455b30a26a2e7d00293be257ccc7faf6324c27',
  ['lua/image/backends/kitty/init.lua'] = '2ce48270ddd78ef881d0e4a0435ceb21bf0ab6139b94ef32c979819bfc074c7c',
  ['lua/image/utils/document.lua'] = '3a610de8b326f2a95d0eda4d5c52d8bc1a372b95fe49f1a216575d84d8f63aa9',
}

local function size()
  if not M.cell_width or not M.cell_height or #api.nvim_list_uis() == 0 then return nil end
  -- Nvim's shared grid, rather than one arbitrarily chosen UI's larger grid.
  local cols, rows = vim.o.columns, vim.o.lines
  if cols < 1 or rows < 1 then return nil end
  return { screen_x = cols * M.cell_width, screen_y = rows * M.cell_height,
    screen_cols = cols, screen_rows = rows, cell_width = M.cell_width, cell_height = M.cell_height }
end

local function write(payload)
  if type(payload) ~= 'string' or #payload == 0 then return end
  if #api.nvim_list_uis() == 0 then return end
  M.bytes_sent = M.bytes_sent + #payload
  api.nvim_ui_send(payload)
end

local function refresh()
  if not size() or not package.loaded.image then return end
  local image = require('image')
  local images = image.get_images()
  if #images > 0 then
    -- The stock backend's private transmit cache must be invalidated when a
    -- different terminal attaches, even when its rows/columns match the old UI.
    require('image/backends/kitty').clear(nil, false)
    for _, item in ipairs(images) do item:render() end
    M.retransmissions = (M.retransmissions or 0) + 1
  end
  -- The initial document scan can run before any UI/geometry exists. Upstream
  -- does not retain those unrendered images, so retry its own document hooks
  -- after the exact geometry reply. Keep this inside image integration groups;
  -- replaying every plugin's BufWinEnter would duplicate unrelated work.
  local groups, buffers = {}, {}
  for _, command in ipairs(api.nvim_get_autocmds({ event = 'BufWinEnter' })) do
    if command.group_name and command.group_name:match('^image%.nvim:') then groups[command.group] = true end
  end
  for _, window in ipairs(api.nvim_tabpage_list_wins(0)) do
    buffers[api.nvim_win_get_buf(window)] = true
  end
  for group in pairs(groups) do
    for buffer in pairs(buffers) do
      api.nvim_exec_autocmds('BufWinEnter', { group = group, buffer = buffer, modeline = false })
    end
  end
end

function M.query()
  if not M.prepared or #api.nvim_list_uis() == 0 then return end
  M.generation = M.generation + 1
  local generation = M.generation
  M.cell_width, M.cell_height = nil, nil
  M.query_count = M.query_count + 1
  api.nvim_ui_send('\027P+q' .. query_hex .. '\027\\')
  -- One bounded check for an explicit query, never an idle/prompt timer.
  vim.defer_fn(function()
    if generation == M.generation and not M.cell_width and #api.nvim_list_uis() > 0 then
      M.error = 'The attached Kitty did not provide exact cell geometry'
      vim.notify('Native image transport: ' .. M.error, vim.log.levels.WARN)
    end
  end, 1500)
end

function M.prepare()
  if M.prepared then return true end
  if not vim.env.DSH_EDITOR_STATE or vim.fn.has('ttyout') == 1 then return false end
  assert(type(api.nvim_ui_send) == 'function', 'native image transport needs Nvim0.12 or newer')
  assert(not package.loaded['image/utils/term'], 'native image adapter must load before image.nvim')
  for relative, expected in pairs(fingerprints) do
    local path = api.nvim_get_runtime_file(relative, false)[1]
    assert(path, 'image.nvim module is missing: ' .. relative)
    local file = assert(io.open(path, 'rb'))
    local contents = file:read('*a')
    file:close()
    assert(vim.fn.sha256(contents) == expected, 'image.nvim changed; qualify its native UI adapter: ' .. relative)
  end
  package.loaded['image/utils/term'] = { get_size = size, get_tty = function() return nil end }
  -- This temporary loader seam changes only the pinned helper's captured
  -- writer. Restore the shared libuv function even if require() fails.
  local uv = vim.loop
  local original = uv.new_tty
  uv.new_tty = function(fd, readable)
    if fd == 1 and not readable then return { write = function(_, payload) write(payload) end } end
    return original(fd, readable)
  end
  local ok, helpers = pcall(require, 'image/backends/kitty/helpers')
  uv.new_tty = original
  if not ok then error(helpers) end
  local graphics = helpers.write_graphics
  local codes = require('image/backends/kitty/codes')
  helpers.write_graphics = function(config, data)
    if data then
      -- The file is on NAS even if the server first started outside SSH.
      -- The local terminal receives bytes, never a nonexistent client path.
      config = vim.tbl_extend('force', {}, config, { transmit_medium = codes.control.transmit_medium.direct })
    end
    return graphics(config, data)
  end
  local group = api.nvim_create_augroup('KittyRemoteImages', { clear = true })
  api.nvim_create_autocmd('TermResponse', { group = group, callback = function()
    local response = vim.v.termresponse
    local value = response:match('^\027P1%+r' .. query_hex .. '=([%da-fA-F]+)')
    if not value or #value % 2 ~= 0 or #value > 128 then return end
    local decoded = value:gsub('..', function(pair) return string.char(tonumber(pair, 16)) end)
    local width, height = decoded:match('^(%d+),(%d+)$')
    width, height = tonumber(width), tonumber(height)
    if not width or not height or width < 1 or height < 1 or width > 1024 or height > 1024 then return end
    M.cell_width, M.cell_height, M.error = width, height, nil
    vim.schedule(refresh)
  end })
  api.nvim_create_autocmd({ 'UIEnter', 'VimResized', 'FocusGained' }, {
    group = group, callback = function() vim.schedule(M.query) end,
  })
  api.nvim_create_autocmd('UILeave', { group = group, callback = function()
    if #api.nvim_list_uis() == 0 then M.cell_width, M.cell_height = nil, nil end
  end })
  M.prepared = true
  vim.schedule(M.query)
  return true
end

function M.status()
  return { prepared = M.prepared, cell_width = M.cell_width, cell_height = M.cell_height,
    bytes_sent = M.bytes_sent, query_count = M.query_count, retransmissions = M.retransmissions or 0,
    error = M.error, size = size() }
end

return M
