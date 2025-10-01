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
    'mikesmithgh/kitty-scrollback.nvim',
    enabled = true,
    lazy = true,
    cmd = { 'KittyScrollbackGenerateKittens', 'KittyScrollbackCheckHealth' },
    event = { 'User KittyScrollbackLaunch' },
    -- version = '*', -- latest stable version, may have breaking changes if major version changed
    -- version = '^5.0.0', -- pin major version, include fixes and features that do not have breaking changes
    config = function()
      require('kitty-scrollback').setup()
    end,
  },
  {
    'tpope/vim-repeat', -- Required for leap.nvim dot-repeats
  },
  {
    'ggandor/leap.nvim',
    config = function()
      require('leap').create_default_mappings()
    end
  },
  {
    'ggandor/flit.nvim',
    dependencies = { 'ggandor/leap.nvim' },
    config = function()
      require('flit').setup {
        keys = { f = 'f', F = 'F', t = 't', T = 'T' },
        labeled_modes = "v",
        clever_repeat = true,
        multiline = true,
        opts = {}
      }
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
    'nathom/filetype.nvim',
    config = function()
      require('filetype').setup({
        overrides = {
          extensions = {
            sh = "sh",
          },
          literal = {
          },
        },
      })
    end
  },
  {
    'nvim-treesitter/nvim-treesitter',
    dependencies = { 'nathom/filetype.nvim' },
    config = function()
      require('nvim-treesitter.configs').setup({
        ensure_installed = { "markdown", "markdown_inline" },
        highlight = {
          enable = true,
          disable = { "markdown" }, -- This will disable Treesitter highlighting for markdown
        },
      })
      vim.treesitter.language.register('markdown', 'markdown')
    end
  },
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
      require('bufferline').setup({
        options = {
          hover = {
            enabled = true,
            delay = 200,
            reveal = {'close'}
          }
        },
        highlights = {
          fill = {
            bg = "#000000"
          },
          background = {
            bg = "#000000"
          }
        }
      })
    end
  },
  {
   'catppuccin/nvim',
   as = 'catppuccin',
   config = function()
     vim.g.catppuccin_flavour = "mocha"
     require('catppuccin').setup({
       transparent_background = true,
       color_overrides = {
         mocha = {
           base = "#000000",
           mantle = "#000000",
           crust = "#000000",
         },
       },
     })
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
    'MeanderingProgrammer/render-markdown.nvim',
    dependencies = { 
      'nvim-treesitter/nvim-treesitter',
      'nvim-tree/nvim-web-devicons'
    },
    ft = {'markdown'},
    config = function()
      require('render-markdown').setup({
        -- You can customize options here
        file_types = { 'markdown' },
      })
      end
  },
  -- Git integration stack (ordered by dependency)
  {
    "sindrets/diffview.nvim",
    dependencies = { 
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles" },
    config = function()
      require("diffview").setup()
      vim.opt.fillchars:append { diff = "╱" }
    end
  },
  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
      "nvim-telescope/telescope.nvim",
    },
    cmd = "Neogit",
    config = function()
      require('plugins.neogit')
    end
  },
  {
    "pwntester/octo.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    cmd = "Octo",
    config = function()
      require("octo").setup()
      vim.treesitter.language.register('markdown', 'octo')
    end
  },
  {
    "HakonHarnes/img-clip.nvim",
    event = "BufEnter",
    opts = {
      default = {
        -- Save images relative to the current markdown file
        relative_to_current_file = true,
        -- Create an 'images' directory next to the markdown file
        dir_path = function()
          -- Gets the directory of the current file
          local file_dir = vim.fn.expand('%:p:h')
          local images_dir = file_dir .. '/images'
          -- Create the images directory if it doesn't exist
          vim.fn.mkdir(images_dir, 'p')
          return 'images'  -- Return relative path
        end,
        extension = "png",
        prompt_for_file_name = true,
      },
      filetypes = {
        markdown = {
          url_encode_path = true,
          template = "![$CURSOR]($FILE_PATH)",
          download_images = true,  -- Enable downloading images from URLs
        },
      },
    }
  },
  {
    "3rd/image.nvim",
    build = false,
    opts = {
        backend = "kitty",
        processor = "magick_cli",
        integrations = {
            markdown = {
                enabled = true,
                clear_in_insert_mode = false,
                download_remote_images = true,
                only_render_image_at_cursor = false,
            }
        },
        -- max_height_window_percentage = 80,  -- uncomment to set max height to 80% of window
        editor_only_render_when_focused = false, 
        window_overlap_clear_enabled = false,
        hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif" }, 
    },
  },
  {
    "karb94/neoscroll.nvim",
    event = "BufRead",
    config = function()
      require('plugins.neoscroll')
    end
  },
  {
    'nvim-lualine/lualine.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function()
      require('plugins.lualine').setup()
    end,
    event = 'VeryLazy',
  },

  -- ===== NEW PLUGINS ADDED BELOW =====
  
  -- NEW: mdx.nvim - MDX file support
  {
    "davidmh/mdx.nvim",
    config = true,
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    ft = "mdx",  -- Lazy-loads on .mdx files
  },

  -- IMPROVED: pipeline.nvim - CI/CD pipeline viewer (using yq instead of make)
  {
    "topaxi/pipeline.nvim",
    keys = {
      { "<leader>ci", "<cmd>Pipeline<cr>", desc = "Open pipeline.nvim" },
    },
    -- Removed build step since yq is already installed
    opts = {
      -- You can customize pipeline.nvim options here if needed
      -- For example:
      -- refresh_interval = 30,
      -- browser = "firefox",
    },
  },

  -- NEW: diagram.nvim - Live diagram rendering (mermaid, plantuml, d2, gnuplot)
  {
    "3rd/diagram.nvim",
    dependencies = { "3rd/image.nvim" },  -- Already have image.nvim above
    opts = {
      events = {
        render_buffer = { "InsertLeave", "BufWinEnter", "TextChanged" },
        clear_buffer = { "BufLeave" },
      },
      renderer_options = {
        mermaid = { theme = "default", scale = 1 },
        plantuml = { charset = "utf-8" },
        d2 = {},
        gnuplot = {},
      },
    },
  },

  -- NEW: Mason + marksman LSP
  {
    "williamboman/mason.nvim",
    dependencies = {
      "williamboman/mason-lspconfig.nvim",
      "neovim/nvim-lspconfig",
    },
    ft = { "markdown", "md", "mdx" },
    config = function()
      require("mason").setup()
      require("mason-lspconfig").setup({
        ensure_installed = { "marksman" },
        handlers = {
          function(server_name)
            require("lspconfig")[server_name].setup({})
          end,
        },
      })
    end,
  },

})
