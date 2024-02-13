local lazypath = fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end

opt.rtp:prepend(lazypath)

g.mapleader = " "

require("lazy").setup({
 {
    "robitx/gp.nvim",
    config = function()
      require("gp").setup({
        openai_api_key = { "cat", vim.fn.expand("~/openai_key") },
      })
    end
  },
  {
    'norcalli/nvim-colorizer.lua',
    config = function()
      require('colorizer').setup()
    end
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    opts = {},
    config = function()
      require('plugins.indent_blankline')
    end
  },
  {
    'nvim-treesitter/nvim-treesitter',
    dependencies = { 'nathom/filetype.nvim' },
    config = function()
      require('plugins.treesitter')
    end
  },
  'RRethy/nvim-base16',
  {
    'kyazdani42/nvim-tree.lua',
    config = function()
      require('plugins.nvim-tree')
    end
  },
  {
    'lewis6991/gitsigns.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      require('plugins.gitsigns')
    end
  },
  {
    'nvim-telescope/telescope.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      require('plugins.telescope')
    end
  },
  {
    'akinsho/bufferline.nvim',
    config = function()
      require('plugins.bufferline')
    end
  },
  {
    'catppuccin/nvim',
    as = 'catppuccin',
    config = function()
      vim.g.catppuccin_flavour = "mocha" -- Set the flavour
      require('catppuccin').setup()
      vim.cmd.colorscheme "catppuccin"
    end
  },
  {
    'windwp/nvim-autopairs',
    config = function()
      require('nvim-autopairs').setup()
    end
  },
  {
    'numToStr/Comment.nvim',
    config = function()
      require('Comment').setup()
    end
  },
  {
    "folke/twilight.nvim",
    config = function()
      require("twilight").setup()
    end
  },
  {
    "folke/zen-mode.nvim",
    config = function()
      require("zen-mode").setup()
    end
  },
  {
    'tpope/vim-repeat', 
    config = function()
      -- Configuration for vim-repeat can be added here if needed
    end
  },
  {
    "ggandor/leap.nvim",
    config = function()
      require('leap').set_default_keymaps()
    end,
  },
  {
    "ggandor/flit.nvim",
    config = function()
      require('flit').setup {
        keys = { f = 'f', F = 'F', t = 't', T = 'T' },
        labeled_modes = "v",
        multiline = true,
        opts = {}
      }
    end
  },
  {
    "ellisonleao/glow.nvim",
      config = function()
       require("glow").setup({
          width_ratio = 1,
          height_ratio = 1,
          style = "~/.config/glow/colors.json"  -- Path to your custom style file
        })
    end
  }
})

