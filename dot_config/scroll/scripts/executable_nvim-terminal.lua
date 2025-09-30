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
if title and (string.find(title, "^nvim") or string.find(title, "neovim") or string.find(title, "NVIM")) then
  is_nvim = true
elseif app_id and string.find(app_id, "nvim") then
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
local cwd = "~"  -- Default to home if we can't get the directory
local cwd_handle = io.popen("readlink /proc/" .. pid .. "/cwd 2>/dev/null")
if cwd_handle then
  local result = cwd_handle:read("*a")
  cwd_handle:close()
  if result and result ~= "" then
    cwd = result:gsub("%s+$", "")  -- Remove trailing whitespace
  end
end

-- Store the nvim window's PID for the callbacks
local data = { pid = pid, view = nil }

-- Callback for when new window is created
local id_map
local on_create = function(cbview, cbdata)
  local new_app_id = scroll.view_get_app_id(cbview)
  -- Check if the new window is our terminal
  if new_app_id == "kitty" then
    cbdata.view = cbview
    -- Set terminal to 1/3 height and move it below nvim
    scroll.command(nil, "set_size v 0.33333333; move left nomode")
  end
  scroll.remove_callback(id_map)
end

-- Callback for when nvim window is closed
local id_unmap
local on_destroy = function(cbview, cbdata)
  -- When nvim closes, also close the associated terminal
  if scroll.view_get_pid(cbview) == cbdata.pid then
    if cbdata.view then
      scroll.view_close(cbdata.view)
    end
  end
  scroll.remove_callback(id_unmap)
end

-- Register callbacks
id_map = scroll.add_callback("view_map", on_create, data)
id_unmap = scroll.add_callback("view_unmap", on_destroy, data)

-- Resize nvim to 2/3 height and launch terminal in the same directory
-- Escape the path properly for shell execution
cwd = cwd:gsub('"', '\\"')
scroll.command(nil, string.format('set_size v 0.66666667; exec kitty --directory "%s" -e fish', cwd))
