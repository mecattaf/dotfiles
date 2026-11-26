local opt = vim.opt
local g = vim.g

-- basic
opt.scrolloff = 3
opt.mouse = 'a'
opt.title = true
opt.titlestring = 'nvim %f'

-- THIN-CLIENT CLIPBOARD SEAM. The seat is the laptop (`client`); nvim runs
-- on the headless NAS, inside an hc station attached to the laptop's Kitty.
-- A local clipboard provider on the NAS cannot reach the seat's clipboard.
--
-- hc sets HC_TERMINAL_ID without SSH_TTY: its PTY belongs to the holder,
-- independently of any SSH attachment. Keep plain SSH and durable editor
-- detection too, and drive the clipboard over OSC 52, so the yank
-- travels the terminal stream into the laptop's kitty and lands on the SEAT's
-- clipboard. kitty's `clipboard_control` (kitty.conf) permits exactly that write.
--
-- COPY-ONLY on purpose. nvim's bundled osc52 paste issues an OSC 52 READ and
-- then blocks 1 s + up to 9 s waiting for the terminal to answer. Kitty answers
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
-- A durable editor can outlive its first SSH TTY; its native attached UIs own
-- the terminal clipboard transport even while the server has no terminal.
if vim.env.HC_TERMINAL_ID or vim.env.HERDR_ENV or vim.env.SSH_TTY or vim.env.DSH_EDITOR_ROOT then
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
