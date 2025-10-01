-- Smart terminal launcher: IDE layout for nvim with proper working directory

local view = scroll.focused_view()

if not view then
  -- No focused view, launch regular terminal
  scroll.command(nil, 'exec kitty -e fish')
  return
end

local app_id = scroll.view_get_app_id(view)
local pid = scroll.view_get_pid(view)

-- Function to check if nvim is running as a child of this PID
local function has_nvim_running(parent_pid)
  if not parent_pid then return false, nil end
  
  local handle = io.popen(string.format("pgrep -P %d 2>/dev/null", parent_pid))
  if not handle then return false, nil end
  
  local children = handle:read("*a")
  handle:close()
  
  if not children or children == "" then return false, nil end
  
  for child_pid in children:gmatch("%S+") do
    local cmd_handle = io.popen(string.format("ps -p %s -o comm= 2>/dev/null", child_pid))
    if cmd_handle then
      local cmd = cmd_handle:read("*a")
      cmd_handle:close()
      
      if cmd and (cmd:match("nvim") or cmd:match("^vim$")) then
        return true, tonumber(child_pid)
      end
      
      -- Recursively check children
      local found, nvim_pid = has_nvim_running(tonumber(child_pid))
      if found then
        return true, nvim_pid
      end
    end
  end
  
  return false, nil
end

-- Check if this is a kitty terminal running nvim
local is_nvim = false
local nvim_pid = nil
if app_id == "kitty" and pid then
  is_nvim, nvim_pid = has_nvim_running(pid)
end

if not is_nvim then
  -- Not in nvim, just launch regular terminal
  scroll.command(nil, 'exec kitty -e fish')
  return
end

-- We're in nvim, create IDE layout
-- Get the working directory from the nvim process
local cwd = nil
if nvim_pid then
  local cwd_handle = io.popen(string.format("readlink /proc/%d/cwd 2>/dev/null", nvim_pid))
  if cwd_handle then
    local result = cwd_handle:read("*a")
    cwd_handle:close()
    if result and result ~= "" then
      cwd = result:gsub("%s+$", "")
    end
  end
end

-- Fallback: try kitty's working directory if nvim's wasn't found
if (not cwd or cwd == "") and pid then
  local cwd_handle = io.popen(string.format("readlink /proc/%d/cwd 2>/dev/null", pid))
  if cwd_handle then
    local result = cwd_handle:read("*a")
    cwd_handle:close()
    if result and result ~= "" then
      cwd = result:gsub("%s+$", "")
    end
  end
end

if not cwd or cwd == "" then
  cwd = os.getenv("HOME") or "~"
end

-- Escape the path for shell execution
local escaped_cwd = cwd:gsub("'", "'\\''")

-- Build the kitty command with directory and fish shell
local kitty_cmd = string.format("exec kitty --directory '%s' -e fish", escaped_cwd)

-- Callback data
local data = {}
data.pid = pid

local id_map
local id_unmap

local on_create = function(cbview, cbdata)
  if scroll.view_get_app_id(cbview) == "kitty" then
    cbdata.view = cbview
    local container = scroll.view_get_container(cbview)
    -- Terminal should already be below nvim due to set_mode v, just resize it
    scroll.command(container, "set_size v 0.33333333")
    -- Restore horizontal mode for normal workflow
    scroll.command(nil, "set_mode h")
  end
  scroll.remove_callback(id_map)
end

local on_destroy = function(cbview, cbdata)
  if scroll.view_get_pid(cbview) == cbdata.pid then
    if cbdata.view then
      scroll.view_close(cbdata.view)
    end
  end
  scroll.remove_callback(id_unmap)
end

id_map = scroll.add_callback("view_map", on_create, data)
id_unmap = scroll.add_callback("view_unmap", on_destroy, data)

-- Resize nvim and launch terminal
-- Set mode to vertical so the terminal is added to the current column (below nvim)
scroll.command(nil, 'set_mode v; set_size v 0.66666667; ' .. kitty_cmd)
