-- Save as ~/.config/scroll/scripts/smart-marks.lua
-- Smart marks system using scroll's Lua API

local action = arg[1]
local mark_num = arg[2]

if not action then
    print("Usage: lua smart-marks.lua {toggle|clear|show|clear-all} [mark_number]")
    return
end

local mark_prefix = "quickmark"

if action == "toggle" then
    local mark_name = mark_prefix .. mark_num
    local focused = scroll.focused_container()
    
    if not focused then
        return
    end
    
    -- Try to focus the mark first (if it exists, we'll jump to it)
    local results = scroll.command(nil, string.format('[con_mark="%s"] focus', mark_name))
    
    -- Check if the command succeeded (mark exists and we jumped)
    if results and results[1] and results[1].success then
        -- We jumped to an existing mark - flash border for feedback
        scroll.command(nil, "border pixel 3")
        os.execute("sleep 0.2")
        scroll.command(nil, "border pixel 1")
    else
        -- Mark doesn't exist - set it on current container
        scroll.command(focused, "mark --add " .. mark_name)
        
        -- Get info about what we marked
        local view = scroll.focused_view()
        if view then
            local app_id = scroll.view_get_app_id(view) or "unknown"
            local title = scroll.view_get_title(view) or "untitled"
            -- Sanitize title for shell
            title = title:gsub("'", "'\\''"):sub(1, 50)
            os.execute(string.format("notify-send 'Mark %s Set' '%s - %s' -t 1500", 
                mark_num, app_id, title))
        end
    end
    
elseif action == "clear" then
    local mark_name = mark_prefix .. mark_num
    -- Use scroll command to clear the mark
    local results = scroll.command(nil, string.format('[con_mark="%s"] unmark %s', mark_name, mark_name))
    
    if results and results[1] and results[1].success then
        os.execute(string.format("notify-send 'Mark %s Cleared' -t 1500", mark_num))
    end
    
elseif action == "show" then
    local mark_name = mark_prefix .. mark_num
    -- Try to focus the marked container
    local results = scroll.command(nil, string.format('[con_mark="%s"] focus', mark_name))
    
    if results and results[1] and results[1].success then
        -- Show in overview mode briefly
        scroll.command(nil, "scale_workspace overview")
        os.execute("sleep 1")
        scroll.command(nil, "scale_workspace reset")
    else
        os.execute(string.format("notify-send 'Mark %s Not Set' -t 1000", mark_num))
    end
    
elseif action == "clear-all" then
    -- Clear all marks from 0-9
    for i = 0, 9 do
        local mark_name = mark_prefix .. tostring(i)
        scroll.command(nil, string.format('[con_mark="%s"] unmark %s', mark_name, mark_name))
    end
    os.execute("notify-send 'All Marks Cleared' -t 1500")
end
