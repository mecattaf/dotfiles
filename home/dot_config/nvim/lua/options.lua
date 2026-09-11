local opt = vim.opt
local g = vim.g

-- basic
opt.scrolloff = 3
opt.mouse = 'a'
opt.title = true
opt.titlestring = 'nvim %f'

-- THIN-CLIENT CLIPBOARD SEAM (2026-09-11). The seat is the laptop (`client`);
-- nvim almost always runs on the COORDINATOR, inside a herdr pane projected
-- into the laptop's kitty. Every herdr pane carries WAYLAND_DISPLAY=wayland-1,
-- so `unnamedplus` below would pick the wl-copy provider and land the yank on
-- the coordinator's clipboard — a clipboard nobody is sitting in front of; once
-- the coordinator goes headless (M-1) wl-copy fails outright.
--
-- Fix: when the session is remote (a herdr pane sets HERDR_ENV; a plain remote
-- shell sets SSH_TTY), drive the clipboard over OSC 52 instead, so the yank
-- travels the terminal stream into the laptop's kitty and lands on the SEAT's
-- clipboard. kitty's `clipboard_control` (kitty.conf) permits exactly that write.
--
-- COPY-ONLY on purpose. nvim's bundled osc52 paste issues an OSC 52 READ and
-- then blocks 1 s + up to 9 s waiting for the terminal to answer. herdr never
-- answers OSC 52 reads at all (herdr-kitten mapping P27), and kitty answers one
-- only behind the interactive `read-clipboard-ask` prompt, so a plain `p` after
-- a yank would hang for ten seconds. The `cache` table keeps whatever THIS nvim
-- last put in each register, so in-nvim yank→put stays instant and never
-- touches the wire; only the write leg is real OSC 52.
--
-- Accepted defect: kitty applies an OSC 52 write only while the receiving
-- window is focused, so a yank made in an unfocused projection window is
-- dropped. `require('vim.ui.clipboard.osc52')` is internal to nvim 0.12 — the
-- pcall leaves g:clipboard unset (and `unnamedplus` back on its own providers)
-- rather than erroring out if a future nvim moves it.
if vim.env.HERDR_ENV or vim.env.SSH_TTY then
  local ok, osc52 = pcall(require, 'vim.ui.clipboard.osc52')
  if ok then
    local cache = {}

    local function copy(reg)
      return function(lines, regtype)
        cache[reg] = { lines, regtype }
        osc52.copy(reg)(lines, regtype)
      end
    end

    local function paste(reg)
      return function()
        return cache[reg] or { {}, 'v' }
      end
    end

    vim.g.clipboard = {
      name = 'osc52-copy-only',
      copy = { ['+'] = copy('+'), ['*'] = copy('*') },
      paste = { ['+'] = paste('+'), ['*'] = paste('*') },
    }
  end
end

opt.clipboard = 'unnamedplus'
opt.swapfile = false
opt.undofile = true
opt.autoread = true
-- opt.cmdheight = 0
opt.showmode = false
opt.cursorline = true
opt.termguicolors = true

-- timeout stuff
opt.updatetime = 100
opt.timeout = true
opt.timeoutlen = 300 
opt.ttimeoutlen = 0

-- status, tab, number, sign line
opt.ruler = false
opt.laststatus = 3
opt.showtabline = 2
opt.number = true
opt.numberwidth = 1
opt.relativenumber = false
opt.signcolumn = "yes"

-- window, buffer, tabs
opt.switchbuf = "newtab"
opt.splitbelow = true
opt.splitright = true
opt.fillchars = {
  eob = " ",
  diff = " ",
  msgsep = " "
}

-- text formatting
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.smartindent = true
opt.showmatch = true
opt.smartcase = true
opt.whichwrap:append "<>[]hl"

-- shift-arrow text selection (text-box muscle memory)
opt.selectmode = 'key'
opt.keymodel = 'startsel,stopsel'

-- remove intro
opt.shortmess:append "sI"

-- disable inbuilt vim plugins
local built_ins = {
  "2html_plugin",
  "getscript",
  "getscriptPlugin",
  "gzip",
  "logipat",
  "netrw",
  "netrwPlugin",
  "netrwSettings",
  "netrwFileHandlers",
  "matchit",
  "tar",
  "tarPlugin",
  "rrhelper",
  "spellfile_plugin",
  "vimball",
  "vimballPlugin",
  "zip",
  "zipPlugin",
}

for _, plugin in pairs(built_ins) do
  g["loaded_" .. plugin] = 1
end
