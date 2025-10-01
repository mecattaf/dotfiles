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
  if not parent_pid then return false end
  
  -- Use pgrep to find all descendants and check if any are nvim
  local handle = io.popen(string.format("pgrep -P %d 2>/dev/null", parent_pid))
  if not handle then return false end
  
  local children = handle:read("*a")
  handle:close()
  
  if not children or children == "" then return false end
  
  -- Check each child process
  for child_pid in children:gmatch("%S+") do
    -- Get the command name
    local cmd_handle = io.popen(string.format("ps -p %s -o comm= 2>/dev/null", child_pid))
    if cmd_handle then
      local cmd = cmd_handle:read("*a")
      cmd_handle:close()
      
      -- Check if this process is nvim or vim
      if cmd and (cmd:match("nvim") or cmd:match("^vim$")) then
        return true, child_pid
      end
      
      -- Recursively check children
      if has_nvim_running(tonumber(child_pid)) then
        return true
      end
    end
  end
  
  return false
end

-- Check if this is a kitty terminal running nvim
local is_nvim = false
if app_id == "kitty" and pid then
  is_nvim = has_nvim_running(pid)
end

if not is_nvim then
  -- Not in nvim, just launch regular terminal
  scroll.command(nil, 'exec kitty -e fish')
  return
end

-- We're in nvim, create IDE layout
-- Get the working directory of the kitty process (which will be nvim's cwd)
local cwd = nil
local cwd_handle = io.popen(string.format("readlink /proc/%d/cwd 2>/dev/null", pid))
if cwd_handle then
  local result = cwd_handle:read("*a")
  cwd_handle:close()
  if result and result ~= "" then
    cwd = result:gsub("%s+$", "")
  end
end

-- Fallback to home directory
if not cwd or cwd == "" then
  cwd = os.getenv("HOME") or "~"
end

-- Store data for callbacks
local data = { nvim_pid = pid, terminal_view = nil }

-- Callback for when new window is created
local id_map
local on_create = function(cbview, cbdata)
  local new_app_id = scroll.view_get_app_id(cbview)
  -- Check if the new window is our terminal
  if new_app_id == "kitty" then
    cbdata.terminal_view = cbview
    -- Set terminal to 1/3 height and move it below nvim
    scroll.command(cbview, "set_size v 0.33333333; move down nomode")
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
