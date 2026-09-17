-- lua/theme.lua — the palette every colour in this config comes from.
--
-- Home Manager renders ~/.config/themes/<name>/theme.lua for each theme
-- (home/themes/*.nix); ~/.config/theme is the symlink ~/.local/bin/theme
-- retargets. This module dofile()s the current fragment and applies it to
-- catppuccin, bufferline and lualine — at startup from plugins.lua.in, and
-- again on `theme <name>`, which calls reload() over --remote-expr on every
-- running nvim. RAW (live-edit), see home/nvim.nix nvimRaw.
local M = {}

local FRAGMENT = vim.fn.expand('~/.config/theme/theme.lua')

-- noir, verbatim, so nvim still looks right when the pointer is missing
-- (a checkout ahead of its switch on the client laptop).
local fallback = {
  name = 'noir', polarity = 'dark', catppuccinFlavour = 'mocha',
  ground = { base = '#000000', dim = '#000000', raised = '#000000', desktop = '#000000' },
  fg = '#EAECF0', fgDim = '#D3D7DE', comment = '#818898', muted = '#45475a',
  red = '#F47B85', green = '#9BE963', yellow = '#f9e2af', blue = '#70B8FF',
  magenta = '#CC7BF4', cyan = '#5EEDED', orange = '#FBAD60',
  accent = '#70B8FF', brand = '#D97757',
  selection = { bg = '#264F78', fg = '#EAECF0' },
  border = { active = '#555451', inactive = '#373735', urgent = '#F47B85' },
}

function M.palette()
  local ok, t = pcall(dofile, FRAGMENT)
  if ok and type(t) == 'table' and t.fg then
    return t
  end
  return fallback
end

-- catppuccin: flavour + colour overrides from the palette. transparent_background
-- keeps kitty's ground as the editor ground, so noir -> claude-dark needs no
-- editor change at all; only claude-light flips the flavour to latte.
function M.catppuccin_opts(T)
  T = T or M.palette()
  return {
    flavour = T.catppuccinFlavour,
    transparent_background = true,
    color_overrides = {
      [T.catppuccinFlavour] = {
        base = T.ground.base,
        mantle = T.ground.dim,
        crust = T.ground.dim,
        text = T.fg,
        subtext1 = T.fgDim,
        overlay1 = T.comment,
        red = T.red,
        green = T.green,
        yellow = T.yellow,
        blue = T.blue,
        mauve = T.magenta,
        peach = T.orange,
        teal = T.cyan,
      },
    },
    custom_highlights = function(colors)
      local U = require('catppuccin.utils.colors')
      local bg_amount = 0.095
      local rainbow = {
        colors.blue,   -- rainbow1 (H1)
        colors.peach,  -- rainbow2 (H2)
        colors.green,  -- rainbow3 (H3)
        colors.teal,   -- rainbow4 (H4)
        colors.yellow, -- rainbow5 (H5)
        colors.mauve,  -- rainbow6 (H6)
      }
      local highlights = {}
      for i, color in ipairs(rainbow) do
        highlights['rainbow' .. i] = { fg = color }
        highlights['RenderMarkdownH' .. i] = { fg = color, bold = true }
        highlights['RenderMarkdownH' .. i .. 'Bg'] = { bg = U.darken(color, bg_amount, colors.base) }
      end
      highlights['RenderMarkdownCode'] = { bg = U.darken(colors.text, 0.05, colors.base) }
      highlights['RenderMarkdownCodeInline'] = { fg = colors.peach }
      highlights['RenderMarkdownBullet'] = { fg = colors.blue }
      highlights['RenderMarkdownDash'] = { fg = colors.overlay1 }
      highlights['RenderMarkdownQuote'] = { fg = colors.overlay1 }
      highlights['RenderMarkdownLink'] = { fg = colors.blue }
      highlights['RenderMarkdownChecked'] = { fg = colors.green }
      highlights['RenderMarkdownUnchecked'] = { fg = colors.overlay1 }
      highlights['RenderMarkdownTableHead'] = { fg = colors.blue }
      highlights['RenderMarkdownTableRow'] = { fg = colors.subtext1 }
      -- catppuccin's default Underlined has no fg (just the underline style),
      -- so man pages, :help tags, etc. render in plain text color instead of
      -- the Claude-blue used everywhere else for links/URLs.
      highlights['Underlined'] = { fg = colors.blue, style = { 'underline' } }
      return highlights
    end,
    integrations = {
      render_markdown = true,
    },
  }
end

function M.apply_catppuccin(T)
  require('catppuccin').setup(M.catppuccin_opts(T))
  vim.cmd.colorscheme('catppuccin')
end

-- bufferline: the fill and the inactive-buffer strip take the theme ground.
function M.bufferline_opts(T)
  T = T or M.palette()
  return {
    options = {
      hover = {
        enabled = true,
        delay = 200,
        reveal = { 'close' },
      },
    },
    highlights = {
      fill = { bg = T.ground.base },
      background = { bg = T.ground.base },
    },
  }
end

-- Re-read the fragment and re-apply everything. catppuccin's setup() does not
-- purge its own modules (that is what :CatppuccinCompile is for), so purge
-- first, then setup, recompile, and re-run the two plugins that consumed
-- palette values at their own setup time.
function M.reload()
  local T = M.palette()
  for name, _ in pairs(package.loaded) do
    if name == 'catppuccin' or name:match('^catppuccin%.') then
      package.loaded[name] = nil
    end
  end
  require('catppuccin').setup(M.catppuccin_opts(T))
  pcall(vim.cmd, 'CatppuccinCompile')
  vim.cmd.colorscheme('catppuccin')
  local ok_b, bufferline = pcall(require, 'bufferline')
  if ok_b then
    pcall(bufferline.setup, M.bufferline_opts(T))
  end
  local ok_l, lualine = pcall(require, 'plugins.lualine')
  if ok_l and type(lualine) == 'table' and lualine.setup then
    pcall(lualine.setup)
  end
  vim.notify('theme: ' .. T.name, vim.log.levels.INFO)
end

return M
