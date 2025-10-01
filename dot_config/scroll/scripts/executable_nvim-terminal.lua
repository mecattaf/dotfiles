-- Save as ~/.config/scroll/scripts/nvim-terminal.lua
-- Smart terminal launcher: IDE layout for nvim with proper working directory

local view = scroll.focused_view()

if not view then
  -- No focused view, launch regular terminal
  scroll.command(nil, 'exec kitty -e fish')
  return
end

local title = scroll.view_get_title(view)
local app_id = scroll.view_get_app_id(view)

-- Check if focused window is nvim (checking both title and app_id)
local is_nvim = false
if title and string.find(title, "nvim") then
  is_nvim = true
elseif app_id and (string.find(app_id, "nvim") or string.find(app_id, "neovim")) then
  is_nvim = true
end

if not is_nvim then
  -- Not in nvim, just launch regular terminal
  scroll.command(nil, 'exec kitty -e fish')
  return
end

-- We're in nvim, create IDE layout
local pid = scroll.view_get_pid(view)

-- Get the working directory of the nvim process
local cwd = nil
local cwd_handle = io.popen("readlink /proc/" .. pid .. "/cwd 2>/dev/null")
if cwd_handle then
  local result = cwd_handle:read("*a")
  cwd_handle:close()
  if result and result ~= "" then
    cwd = result:gsub("%s+$", "")  -- Remove trailing whitespace
  end
end

-- Fallback to home directory if we couldn't get the working directory
if not cwd or cwd == "" then
  cwd = os.getenv("HOME") or "~"
end

-- Store the nvim view for the callbacks
local data = { nvim_pid = pid, terminal_view = nil }

-- Callback for when new window is created
local id_map
local on_create = function(cbview, cbdata)
  local new_app_id = scroll.view_get_app_id(cbview)
  -- Check if the new window is our terminal
  if new_app_id == "kitty" then
    -- Store the terminal view
    cbdata.terminal_view = cbview
    -- Set terminal to 1/3 height and move it below nvim
    scroll.command(cbview, "set_size v 0.33333333; move down nomode")
    -- Remove this callback after we've found our terminal
    scroll.remove_callback(id_map)
  end
end

-- Callback for when nvim window is closed
local id_unmap
local on_destroy = function(cbview, cbdata)
  local destroyed_pid = scroll.view_get_pid(cbview)
  -- When nvim closes, also close the associated terminal
  if destroyed_pid == cbdata.nvim_pid then
    if cbdata.terminal_view then
      scroll.view_close(cbdata.terminal_view)
    end
    -- Remove this callback after nvim is destroyed
    scroll.remove_callback(id_unmap)
  end
end

-- Register callbacks
id_map = scroll.add_callback("view_map", on_create, data)
id_unmap = scroll.add_callback("view_unmap", on_destroy, data)

-- Escape the path properly for shell execution
local escaped_cwd = cwd:gsub("'", "'\\''")

-- Resize nvim to 2/3 height and launch terminal in the same directory
scroll.command(view, string.format('set_size v 0.66666667; exec kitty --directory \'%s\' -e fish', escaped_cwd))
