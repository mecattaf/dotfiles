-- lua/plugins/lualine.lua

local M = {}

-- Git branch component 
local function git_branch()
  local branch = vim.fn.system("git branch --show-current 2>/dev/null"):gsub('\n', '')
  if branch and branch ~= '' then
    return '  ' .. branch
  end
  return ''
end

-- Custom components
local components = {}

-- Mode component 
components.mode = {
  'mode',
  padding = { left = 1, right = 1 },
}

-- Git branch 
components.branch = {
  git_branch,
  color = { gui = 'bold' },
  cond = function()
    -- Only show if we're in a git repo
    return vim.fn.isdirectory('.git') == 1 or vim.fn.finddir('.git', '.;') ~= ''
  end,
}

-- Git diff 
components.diff = {
  'diff',
  symbols = { 
    added = ' ', 
    modified = ' ', 
    removed = ' ' 
  },
  colored = true,
  source = function()
    local gitsigns = vim.b.gitsigns_status_dict
    if gitsigns then
      return {
        added = gitsigns.added,
        modified = gitsigns.changed,
        removed = gitsigns.removed
      }
    end
  end,
  cond = function()
    return vim.fn.winwidth(0) > 80
  end,
}

-- Pipeline status component (NEW)
components.pipeline = {
  'pipeline',
  icon = '', -- CI/CD icon
  cond = function()
    -- Only show if we're in a git repo and window is wide enough
    return (vim.fn.isdirectory('.git') == 1 or vim.fn.finddir('.git', '.;') ~= '') 
           and vim.fn.winwidth(0) > 100
  end,
}

-- Filename component
components.filename = {
  'filename',
  file_status = true,
  newfile_status = false,
  path = 0,
  symbols = {
    modified = ' ●',
    readonly = ' ',
    unnamed = '[No Name]',
  },
}

-- Search count
components.searchcount = {
  'searchcount',
  maxcount = 999,
  timeout = 500,
  cond = function()
    return vim.v.hlsearch == 1 and vim.fn.searchcount().total > 0
  end,
}

-- Recording status
components.recording = {
  function()
    local reg = vim.fn.reg_recording()
    if reg == '' then
      return ''
    end
    return ' REC @' .. reg
  end,
  color = { fg = '#f38ba8', gui = 'bold' },
  cond = function()
    return vim.fn.reg_recording() ~= ''
  end,
}

-- LSP diagnostics
components.diagnostics = {
  'diagnostics',
  sources = { 'nvim_diagnostic' },
  symbols = { 
    error = ' ', 
    warn = ' ', 
    info = ' ', 
    hint = ' ' 
  },
  colored = true,
  update_in_insert = false,
  always_visible = false,
}

-- Filetype with icon
components.filetype = {
  'filetype',
  colored = true,
  icon_only = false,
}

-- Location
components.location = {
  'location',
  padding = { left = 0, right = 1 },
}

-- Setup function
function M.setup()
  require('lualine').setup({
    options = {
      theme = 'catppuccin',
      component_separators = { left = '', right = '' },
      section_separators = { left = '', right = '' },
      disabled_filetypes = {
        statusline = { 'alpha', 'dashboard' },
        winbar = {},
      },
      ignore_focus = {},
      always_divide_middle = true,
      globalstatus = true,
      refresh = {
        statusline = 5000,  
        refresh_time = 500, 
        events = {          
          'ModeChanged',    
          'BufWritePost',   
        },
      }
    },
    sections = {
      lualine_a = { components.mode },
      lualine_b = { 
        components.branch,
        components.diff,
        components.pipeline, 
      },
      lualine_c = {
        components.filename,
        components.searchcount,
        components.recording,
      },
      lualine_x = {
        components.diagnostics,
        components.filetype,
      },
      lualine_y = { components.location },
      lualine_z = {},
    },
    inactive_sections = {
      lualine_a = {},
      lualine_b = {},
      lualine_c = { 'filename' },
      lualine_x = { 'location' },
      lualine_y = {},
      lualine_z = {}
    },
    tabline = {},
    winbar = {},
    inactive_winbar = {},
    extensions = {
      'nvim-tree', 
      'lazy',
      'quickfix', 
    }
  })
end

return M
