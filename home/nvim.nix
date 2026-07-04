{
  config,
  lib,
  pkgs,
  ...
}:
# nvim → Nix, implementing nvim-sweep.md. Keep lazy.nvim; ZERO functionality loss.
# Nix provides the binary + every LSP/formatter/tool (mason removed) + the plugins as
# /nix/store paths resolved by lazy-nix-helper. Most nvim files stay RAW (live-edit);
# only lua/plugins.lua is rendered (it carries store paths).
let
  repoDir = "${config.home.homeDirectory}/mecattaf/dotfiles";
  ndir = "${repoDir}/home/dot_config/nvim";
  link = p: config.lib.file.mkOutOfStoreSymlink "${ndir}/${p}";
  vp = pkgs.vimPlugins;

  # --- the three source-built plugins (REAL pinned hashes, prefetched in-container) ---
  lazy-nix-helper-nvim = pkgs.vimUtils.buildVimPlugin {
    pname = "lazy-nix-helper.nvim";
    version = "0-unstable-2026-06-20";
    src = pkgs.fetchFromGitHub {
      owner = "b-src";
      repo = "lazy-nix-helper.nvim";
      rev = "22d0f4d737104cba6c18ba9ca3ff1db5160c67b5";
      hash = "sha256-4DyuBMp83vM344YabL2SklQCg6xD7xGF5CvQP2q+W7A=";
    };
    doCheck = false;
  };

  leap-nvim-fork = pkgs.vimUtils.buildVimPlugin {
    pname = "leap.nvim";
    version = "0-unstable-codeberg-andyg-2026-06-20";
    # the config uses the codeberg andyg fork (url=), NOT ggandor upstream
    src = pkgs.fetchFromGitea {
      domain = "codeberg.org";
      owner = "andyg";
      repo = "leap.nvim";
      rev = "d7f8ee64155b7790188f17a993390f32577cfb81";
      hash = "sha256-x+oaVsaY69GrKtEt+8BS+XlRCc0QkYO1b7I4AABc/zs=";
    };
  };

  pipeline-nvim = pkgs.vimUtils.buildVimPlugin {
    pname = "pipeline.nvim";
    version = "0-unstable-2026-06-20";
    # not in nixpkgs (verified) — build from source
    src = pkgs.fetchFromGitHub {
      owner = "topaxi";
      repo = "pipeline.nvim";
      rev = "7f65a9fa31b8f500469f708c68b30d6c430f92ff";
      hash = "sha256-Ur/199keKqmXvlUZCAw60P2bqS6/hNfj2JuoumtPW2Y=";
    };
    doCheck = false;
  };

  filemention-nvim = pkgs.vimUtils.buildVimPlugin {
    pname = "filemention.nvim";
    version = "0-unstable-2026-05-30";
    # not in nixpkgs (verified 2026-07-04) — @-mention file completion (Claude Code style).
    # Completion-engine source only (cmp/blink, no native fallback) → blink.cmp added below.
    src = pkgs.fetchFromGitHub {
      owner = "not-manu";
      repo = "filemention.nvim";
      rev = "d8aa9116fa441d0529c53bb5cb2c321f30d9544d";
      hash = "sha256-XeLy1GlSSD3xg5KZWQKJH+riTdcN8e2iIpF7dbGl2MY=";
    };
    doCheck = false;
  };

  web-clipper-nvim = pkgs.vimUtils.buildVimPlugin {
    pname = "web-clipper.nvim";
    version = "0-unstable-2026-05-25";
    # not in nixpkgs (verified 2026-07-04) — URL → cleaned Markdown clippings.
    # Upstream says `build = "npm install --prefix bin"` but bin/node_modules is
    # vendored in-repo, so no npm at build time; only node itself is needed —
    # pinned via the shebang so clipping works regardless of runtime PATH.
    src = pkgs.fetchFromGitHub {
      owner = "jbuck95";
      repo = "web-clipper.nvim";
      rev = "f08924133465b670d9c7248b483d82a979e6fda9";
      hash = "sha256-It2jYLHm6PhFIQ/LamO9Br4uddK/ksQ/vmGjPmyy5ek=";
    };
    postPatch = ''
      substituteInPlace bin/defuddle-clip.mjs \
        --replace-fail "#!/usr/bin/env node" "#!${lib.getExe pkgs.nodejs}"
      # upstream doc bug: *web-clipper-health* is defined twice, which fails
      # buildVimPlugin's help-tag generation (E154) — drop the second tag.
      # Also drop the committed pre-generated doc/tags; the build regenerates it.
      substituteInPlace doc/web-clipper.txt \
        --replace-fail ":checkhealth web-clipper  *web-clipper-health*" ":checkhealth web-clipper"
      rm doc/tags
    '';
    doCheck = false;
  };

  # tree-sitter with grammars Nix-prebuilt (withPlugins patches install_dir → no runtime install)
  treesitterWithGrammars = vp.nvim-treesitter.withPlugins (
    p: with p; [
      markdown
      markdown-inline
      latex
      yaml
      mermaid
    ]
  );

  # lazy spec dir-name → derivation. Keys are lazy's on-disk names (last path segment of
  # the short repo / url= tail / name= override), NOT pnames.
  lazyPlugins = {
    "lazy.nvim" = vp.lazy-nvim;
    "lazy-nix-helper.nvim" = lazy-nix-helper-nvim;
    "kitty-scrollback.nvim" = vp.kitty-scrollback-nvim;
    "vim-repeat" = vp.vim-repeat;
    "leap.nvim" = leap-nvim-fork;
    "nvim-colorizer.lua" = vp.nvim-colorizer-lua; # nixpkgs attr IS the catgoose fork (verified)
    "indent-blankline.nvim" = vp.indent-blankline-nvim;
    "nvim-treesitter" = treesitterWithGrammars;
    "nvim-tree.lua" = vp.nvim-tree-lua;
    "gitsigns.nvim" = vp.gitsigns-nvim;
    "plenary.nvim" = vp.plenary-nvim;
    "telescope.nvim" = vp.telescope-nvim;
    "bufferline.nvim" = vp.bufferline-nvim;
    "catppuccin" = vp.catppuccin-nvim;
    "nvim-autopairs" = vp.nvim-autopairs;
    "twilight.nvim" = vp.twilight-nvim;
    "zen-mode.nvim" = vp.zen-mode-nvim;
    "render-markdown.nvim" = vp.render-markdown-nvim;
    "nvim-web-devicons" = vp.nvim-web-devicons;
    "diffview.nvim" = vp.diffview-nvim;
    "neogit" = vp.neogit;
    "octo.nvim" = vp.octo-nvim;
    "img-clip.nvim" = vp.img-clip-nvim;
    "image.nvim" = vp.image-nvim;
    "neoscroll.nvim" = vp.neoscroll-nvim;
    "lualine.nvim" = vp.lualine-nvim;
    "pipeline.nvim" = pipeline-nvim;
    "diagram.nvim" = vp.diagram-nvim;
    "nvim-lspconfig" = vp.nvim-lspconfig;
    "filemention.nvim" = filemention-nvim;
    "blink.cmp" = vp.blink-cmp; # nixpkgs build ships the compiled rust fuzzy lib
    "web-clipper.nvim" = web-clipper-nvim;
  };

  pluginTableLua = lib.concatStrings (
    lib.mapAttrsToList (name: drv: "  [\"${name}\"] = \"${drv}\",\n") lazyPlugins
  );

  # render plugins.lua from the template (no replaceVars dependency)
  pluginsLua = pkgs.writeText "plugins.lua" (
    builtins.replaceStrings
      [ "@pluginTable@" "@lazyNixHelperPath@" ]
      [ pluginTableLua "${lazy-nix-helper-nvim}" ]
      (builtins.readFile ./nvim/plugins.lua.in)
  );

  # nvim files that stay RAW (live-edit) — everything except the rendered plugins.lua
  nvimRaw = [
    "init.lua"
    "lua/options.lua"
    "lua/mappings.lua"
    "lua/yank.lua"
    "lua/hotreload.lua"
    "lua/external-changes.lua"
    "lua/directory-watcher.lua"
    "lua/diffview-watcher.lua"
    "lua/plugins/gitsigns.lua"
    "lua/plugins/indent_blankline.lua"
    "lua/plugins/neogit.lua"
    "lua/plugins/neoscroll.lua"
    "lua/plugins/nvim-tree.lua"
    "lua/plugins/telescope.lua"
    "lua/plugins/bufferline.lua"
    "lua/plugins/lualine.lua"
  ];

  # every binary the nvim config shells out to (replaces mason; covers all plugin CLIs)
  nvimTools = with pkgs; [
    marksman # markdown LSP — replaces the ENTIRE mason stack
    git
    gh
    ripgrep
    fd
    yq-go # mikefarah yq (pipeline.nvim); NOT pkgs.yq
    imagemagick # image.nvim magick_cli + diagram PNG
    mermaid-cli # diagram.nvim mermaid (mmdc; bundles headless chromium)
    plantuml
    graphviz # plantuml `dot`
    d2
    gnuplot
    curl # img-clip + image.nvim remote downloads
    wl-clipboard
    kitty
    lazygit
    xdg-utils
  ];
in
{
  # nvim ≥ 0.11 required (config uses vim.fn.getregion / vim.uv / vim.diff / vim.lsp.config)
  assertions = [
    {
      assertion = lib.versionAtLeast pkgs.neovim-unwrapped.version "0.11";
      message = "nvim ${pkgs.neovim-unwrapped.version} < 0.11";
    }
  ];

  programs.neovim = {
    enable = true;
    package = pkgs.neovim-unwrapped;
    defaultEditor = true;
    plugins = [ ]; # lazy.nvim + lazy-nix-helper own ALL plugins
    extraPackages = nvimTools;
    extraLuaPackages = ps: [ ps.magick ]; # image.nvim's magick LuaJIT rock, from Nix
    # extraConfig/extraLuaConfig intentionally empty → HM writes no init.lua, so the
    # RAW init.lua below (the hand-written module loader) is authoritative.
  };

  xdg.configFile =
    # RAW nvim files (live-edit)
    (builtins.listToAttrs (
      map (f: {
        name = "nvim/${f}";
        value = {
          source = link f;
        };
      }) nvimRaw
    ))
    # the ONE rendered file: lua/plugins.lua (store-path plugin table)
    // {
      "nvim/lua/plugins.lua".source = pluginsLua;
    };
}
