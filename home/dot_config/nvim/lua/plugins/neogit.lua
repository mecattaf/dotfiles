local present, neogit = pcall(require, "neogit")

if not present then
  return
end

neogit.setup({
  -- Auto-fetch on open
  disable_commit_confirmation = false,
  auto_refresh = true,
  kind = "tab",  -- Opens in new tab
  signs = {
    section = { "", "" },
    item = { "", "" },
    hunk = { "", "" },
  },
  integrations = {
    diffview = true,
    telescope = true,
  },
  -- Use Telescope for branch selection
  use_telescope = true,
  telescope_sorter = function()
    return require("telescope").extensions.fzf.native_fzf_sorter()
  end,
})

-- Smart auto-fetch when opening Neogit
local neogit_augroup = vim.api.nvim_create_augroup("NeogitCustom", { clear = true })

-- Track fetch status per repository
local fetch_cache = {}
local fetch_in_progress = {}

local function get_git_root()
  local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub('\n', '')
  if vim.v.shell_error == 0 and git_root ~= "" then
    return git_root
  end
  return nil
end

local function should_fetch()
  local git_root = get_git_root()
  if not git_root then
    return false
  end
  
  -- Don't fetch if already in progress
  if fetch_in_progress[git_root] then
    return false, git_root
  end
  
  local current_time = os.time()
  local last_fetch = fetch_cache[git_root]
  
  -- Only fetch if we haven't fetched in the last 5 minutes (300 seconds)
  if not last_fetch or (current_time - last_fetch > 300) then
    return true, git_root
  end
  
  return false, git_root
end

-- Use the correct event: NeogitStatusRefreshed
vim.api.nvim_create_autocmd("User", {
  pattern = "NeogitStatusRefreshed",
  group = neogit_augroup,
  callback = function()
    local should_do_fetch, git_root = should_fetch()
    
    if should_do_fetch and git_root then
      -- Mark as in progress
      fetch_in_progress[git_root] = true
      fetch_cache[git_root] = os.time()
      
      -- Run fetch in background without blocking UI
      vim.defer_fn(function()
        vim.notify("Fetching latest changes...", vim.log.levels.INFO, {
          title = "Neogit",
          timeout = 1500,
          animate = false,
        })
        
        -- Use async job to avoid blocking
        vim.fn.jobstart({"git", "fetch", "--all", "--quiet"}, {
          cwd = git_root,
          on_exit = function(_, exit_code)
            vim.schedule(function()
              fetch_in_progress[git_root] = false
              
              if exit_code == 0 then
                vim.notify("Fetch complete", vim.log.levels.INFO, {
                  title = "Neogit",
                  timeout = 1000,
                  animate = false,
                })
                -- Only refresh if Neogit is still open
                local neogit_open = false
                for _, win in ipairs(vim.api.nvim_list_wins()) do
                  local buf = vim.api.nvim_win_get_buf(win)
                  local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
                  if ft == 'NeogitStatus' then
                    neogit_open = true
                    break
                  end
                end
                
                if neogit_open then
                  require('neogit').refresh()
                end
              else
                vim.notify("Fetch failed - check your network connection", vim.log.levels.WARN, {
                  title = "Neogit", 
                  timeout = 3000,
                })
                -- Clear cache on failure so it retries next time
                fetch_cache[git_root] = nil
              end
            end)
          end,
        })
      end, 100) -- Small delay to let Neogit fully initialize
    end
  end,
})

-- Clear cache entry when leaving a repository
vim.api.nvim_create_autocmd("DirChanged", {
  group = neogit_augroup,
  callback = function()
    local new_git_root = get_git_root()
    if not new_git_root then
      -- Not in a git repo anymore, clear all in-progress flags
      fetch_in_progress = {}
    end
  end,
})

-- Optional: Add a command to manually trigger fetch
vim.api.nvim_create_user_command("NeogitFetch", function()
  local git_root = get_git_root()
  if git_root then
    -- Clear cache to force fetch
    fetch_cache[git_root] = nil
    require('neogit').refresh()
  else
    vim.notify("Not in a git repository", vim.log.levels.WARN)
  end
end, {})
