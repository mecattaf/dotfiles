local function map(mode, keys, command)
  api.nvim_set_keymap(mode, keys, command, { noremap = true, silent = true })
end

local active = false
function Minimal()
  local opt = vim.o
  if active then
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
  active = not active
end

-- Normal Map
map("n", "<TAB>", ":bnext<CR>")
map("n", "<S-TAB>", ":bprev<CR>")
map("n", "hs", ":split<CR>")
map("n", "vs", ":vs<CR>")

-- Save
map("i", "<C-S>", "<ESC>:w<CR><Insert>")
map("n", "<C-S>", ":w<CR>")

-- Buffer
map("n", "<leader>x", ":bd<CR>")
map("n", "<leader>s", ":w<CR>")
map("n", "<leader>t", ":enew<CR>")
map("n", "<ESC>", ":nohlsearch<CR>")

-- Minimal toggle
map("n", "<leader>m", ":lua Minimal()<CR>")
map("n", "<leader>n", ":set relativenumber!<CR>")

-- Zen mode and Twilight toggle
map("n", "<leader>z", ":ZenMode<CR>")
map("n", "<leader>u", ":Twilight<CR>")  

-- Telescope to search for a string
map("n", "<leader>f", ":Telescope grep_string<CR>")

-- NvimTree
map("n", "<C-S-B>", ":NvimTreeToggle<CR>")
map("n", "<C-B>", ":NvimTreeFocus<CR>")

-- Insert Map
map("i", "<C-E>", "<End>")
map("i", "<C-A>", "<Home>")

-- Shift tab
map("i", "<S-TAB>", "<ESC><<<Ins>")

-- Image handling
map("n", "<leader>p", "<cmd>PasteImage<cr>")

-- Git integration
map("n", "<leader>dv", "<cmd>DiffviewOpen<cr>")
map("n", "<leader>dc", "<cmd>DiffviewClose<cr>")
map("n", "<leader>ng", "<cmd>Neogit<cr>")

-- GitHub integration
map("n", "<leader>oi", "<cmd>Octo issue list<cr>")
map("n", "<leader>op", "<cmd>Octo pr list<cr>")
