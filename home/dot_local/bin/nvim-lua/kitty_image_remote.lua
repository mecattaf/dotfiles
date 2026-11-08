-- image.nvim1.5.1 uses its process stdout and ioctl FD1. A retained headless
-- server has neither a terminal nor terminal pixels. Keep the upstream image
-- backend, but route its writes through Nvim's native UI and query exact cell
-- pixels from the attached Kitty. No key/output proxy or approximate geometry.
local M = { prepared = false, bytes_sent = 0, query_count = 0, generation = 0,
  geometry = {}, pending = {}, pending_by_chan = {}, native_cell_placements = 0,
  full_resolution_transmits = 0, cpu_resizes_avoided = 0 }
local api = vim.api
local query_prefix = 'kitty-query-agency_font_cell_size_'
local current_image, backend_geometry
local fingerprints = {
  ['lua/image/backends/kitty/helpers.lua'] = '27430b1d95d7a1ad417fb709c4f8e38eeac7b0487d4933fe372931d5e89ea3c1',
  ['lua/image/utils/term.lua'] = '35a9feffded501a429e321c5b2455b30a26a2e7d00293be257ccc7faf6324c27',
  ['lua/image/backends/kitty/init.lua'] = '2ce48270ddd78ef881d0e4a0435ceb21bf0ab6139b94ef32c979819bfc074c7c',
  ['lua/image/utils/document.lua'] = '3a610de8b326f2a95d0eda4d5c52d8bc1a372b95fe49f1a216575d84d8f63aa9',
  ['lua/image/renderer.lua'] = 'f41233243668e6a0415be17f1d2d86fba18fdc559736be1e15a86bce6b406e9c',
}

local function native_uis()
  local result = {}
  for _, ui in ipairs(api.nvim_list_uis()) do
    if ui.stdout_tty then result[#result + 1] = ui end
  end
  table.sort(result, function(a, b) return a.chan < b.chan end)
  return result
end

local function anchor()
  local attached, present = native_uis(), {}
  for _, ui in ipairs(attached) do present[ui.chan] = true end
  for chan in pairs(M.geometry) do
    if not present[chan] then M.geometry[chan] = nil end
  end
  for chan, nonce in pairs(M.pending_by_chan) do
    if not present[chan] then M.pending[nonce], M.pending_by_chan[chan] = nil, nil end
  end
  if not present[M.anchor_chan] then M.anchor_chan = attached[1] and attached[1].chan or nil end
  local geometry = M.geometry[M.anchor_chan]
  M.cell_width, M.cell_height = geometry and geometry.width, geometry and geometry.height
  return attached
end

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

local function refresh_later()
  if M.refresh_pending then return end
  M.refresh_pending = true
  vim.schedule(function() M.refresh_pending = false; refresh() end)
end

function M.query()
  if not M.prepared then return end
  local attached = anchor()
  if #attached == 0 then return end
  M.generation = M.generation + 1
  local generation = M.generation
  for _, ui in ipairs(attached) do
    M.query_count = M.query_count + 1
    local nonce = string.format('%08x%08x', vim.fn.getpid(), M.query_count)
    local previous = M.pending_by_chan[ui.chan]
    if previous then M.pending[previous] = nil end
    M.pending_by_chan[ui.chan] = nonce
    M.pending[nonce] = { chan = ui.chan, generation = generation }
    local name = query_prefix .. nonce
    local encoded = name:gsub('.', function(c) return string.format('%02x', string.byte(c)) end)
    -- This is the documented native redraw event, addressed to one existing
    -- TUI channel. 0.12 TermResponse lacks chan, so the echoed nonce binds it.
    vim.rpcnotify(ui.chan, 'redraw', { 'ui_send', { '\027P+q' .. encoded .. '\027\\' } })
  end
  -- One bounded check for an explicit query, never an idle/prompt timer.
  vim.defer_fn(function()
    if generation == M.generation and not M.cell_width and #native_uis() > 0 then
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
  local backend = require('image/backends/kitty')
  local renderer = require('image/renderer')
  local original_render, original_backend_render = renderer.render, backend.render
  local processors = setmetatable({}, { __mode = 'k' })
  renderer.render = function(image)
    local processor = image.global_state.processor
    if not processors[processor] then
      local resize = processor.resize
      processor.resize = function(path, width, height, output)
        if current_image and current_image.global_state.backend.features.crop then
          -- Keep full source pixels. Each native Kitty scales them to its
          -- own font/DPI with KGP cell-relative placements, without blurry
          -- enlargement of a bitmap pre-shrunk for another attached UI.
          M.cpu_resizes_avoided = M.cpu_resizes_avoided + 1
          return path
        end
        return resize(path, width, height, output)
      end
      processors[processor] = true
    end
    local previous = current_image
    current_image = image
    local rendered, result = pcall(original_render, image)
    current_image = previous
    if not rendered then error(result) end
    return result
  end
  backend.render = function(image, x, y, width, height)
    local previous = backend_geometry
    backend_geometry = { image = image, width = width, height = height }
    local rendered, result = pcall(original_backend_render, image, x, y, width, height)
    backend_geometry = previous
    if not rendered then error(result) end
    return result
  end
  helpers.write_graphics = function(config, data)
    if data then
      -- The file is on NAS even if the server first started outside SSH.
      -- The local terminal receives bytes, never a nonexistent client path.
      config = vim.tbl_extend('force', {}, config, { transmit_medium = codes.control.transmit_medium.direct })
      if backend_geometry and backend.features.crop then
        data = backend_geometry.image.path
        M.full_resolution_transmits = M.full_resolution_transmits + 1
      end
    end
    if backend_geometry and backend.features.crop and config.action == codes.control.action.display then
      local context, image = backend_geometry, backend_geometry.image
      local width, height = context.width * M.cell_width, context.height * M.cell_height
      local crop_width, crop_height = config.display_width or width, config.display_height or height
      local scale_x, scale_y = image.image_width / width, image.image_height / height
      local left = math.floor((config.display_x or 0) * scale_x)
      local top = math.floor((config.display_y or 0) * scale_y)
      -- All attached native UIs share Nvim's logical grid/padding. KGP c/r
      -- scales and letterboxes that cell rectangle independently per Kitty,
      -- preserving aspect ratio even when the two fonts have different cells.
      config = vim.tbl_extend('force', {}, config, {
        display_columns = math.max(1, math.ceil(crop_width / M.cell_width)),
        display_rows = math.max(1, math.ceil(crop_height / M.cell_height)),
        display_x = left, display_y = top,
        display_width = math.min(image.image_width - left, math.ceil(crop_width * scale_x)),
        display_height = math.min(image.image_height - top, math.ceil(crop_height * scale_y)),
      })
      M.native_cell_placements = M.native_cell_placements + 1
    end
    return graphics(config, data)
  end
  local group = api.nvim_create_augroup('KittyRemoteImages', { clear = true })
  api.nvim_create_autocmd('TermResponse', { group = group, callback = function(event)
    local response = event.data and event.data.sequence or vim.v.termresponse
    local encoded_name, value = response:match('^\027P1%+r([%da-fA-F]+)=([%da-fA-F]+)')
    if not encoded_name or #encoded_name > 256 or #encoded_name % 2 ~= 0 then return end
    local name = encoded_name:gsub('..', function(pair) return string.char(tonumber(pair, 16)) end)
    local nonce = name:match('^kitty%-query%-agency_font_cell_size_([0-9a-f]+)$')
    local pending = nonce and M.pending[nonce]
    if not pending or #nonce ~= 16 then return end
    if event.data and event.data.chan and event.data.chan ~= pending.chan then return end
    if not value or #value % 2 ~= 0 or #value > 128 then return end
    local decoded = value:gsub('..', function(pair) return string.char(tonumber(pair, 16)) end)
    local width, height = decoded:match('^(%d+),(%d+)$')
    width, height = tonumber(width), tonumber(height)
    if not width or not height or width < 1 or height < 1 or width > 1024 or height > 1024 then return end
    M.geometry[pending.chan] = { width = width, height = height }
    M.pending[nonce], M.pending_by_chan[pending.chan], M.error = nil, nil, nil
    anchor()
    refresh_later()
  end })
  api.nvim_create_autocmd({ 'UIEnter', 'VimResized', 'FocusGained' }, {
    group = group, callback = function() vim.schedule(M.query) end,
  })
  api.nvim_create_autocmd('UILeave', { group = group, callback = function()
    vim.schedule(function() anchor(); M.query() end)
  end })
  M.prepared = true
  vim.schedule(M.query)
  return true
end

function M.status()
  local views = {}
  for chan, geometry in pairs(M.geometry) do
    views[#views + 1] = { chan = chan, width = geometry.width, height = geometry.height, anchor = chan == M.anchor_chan }
  end
  table.sort(views, function(a, b) return a.chan < b.chan end)
  return { prepared = M.prepared, cell_width = M.cell_width, cell_height = M.cell_height,
    bytes_sent = M.bytes_sent, query_count = M.query_count, retransmissions = M.retransmissions or 0,
    native_cell_placements = M.native_cell_placements, full_resolution_transmits = M.full_resolution_transmits,
    cpu_resizes_avoided = M.cpu_resizes_avoided, views = views, anchor_chan = M.anchor_chan,
    error = M.error, size = size() }
end

return M
