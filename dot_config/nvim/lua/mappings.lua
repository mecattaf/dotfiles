-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function map(mode, keys, command, opts)
  opts = opts or { noremap = true, silent = true }
  api.nvim_set_keymap(mode, keys, command, opts)
end

local function lua_map(mode, keys, func, opts)
  opts = opts or { noremap = true, silent = true }
  vim.keymap.set(mode, keys, func, opts)
end

-- Minimal mode toggle
local minimal_active = false
function Minimal()
  local opt = vim.o
  if minimal_active then
    opt.number = true
    opt.showmode = false
    opt.showtabline = 2
    opt.laststatus = 2
  else
    opt.number = false
    opt.relativenumber = false
    opt.showmode = true
    opt.showtabline = 0
    opt.laststatus = 0
  end
  minimal_active = not minimal_active
end

-- ============================================================================
-- BASIC NAVIGATION & EDITING
-- ============================================================================

-- Map semicolon to colon in normal mode
map("n", ";", ":")

-- Buffer navigation
map("n", "<TAB>", ":bnext<CR>")
map("n", "<S-TAB>", ":bprev<CR>")

-- Window splits
map("n", "hs", ":split<CR>")
map("n", "vs", ":vs<CR>")

-- Save operations
map("i", "<C-S>", "<ESC>:w<CR><Insert>")
map("n", "<C-S>", ":w<CR>")

-- Buffer management
map("n", "<leader>x", ":bd<CR>")
map("n", "<leader>s", ":w<CR>")
map("n", "<leader>t", ":enew<CR>")
map("n", "<ESC>", ":nohlsearch<CR>")

-- Insert mode navigation
map("i", "<C-E>", "<End>")
map("i", "<C-A>", "<Home>")
map("i", "<S-TAB>", "<ESC><<<Ins>")

-- ============================================================================
-- UI & DISPLAY TOGGLES
-- ============================================================================

map("n", "<leader>m", ":lua Minimal()<CR>")
map("n", "<leader>n", ":set relativenumber!<CR>")
map("n", "<leader>z", ":ZenMode<CR>")
map("n", "<leader>u", ":Twilight<CR>")

-- ============================================================================
-- PLUGIN MAPPINGS
-- ============================================================================

-- Telescope
map("n", "<leader>f", ":Telescope grep_string<CR>")

-- NvimTree
map("n", "<C-S-B>", ":NvimTreeToggle<CR>")
map("n", "<C-B>", ":NvimTreeFocus<CR>")

-- Image handling
map("n", "<leader>p", "<cmd>PasteImage<cr>")

-- ============================================================================
-- SMOOTH SCROLLING (NEOSCROLL)
-- ============================================================================

local function setup_neoscroll()
  local ok, neoscroll = pcall(require, "neoscroll")
  if not ok then return end

  lua_map("n", "<C-u>", function() neoscroll.ctrl_u({ duration = 200, easing = 'sine' }) end)
  lua_map("n", "<C-d>", function() neoscroll.ctrl_d({ duration = 200, easing = 'sine' }) end)
  lua_map("n", "<C-y>", function() neoscroll.scroll(-0.1, { move_cursor=false, duration = 80 }) end)
  lua_map("n", "<C-e>", function() neoscroll.scroll(0.1, { move_cursor=false, duration = 80 }) end)
end

setup_neoscroll()

-- ============================================================================
-- GIT INTEGRATION
-- ============================================================================

-- Git tools
map("n", "<leader>dv", "<cmd>DiffviewOpen<cr>")
map("n", "<leader>dc", "<cmd>DiffviewClose<cr>")
map("n", "<leader>ng", "<cmd>Neogit<cr>")

-- NEW! 
map("n", "<leader>gf", ":!git fetch --all<CR>")  -- Quick fetch
map("n", "<leader>gr", ":DiffviewOpen origin/main...HEAD<CR>")  -- Review against main

-- GitHub integration
map("n", "<leader>oi", "<cmd>Octo issue list<cr>")
map("n", "<leader>op", "<cmd>Octo pr list<cr>")

-- Gitsigns hunk navigation
lua_map("n", "]c", function()
  if vim.wo.diff then
    return "]c"
  end
  vim.schedule(function() 
    require('gitsigns').next_hunk() 
  end)
  return "<Ignore>"
end, { expr = true })

lua_map("n", "[c", function()
  if vim.wo.diff then
    return "[c"
  end
  vim.schedule(function() 
    require('gitsigns').prev_hunk() 
  end)
  return "<Ignore>"
end, { expr = true })

-- Gitsigns hunk operations
local gitsigns_maps = {
  -- Hunk staging/reset
  { "n", "<leader>hs", ":Gitsigns stage_hunk<CR>" },
  { "n", "<leader>hr", ":Gitsigns reset_hunk<CR>" },
  { "v", "<leader>hs", ":Gitsigns stage_hunk<CR>" },
  { "v", "<leader>hr", ":Gitsigns reset_hunk<CR>" },
  
  -- Hunk preview
  { "n", "<leader>hp", ":Gitsigns preview_hunk<CR>" },
  { "n", "<leader>hi", ":Gitsigns preview_hunk_inline<CR>" },
  
  -- Blame operations
  { "n", "<leader>hb", ":Gitsigns blame_line<CR>" },
  { "n", "<leader>tb", ":Gitsigns toggle_current_line_blame<CR>" },
  
  -- Word diff toggle
  { "n", "<leader>tw", ":Gitsigns toggle_word_diff<CR>" },
  
  -- Text objects
  { "o", "ih", ":<C-U>Gitsigns select_hunk<CR>" },
  { "x", "ih", ":<C-U>Gitsigns select_hunk<CR>" },
}

for _, mapping in ipairs(gitsigns_maps) do
  map(mapping[1], mapping[2], mapping[3])
end
