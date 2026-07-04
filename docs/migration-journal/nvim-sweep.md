# nvim → Nix Migration Plan (lazy.nvim retained, maximally Nix-native)

**Scope:** This is a written plan only. Nothing is built yet (Nix is not installed on the
host). The acceptance contract is **zero functionality loss** vs. the live config at
`/var/home/tom/mecattaf/dotfiles/home/dot_config/nvim`. The prior `nix-test` port is **not**
trusted — it merely symlinks the nvim dir, ships a bare `neovim` package, and leaves
`mason.nvim` live (the forbidden imperative-install pattern).

**Ratified decisions this plan implements:**

- Keep **lazy.nvim** as the plugin manager (not nixvim/nvf, not `programs.neovim.plugins`).
- Go maximally Nix-native: Nix provides the nvim binary + every LSP/formatter/linter; add
  **lazy-nix-helper.nvim** so lazy specs resolve to `/nix/store` paths (offline/sandbox-safe),
  falling back to lazy's own git clone only when a plugin isn't Nix-provided.
- Replace **mason / mason-lspconfig** entirely (imperative runtime installs → forbidden).
  Every mason-installed binary becomes a Nix package on PATH.
- **Pre-seed tree-sitter parsers** via Nix; disable runtime `:TSInstall`/`:TSUpdate`.
- HARD requirement: every plugin, LSP, formatter, linter, keymap, autocmd, and custom lua
  module has an explicit provider post-migration.

---

## 0. Inventory baseline (reconstructed by reading every file)

### 0.1 Plugins declared in `lua/plugins.lua` (the lazy spec)

| Plugin | Type | Notes |
|---|---|---|
| `folke/lazy.nvim` | manager | git-cloned in `plugins.lua` L5–15 |
| `mikesmithgh/kitty-scrollback.nvim` | pure lua | cmd/event-gated (L22–33) |
| `tpope/vim-repeat` | pure lua | leap dot-repeat dep (L34–36) |
| leap.nvim — **codeberg `andyg` fork via `url=`** | pure lua | **non-GitHub source** (L37–44) |
| `catgoose/nvim-colorizer.lua` | pure lua | **fork** (L45–50) |
| `lukas-reineke/indent-blankline.nvim` (`ibl`) | pure lua | L51–58 |
| `nvim-treesitter/nvim-treesitter` | **parsers/compilation** | `build=:TSUpdate`, **main-branch API** `require('nvim-treesitter').install(...)` (L59–70) |
| `nvim-tree/nvim-tree.lua` | pure lua | needs `git` on PATH (L71–76) |
| `lewis6991/gitsigns.nvim` | pure lua | + plenary (L77–83) |
| `nvim-telescope/telescope.nvim` | pure lua | + plenary; needs `rg`/`fd` (L84–90) |
| `akinsho/bufferline.nvim` | pure lua | config inline (L91–112) |
| `catppuccin/nvim` (`name='catppuccin'`) | pure lua | colorscheme + custom highlights (L113–171) |
| `windwp/nvim-autopairs` | pure lua | L172–177 |
| `folke/twilight.nvim` | pure lua | L178–183 |
| `folke/zen-mode.nvim` | pure lua | drives kitty font (L184–207) |
| `MeanderingProgrammer/render-markdown.nvim` | pure lua | needs ts markdown parsers (L208–218) |
| `sindrets/diffview.nvim` | pure lua | needs `git` (L220–252) |
| `NeogitOrg/neogit` | pure lua | needs `git`; async `git fetch` (L253–264) |
| `pwntester/octo.nvim` | pure lua | needs `gh` (L265–277) |
| `HakonHarnes/img-clip.nvim` | pure lua | `download_images=true` (L301); needs `wl-clipboard`/`curl` |
| `3rd/image.nvim` | **rockspec build** | kitty backend, `processor=magick_cli`, `download_remote_images=true` (L306–325) |
| `3rd/diagram.nvim` | **runtime binaries** | mermaid/plantuml/d2/gnuplot (L359–375) |
| `karb94/neoscroll.nvim` | pure lua | L326–332 |
| `nvim-lualine/lualine.nvim` | pure lua | + web-devicons + catppuccin (L333–340) |
| `topaxi/pipeline.nvim` | pure lua | needs `yq`, `gh` (L345–357) |
| `williamboman/mason.nvim` + `mason-lspconfig.nvim` + `neovim/nvim-lspconfig` | **FORBIDDEN** | installs `marksman` imperatively (L377–396) |
| `nvim-lua/plenary.nvim` | pure lua (dep-only) | telescope/gitsigns/neogit/diffview/octo |
| `nvim-tree/nvim-web-devicons` | pure lua (dep-only) | needs a Nerd Font |

### 0.2 Local lua modules (NOT plugins — must survive verbatim)

Loaded by `init.lua`'s module loop (L3–20), which **`error()`s hard** on any failed
`require` and aborts the remaining loads — so any config-time failure in `plugins` cascades
into losing the watchers below. These carry over unchanged via the out-of-store symlink (§1.4):

`options.lua`, `mappings.lua`, `plugins.lua`, `directory-watcher.lua`, `hotreload.lua`,
`diffview-watcher.lua`, `external-changes.lua`, `yank.lua`, and `plugins/*` config files.

### 0.3 Runtime external binaries the config shells out to

- `git` — lualine branch, neogit fetch, diffview-watcher `git check-ignore`, nvim-tree, lazy bootstrap
- `gh` — octo, pipeline
- `rg` / `fd` — telescope (`grep_string`/finders), nvim-tree
- `yq` — pipeline.nvim (mikefarah yq → `pkgs.yq-go`, **not** `pkgs.yq`)
- `kitty` — `kitty @` remote control (mappings), kitty-scrollback, image.nvim kitty backend, zen-mode font
- `xdg-open` — mappings `<leader>ko` URL open
- `lazygit` — mappings `<leader>kg`
- `curl` — img-clip `download_images=true` (L301), image.nvim `download_remote_images=true` (L316); both shell out to `curl` over HTTP
- `magick` (ImageMagick) — image.nvim `magick_cli`, img-clip, diagram PNG handling
- `wl-clipboard` — `clipboard=unnamedplus` on Wayland; img-clip paste
- diagram renderers: `mmdc` (mermaid), `plantuml`, `d2`, `gnuplot`

### 0.4 Runtime-network behaviors

| # | Behavior | Class | Disposition |
|---|---|---|---|
| 1 | lazy.nvim self-clone from GitHub (L5–15) | install-time | **neutralize** — store path |
| 2 | per-plugin git clone | install-time | **neutralize** — `dir` → store |
| 3 | treesitter `:TSUpdate` + `.install()` at runtime | install-time | **neutralize** — pre-seed |
| 4 | mason downloads `marksman` | install-time | **neutralize** — Nix package |
| 5 | neogit `git fetch --all` | user-action, **cmd-gated** | **kept** (not a first-launch concern) |
| 6 | img-clip / image.nvim remote image download | user-action | **kept** (needs `curl`) |
| 7 | octo GitHub API via `gh` | user-action, **cmd-gated** | **kept** |

**Honest framing:** the acceptance gate "no network on `nvim` open" concerns classes 1–4
only. Classes 5–7 are lazy-gated (cmd/keys/explicit user action) and therefore never fire on
a bare startup — verified against the specs (`cmd = "Neogit"`, `cmd = "Octo"`, keys-gated
pipeline, manual img-clip paste).

---

## 1. Nix provides the nvim binary + all tools (the mason replacement vector)

### 1.1 Neovim provider — version floor with build-time assertion

Provide nvim via `programs.neovim` (which builds the correctly-wrapped `cfg.finalPackage` from
`pkgs.neovim-unwrapped`). Pin a **hard minimum of Neovim ≥ 0.11**.

Rationale: the config uses 0.10+ APIs — `vim.fn.getregion` (yank.lua:57), `vim.uv`
(directory-watcher.lua:3, external-changes.lua:59/63/81), `vim.diff`
(external-changes.lua:32) — and the mason-removal LSP wiring (§3) uses 0.11
`vim.lsp.config`/`vim.lsp.enable`. Current nixpkgs-unstable ships 0.12.x, satisfying this with
margin. Nothing asserts the floor today, so a future/older pin would break `<leader>ya/yr`
silently; add a build-time assertion so a too-old pin fails `nix build`, not at runtime:

```nix
let
  nvim = pkgs.neovim-unwrapped;
  nvimMin = "0.11";
in
  assert lib.versionAtLeast nvim.version nvimMin
    || throw "nvim ${nvim.version} < required ${nvimMin} (config uses vim.fn.getregion / vim.uv / vim.diff / vim.lsp.config)";
  # ... programs.neovim.package = nvim; ...
```

### 1.2 Tools on PATH via `programs.neovim.extraPackages` (NOT a symlinkJoin wrapper)

`pkgs.neovim`'s `bin/nvim` is already a `makeWrapper`-generated script; wrapping it again with
`symlinkJoin { paths=[pkgs.neovim]; postBuild = wrapProgram ... }` double-wraps and mangles the
existing `--add-flags`/VIMINIT resolution — **do not do this**. Instead use Home Manager's
native `extraPackages`, which the module wires onto nvim's PATH via
`--suffix PATH : ${lib.makeBinPath extraPackages}` (HM `neovim.nix`).

```nix
# home/neovim.nix  (Home Manager module)
{ pkgs, lib, config, ... }:
let
  nvim = pkgs.neovim-unwrapped;
  # Every binary the nvim config shells out to (replaces mason + covers all plugin CLIs).
  nvimTools = with pkgs; [
    marksman        # markdown LSP — replaces the ENTIRE mason/mason-lspconfig stack
    git             # gitsigns, neogit, diffview, lualine branch, diffview-watcher
    gh              # octo.nvim, pipeline.nvim CI status
    ripgrep         # telescope grep_string (<leader>f)  — REQUIRED
    fd              # telescope file finder — recommended; telescope degrades gracefully if absent
    yq-go           # pipeline.nvim YAML (mikefarah yq; NOT pkgs.yq)
    imagemagick     # image.nvim magick_cli + diagram PNG (magick/convert/identify)
    mermaid-cli     # diagram.nvim mermaid (binary: mmdc; self-wraps chromium — see §8 R4)
    plantuml        # diagram.nvim plantuml (JRE-wrapped)
    graphviz        # plantuml `dot` for non-sequence UML (unconditional — diagram exposes all types)
    d2              # diagram.nvim d2
    gnuplot         # diagram.nvim gnuplot
    curl            # img-clip download_images (L301) + image.nvim download_remote_images (L316)
    wl-clipboard    # unnamedplus clipboard + img-clip PasteImage (Wayland host)
    kitty           # image.nvim kitty backend, kitty-scrollback, zen-mode font, kitty @
    lazygit         # mappings <leader>kg
    xdg-utils       # mappings <leader>ko -> xdg-open
  ];
in
  assert lib.versionAtLeast nvim.version "0.11"
    || throw "nvim ${nvim.version} < 0.11";
{
  programs.neovim = {
    enable = true;             # builds the correctly-wrapped finalPackage
    package = nvim;
    plugins = [];              # KEEP EMPTY — lazy.nvim + lazy-nix-helper own all plugins
    extraPackages = nvimTools; # onto nvim's PATH (inherited by every nvim child process)
    # extraLuaPackages: the magick LuaJIT rock, needed to BUILD vimPlugins.image-nvim (§8 R5)
    extraLuaPackages = ps: [ ps.magick ];
    # DO NOT set extraConfig/extraLuaConfig: leaving them empty means HM writes NO
    # ~/.config/nvim/init.lua (it only writes when generated content is non-empty, wrapRc=false),
    # so the chezmoi-managed hand-written init.lua + lua/ modules are used verbatim.
    defaultEditor = true;
  };

  # Clipboard tool also on the interactive shell PATH so unnamedplus works regardless of launch.
  home.packages = [ pkgs.wl-clipboard ];
}
```

`extraPackages` puts tools on the PATH of nvim's **child** processes — covering every shell-out
in this config (telescope→rg/fd, neogit/diffview/lualine→git, octo→gh, pipeline→yq/gh,
image/diagram→imagemagick/mmdc/plantuml/d2/gnuplot, img-clip→curl/wl-clipboard, marksman LSP).
It does **not** cover kitty-daemon-launched processes (`kitty @ launch ...`) — that is the
session-PATH problem solved in §1.3.

### 1.3 Session PATH for kitty-daemon-launched tools (covers `<leader>kg`, `<leader>ko`, open-actions)

`kitty @ launch` spawns from the **kitty daemon** (niri's env), not as a child of wrapped nvim,
so §1.2's PATH does **not** reach `<leader>kg` lazygit (mappings.lua), `<leader>ko` nested nvim,
or `open-actions.conf` nvim launches. `niri-session` runs the **login shell** and imports its
env to systemd → niri → kitty inherit it; but `dot_bashrc`/`dot_bash_profile` source no
nix/HM vars today. Fix the SESSION PATH at the login entry (do both layers):

**(A) Primary — source HM session vars from the chezmoi login file.** In
`home/dot_bash_profile`, before niri starts:

```sh
# Source home-manager session vars (PATH incl. ~/.nix-profile/bin, sessionVariables)
if [ -f "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
    . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
fi
```

and in home-manager: `home.sessionPath = [ "$HOME/.nix-profile/bin" ];`. Then every tool in
`home.packages` is on the SESSION PATH, inherited by niri → kitty → `kitty @ launch` children.
This is the systemic fix — it also repairs every niri `spawn`/`spawn-at-startup` and
`kitty -e fish` shell that expects Nix-provided binaries (`wl-clipboard`, `cliphist`, etc.).

**(B) Defense-in-depth for the three nvim/lazygit launches — absolute store paths so PATH is
irrelevant.** Render these files via home-manager (substituted text), not verbatim chezmoi:

- `mappings.lua` `<leader>kg`: `... launch ... @lazygit@` ← `${pkgs.lazygit}/bin/lazygit`
- `mappings.lua` `<leader>ko` nested nvim: `... launch ... @nvim@ -- ...` ← wrapped-nvim path
- `open-actions.conf` (the `action launch ... nvim -- ${FILE_PATH}` lines): `@nvim@`

`@nvim@` = `${config.programs.neovim.finalPackage}/bin/nvim`.

### 1.4 Config dir wiring (live-editable, hot-reload preserved)

Keep the existing out-of-store symlink strategy (`nvim` already in `configDirs` via
`config.lib.file.mkOutOfStoreSymlink`). The config is symlinked from the repo, so edits take
effect with no rebuild — required by `hotreload.lua`/`directory-watcher.lua`. Files that must
embed a `/nix/store` path (the templated `plugins.lua`, `mappings.lua`, `open-actions.conf`,
and the kitty-scrollback fragment in §9) are the exception: those are rendered by home-manager
and are not hand-edited live.

---

## 2. lazy-nix-helper.nvim wiring (verified real API)

lazy-nix-helper maps each lazy plugin **dir name** → `/nix/store` path via an
`input_plugin_table` passed to `setup()`. There is **no env var** and **no auto-scan of a
linkFarm**. Verified API surface (against `b-src/lazy-nix-helper.nvim`):

- `setup()` recognizes exactly: `lazypath`, `input_plugin_table`, `friendly_plugin_names`,
  `auto_plugin_discovery`. Any other key (`plugins_dir`, `input_plugin_table_version`,
  `plugin_path`) is silently ignored.
- `get_plugin_path(name)` → `PluginTable.plugins[name]` (plain lookup; returns the store path
  or `nil`). lazy treats `dir = nil` as "not local" → it clones.
- `lazypath()` → `get_plugin_path("lazy.nvim") or <configured lazypath>`. So `lazy.nvim` itself
  must be a key in the table for the Nix path to win.
- lazy-nix-helper **cannot resolve itself** — it is what does the resolving — so it bootstraps
  from a hardcoded store path prepended to rtp before `setup()`.
- **lazy-nix-helper is NOT in nixpkgs** (`pkgs.vimPlugins.lazy-nix-helper-nvim` does not exist):
  build it with `buildVimPlugin` + `fetchFromGitHub`.

### 2.1 Nix side: build lazy-nix-helper + the explicit name→derivation map

Keys MUST be **lazy's on-disk spec dir name** (last path segment of the short repo / `url=`
tail / `name=` override), NOT `p.pname`/`p.name` (which are version/date/`vimplugin-`-suffixed).
A key miss with `install.missing=false` (§2.4) = the plugin silently never loads = a zero-loss
violation. Build an **explicit, hand-authored** attrset:

```nix
{ pkgs, lib, ... }:
let
  vp = pkgs.vimPlugins;

  lazy-nix-helper-nvim = pkgs.vimUtils.buildVimPlugin {
    pname = "lazy-nix-helper.nvim";
    version = "unstable-<DATE>";
    src = pkgs.fetchFromGitHub {
      owner = "b-src"; repo = "lazy-nix-helper.nvim";
      rev = "<PIN_COMMIT>"; hash = "<FILL>";       # TOFU on first build
    };
    doCheck = false;
  };

  # Codeberg andyg/leap.nvim fork — NOT vp.leap-nvim (that is ggandor upstream). §5.3.
  leap-nvim-fork = pkgs.vimUtils.buildVimPlugin {
    pname = "leap.nvim"; version = "codeberg-<rev>";
    src = pkgs.fetchgit {                            # codeberg is Forgejo/Gitea, not GitHub
      url = "https://codeberg.org/andyg/leap.nvim";
      rev = "<PIN_COMMIT>"; hash = "<FILL>";        # nix-prefetch-git
    };
  };

  # tree-sitter with grammars pre-bundled; main-branch-aware wrapper patches install_dir. §4.
  treesitterWithGrammars = vp.nvim-treesitter.withPlugins (p: with p; [
    markdown markdown-inline latex yaml mermaid     # nixpkgs attrs are hyphenated
  ]);
  # (or vp.nvim-treesitter.withAllGrammars for the everything bundle)

  # KEY = lazy's spec dir name; VALUE = derivation. Includes dependency-only plugins.
  lazyPlugins = {
    "lazy.nvim"             = vp.lazy-nvim;                 # required for lazypath()
    "lazy-nix-helper.nvim"  = lazy-nix-helper-nvim;
    "kitty-scrollback.nvim" = vp.kitty-scrollback-nvim;
    "vim-repeat"            = vp.vim-repeat;
    "leap.nvim"             = leap-nvim-fork;               # url= tail
    "nvim-colorizer.lua"    = vp.nvim-colorizer-lua;        # catgoose fork — verify in pin
    "indent-blankline.nvim" = vp.indent-blankline-nvim;
    "nvim-treesitter"       = treesitterWithGrammars;
    "nvim-tree.lua"         = vp.nvim-tree-lua;
    "gitsigns.nvim"         = vp.gitsigns-nvim;
    "plenary.nvim"          = vp.plenary-nvim;              # dependency-only
    "telescope.nvim"        = vp.telescope-nvim;
    "bufferline.nvim"       = vp.bufferline-nvim;
    "catppuccin"            = vp.catppuccin-nvim;           # name='catppuccin' override
    "nvim-autopairs"        = vp.nvim-autopairs;
    "twilight.nvim"         = vp.twilight-nvim;
    "zen-mode.nvim"         = vp.zen-mode-nvim;
    "render-markdown.nvim"  = vp.render-markdown-nvim;
    "nvim-web-devicons"     = vp.nvim-web-devicons;         # dependency-only
    "diffview.nvim"         = vp.diffview-nvim;
    "neogit"                = vp.neogit;
    "octo.nvim"             = vp.octo-nvim;
    "img-clip.nvim"         = vp.img-clip-nvim;
    "image.nvim"            = vp.image-nvim;                # diagram dep; carries magick rock (§8 R5)
    "neoscroll.nvim"        = vp.neoscroll-nvim;
    "lualine.nvim"          = vp.lualine-nvim;
    "pipeline.nvim"         = vp.pipeline-nvim;             # overlay if absent — §5.3
    "diagram.nvim"          = vp.diagram-nvim;              # overlay if absent — §5.3
    "nvim-lspconfig"        = vp.nvim-lspconfig;            # dependency-only after mason removal
  };

  pluginPack = pkgs.linkFarm "nvim-lazy-plugins"
    (lib.mapAttrsToList (name: path: { inherit name path; }) lazyPlugins);

  # Render the Lua table literal for input_plugin_table.
  pluginTableLua = lib.concatStrings
    (lib.mapAttrsToList (name: drv: "  [\"${name}\"] = \"${drv}\",\n") lazyPlugins);
in {
  # substituteAll into plugins.lua: @pluginTable@ and @lazyNixHelperPath@
  # @lazyNixHelperPath@ = "${lazy-nix-helper-nvim}"
}
```

> `telescope-fzf-native-nvim` is **intentionally NOT included** — see §5.1.

### 2.2 Lua side: rewrite the bootstrap in `plugins.lua`

Replace the current bootstrap (L5–17) with the verified shape:

```lua
-- @pluginTable@ and @lazyNixHelperPath@ substituted by home-manager.
local plugins = {
@pluginTable@
}

-- lazy-nix-helper bootstraps from a hardcoded store path (it cannot resolve itself).
local lazy_nix_helper_path = "@lazyNixHelperPath@"
if not vim.uv.fs_stat(lazy_nix_helper_path) then              -- non-Nix fallback (portability)
  lazy_nix_helper_path = vim.fn.stdpath("data") .. "/lazy/lazy-nix-helper.nvim"
  if not vim.uv.fs_stat(lazy_nix_helper_path) then
    vim.fn.system({ "git", "clone", "--filter=blob:none",
      "https://github.com/b-src/lazy-nix-helper.nvim.git", lazy_nix_helper_path })
  end
end
vim.opt.rtp:prepend(lazy_nix_helper_path)

local lnh = require("lazy-nix-helper")
lnh.setup({
  lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim",     -- non-Nix fallback only
  input_plugin_table = plugins,
  friendly_plugin_names = true,    -- tolerate vimplugin-/-scm name skew vs lazy short names
  -- auto_plugin_discovery left default false; the explicit table is authoritative
})

-- Replace the lazy.nvim git-clone bootstrap with the helper-resolved path.
local lazypath = lnh.lazypath()
vim.opt.rtp:prepend(lazypath)

vim.g.mapleader = " "
```

Then add `dir = lnh.get_plugin_path("<lazy spec dir name>")` to **every** spec, e.g.:

```lua
{ 'lewis6991/gitsigns.nvim', dir = lnh.get_plugin_path('gitsigns.nvim'),
  dependencies = { { 'nvim-lua/plenary.nvim', dir = lnh.get_plugin_path('plenary.nvim') } },
  config = function() require('plugins.gitsigns') end },

{ url = 'https://codeberg.org/andyg/leap.nvim', dir = lnh.get_plugin_path('leap.nvim'),
  config = function() ... end },

{ 'catppuccin/nvim', name = 'catppuccin', dir = lnh.get_plugin_path('catppuccin'), ... },
```

### 2.3 Dependency resolution (HARD — every nested `dependencies` entry needs its own `dir`)

lazy-nix-helper only store-resolves a spec — top-level **or** a `dependencies` entry — when that
entry carries a `dir`. A bare `dependencies = { "owner/name" }` is a real spec to lazy and gets
**cloned** when its parent loads. `install.missing=false` does NOT prevent dependency clones.
Therefore give **every** dependency entry an explicit `dir`:

```lua
gitsigns:        dependencies = { { dir = lnh.get_plugin_path("plenary.nvim") } }
telescope:       dependencies = { { dir = lnh.get_plugin_path("plenary.nvim") } }
render-markdown: dependencies = { { dir = lnh.get_plugin_path("nvim-treesitter") },
                                  { dir = lnh.get_plugin_path("nvim-web-devicons") } }
diffview:        dependencies = { { dir = lnh.get_plugin_path("plenary.nvim") },
                                  { dir = lnh.get_plugin_path("nvim-web-devicons") } }
neogit:          dependencies = { { dir = lnh.get_plugin_path("plenary.nvim") },
                                  { dir = lnh.get_plugin_path("diffview.nvim") },
                                  { dir = lnh.get_plugin_path("telescope.nvim") } }
octo:            dependencies = { { dir = lnh.get_plugin_path("plenary.nvim") },
                                  { dir = lnh.get_plugin_path("telescope.nvim") },
                                  { dir = lnh.get_plugin_path("nvim-web-devicons") } }
lualine:         dependencies = { { dir = lnh.get_plugin_path("nvim-web-devicons") },
                                  { dir = lnh.get_plugin_path("catppuccin") } }
diagram:         dependencies = { { dir = lnh.get_plugin_path("image.nvim") } }
```

Dependency-only plugins (`plenary.nvim`, `nvim-web-devicons`, `nvim-lspconfig`) have no
top-level spec but **must** be keys in `lazyPlugins` (they are, §2.1).

### 2.4 lazy global settings (fail-closed under Nix)

```lua
opts = {
  install = { missing = false },   -- never auto-install at startup
  pkg = { enable = false },
  rocks = { enabled = false },     -- no luarocks network (image.nvim rock comes from Nix)
  change_detection = { enabled = false },
}
```

### 2.5 Fail-closed startup assertion

`install.missing=false` means any `dir` miss is a *silent* loss. Add an active guard after
`lazy.setup` that errors loudly in the Nix path (and is skipped off-Nix where clones are
allowed):

```lua
if vim.uv.fs_stat("@lazyNixHelperPath@") then  -- only on the Nix closure
  local expected = {
    "kitty-scrollback.nvim","vim-repeat","leap.nvim","nvim-colorizer.lua",
    "indent-blankline.nvim","nvim-treesitter","nvim-tree.lua","gitsigns.nvim",
    "plenary.nvim","telescope.nvim","bufferline.nvim","catppuccin","nvim-autopairs",
    "twilight.nvim","zen-mode.nvim","render-markdown.nvim","nvim-web-devicons",
    "diffview.nvim","neogit","octo.nvim","img-clip.nvim","image.nvim","neoscroll.nvim",
    "lualine.nvim","pipeline.nvim","diagram.nvim","nvim-lspconfig",
  }
  local cfg = require("lazy.core.config").plugins
  for _, name in ipairs(expected) do
    local p = cfg[name]
    assert(p and p.dir and p.dir:match("^/nix/store/"),
      "lazy-nix-helper MISS: " .. name .. " not resolved from /nix/store (dir=" .. tostring(p and p.dir) .. ")")
  end
end
```

---

## 3. mason removal → exact nixpkgs packages

Delete the entire mason block (`plugins.lua` L377–396: `mason.nvim`, `mason-lspconfig.nvim`).
**Keep** `neovim/nvim-lspconfig` (the lspconfig framework, not an installer) and replace the
mason `ensure_installed`/`handlers` setup with a direct lspconfig call that assumes the binary
is on PATH.

### 3.1 mason's entire footprint today

`mason-lspconfig.ensure_installed = { "marksman" }` — one LSP. **No** none-ls/null-ls/conform/
nvim-lint/nvim-dap and no other servers exist anywhere in the config. The complete
LSP/formatter/linter/DAP replacement set is exactly:

| mason-installed tool | role | nixpkgs attr | on PATH via |
|---|---|---|---|
| `marksman` | Markdown LSP | `pkgs.marksman` | `nvimTools` (§1.2) |

### 3.2 New lspconfig wiring (replacing the mason block)

```lua
{
  "neovim/nvim-lspconfig",
  dir = require("lazy-nix-helper").get_plugin_path("nvim-lspconfig"),
  ft = { "markdown" },
  config = function()
    require("lspconfig").marksman.setup({})   -- marksman is on PATH via Nix; no mason
  end,
},
```

Pin `nvim-lspconfig` alongside neovim and verify `require('lspconfig').marksman.setup({})` does
not warn on the pinned nvim. If it does (deprecation on ≥0.11), switch to
`vim.lsp.config('marksman', {})` + `vim.lsp.enable('marksman')`, gated on the same
`ft={'markdown'}`. `marksman` exists as `pkgs.marksman` and is on the nvim PATH so lspconfig's
default `cmd` resolves.

---

## 4. tree-sitter: pre-seed parsers, keep the live main-branch API

### 4.1 What the live config does (confirmed: main/rewrite branch)

`plugins.lua` L59–70 is unambiguously the **main/rewrite-branch API**:
`require('nvim-treesitter').install({ 'markdown', 'markdown_inline' })` plus a
`FileType markdown_inline -> vim.treesitter.start()` autocmd. There is **no**
`require('nvim-treesitter.configs')`, no `ensure_installed`, no `auto_install`, no classic
`highlight.enable`.

### 4.2 Parser provider (Nix) — default nixpkgs is already the main branch

nixpkgs `vimPlugins.nvim-treesitter` was switched master→main in late 2025 (PR #470883, commit
d5146f4, pin `0.10.0-unstable-2025-12-29`). On any 2026 pin the default package **is** the main
branch — the same API the live config uses. **No overlay, no iofq/nvim-treesitter-main
(deprecated), no buildVimPlugin-from-main-ref.**

Provide grammars via `withPlugins`, which patches the main-branch `install_dir` to the Nix-store
bundle so parsers are discovered with no runtime `.install()`, no `:TSInstall`, no compiler:

```nix
nvimTreesitter = pkgs.vimPlugins.nvim-treesitter.withPlugins (p: with p; [
  markdown        # render-markdown, octo (registered as markdown alias)
  markdown-inline # NB: nixpkgs attr is hyphenated, not markdown_inline
  latex           # render-markdown math
  yaml            # pipeline.nvim CI + md frontmatter
  mermaid         # diagram.nvim source highlight
]);
# (or .withAllGrammars for zero-miss at the cost of closure size)
```

Queries ship in-package (PR #470883 override), so highlight/injection work offline. octo needs
no extra grammar (`vim.treesitter.language.register('markdown','octo')`, L275). Add **no** gcc /
tree-sitter CLI to `home.packages` for treesitter.

### 4.3 Lua change (a 2-line deletion + a 1-pattern extension — NOT a rewrite)

Keep the live main-branch shape; remove only the build/install network vectors. Extend the
autocmd to also start `markdown` (today the `markdown` parser is brought up as a side-effect of
the deleted `.install()` plus render-markdown's own `vim.treesitter.start()`; covering it
explicitly keeps strict parity):

```lua
{
  'nvim-treesitter/nvim-treesitter',
  dir = require("lazy-nix-helper").get_plugin_path("nvim-treesitter"),
  lazy = false,
  build = false,                          -- was ':TSUpdate'; grammars are Nix-prebuilt
  config = function()
    -- removed: require('nvim-treesitter').install({ 'markdown', 'markdown_inline' })
    -- (parsers already on rtp via the patched install_dir — that call WAS the network vector)
    vim.api.nvim_create_autocmd('FileType', {
      pattern = { 'markdown', 'markdown_inline' },   -- 'markdown' added for parity after dropping install()
      callback = function() pcall(vim.treesitter.start) end,
    })
  end,
},
```

**DO NOT** introduce `require('nvim-treesitter.configs').setup({...})`, `ensure_installed`,
`auto_install`, or `highlight.enable` — that module does not exist on the main branch
(reproduces nixpkgs issue #477072 "module nvim-treesitter.configs not found"), would raise at
require time, and via `init.lua`'s hard `error()` loop would abort the entire plugin set and the
watcher modules (§0.2).

**Documented fallback (only if a frozen/older pin ever ships `master`):** then, and only then,
use `require('nvim-treesitter.configs').setup({ auto_install = false, ensure_installed = {} })`
and regression-test render-markdown + the autocmd.

---

## 5. Plugin handling — Nix-provided vs. lazy-managed

**Rule:** anything that compiles a native binary or has a non-lua build artifact **must** come
from Nix (offline-safe); pure-lua plugins come from Nix (preferred) and fall back to lazy clone
only off-Nix.

### 5.1 MUST be Nix-provided (compilation / native artifact)

| Plugin | Why | nixpkgs attr |
|---|---|---|
| `nvim-treesitter` (grammars) | compiled `.so` parsers | `withPlugins`/`withAllGrammars` (§4) |
| `image.nvim` | rockspec-driven build pulls the `magick` rock (§8 R5) | `pkgs.vimPlugins.image-nvim` (+ `imagemagick` on PATH + `magick` rock on Lua path) |

**`telescope-fzf-native` — NOT USED; do NOT add.** Verified: `grep -ri fzf` over the config = 0
matches; the telescope spec (plugins.lua L84–90) depends only on `plenary.nvim` with no
`build='make'`; `lua/plugins/telescope.lua` has only a `defaults` block — no `extensions`, no
`load_extension('fzf')`. The config uses telescope's built-in pure-Lua sorter (no compiled
extension, no C build). Adding `pkgs.vimPlugins.telescope-fzf-native-nvim` would add a needless
compiled make build with zero functional effect, and wiring `load_extension('fzf')` would be
net-new functionality — both violate zero-loss / no-new-build. The active mapping `<leader>f`
→ `:Telescope grep_string` (mappings.lua) is backed by `ripgrep` (already provided); `fd` is an
optional finder companion (telescope degrades gracefully if absent).

### 5.2 Nix-provided when available in nixpkgs (pure lua, offline-safe)

All have `vimPlugins.*` attrs and are keys in `lazyPlugins` (§2.1): `lazy-nvim`, `plenary-nvim`,
`nvim-web-devicons`, `vim-repeat`, `nvim-colorizer-lua` (catgoose — **verify** the pin has the
catgoose fork, else custom derivation), `indent-blankline-nvim`, `nvim-tree-lua`,
`gitsigns-nvim`, `telescope-nvim`, `bufferline-nvim`, `catppuccin-nvim`, `nvim-autopairs`,
`twilight-nvim`, `zen-mode-nvim`, `render-markdown-nvim`, `diffview-nvim`, `neogit`, `octo-nvim`,
`img-clip-nvim`, `neoscroll-nvim`, `lualine-nvim`, `kitty-scrollback-nvim`, `nvim-lspconfig`.
`lazy-nix-helper.nvim` is **not** in nixpkgs and is built via `buildVimPlugin` (§2.1).

### 5.3 Forks / possibly-absent → HARD overlays (offline guarantee, not a "network touch")

A `url=`/absent plugin with no resolvable `dir` **hard-fails** offline — it does not degrade.
Under the zero-network gate these are blockers, so commit to overlays now:

| Plugin | Status | Action |
|---|---|---|
| leap.nvim (codeberg `andyg` fork) | `vimPlugins.leap-nvim` is **ggandor upstream**, the wrong source | `buildVimPlugin` + `fetchgit` against codeberg, pname `leap.nvim`, pinned rev (§2.1). MANDATORY. |
| `topaxi/pipeline.nvim` | may be absent on the pin | if `vimPlugins.pipeline-nvim` absent → `buildVimPlugin` + `fetchFromGitHub`, pinned rev |
| `3rd/diagram.nvim` | may be absent on the pin | same: overlay if `vimPlugins.diagram-nvim` absent |

```nix
# overlays/nvim-plugins.nix
final: prev: {
  vimPlugins = prev.vimPlugins.extend (pf: pp: {
    # leap.nvim — codeberg andyg fork (NOT ggandor upstream)
    leap-nvim = pf.buildVimPlugin {
      pname = "leap.nvim"; version = "codeberg-<rev>";
      src = final.fetchgit {
        url = "https://codeberg.org/andyg/leap.nvim";
        rev = "<PIN_COMMIT>"; hash = "<sha256-...>";   # nix-prefetch-git
      };
    };
    # build ONLY if not already present at an acceptable rev on the pin:
    pipeline-nvim = pf.buildVimPlugin {
      pname = "pipeline.nvim"; version = "<PIN>";
      src = final.fetchFromGitHub { owner = "topaxi"; repo = "pipeline.nvim"; rev = "<SHA>"; hash = "<sha256-...>"; };
      # upstream build="make" intentionally NOT run (config uses yq + gh on PATH)
    };
    diagram-nvim = pf.buildVimPlugin {
      pname = "diagram.nvim"; version = "<PIN>";
      src = final.fetchFromGitHub { owner = "3rd"; repo = "diagram.nvim"; rev = "<SHA>"; hash = "<sha256-...>"; };
    };
  });
}
```

Pin every rev (no branch refs) for reproducible offline fetch after the first build. If a probe
of the actual pin shows `pipeline-nvim`/`diagram-nvim` already present at an acceptable rev, drop
those overlay entries and reference `vp.<name>`. `leap-nvim` ALWAYS needs the override.

> Until these overlays exist and pass the offline gate, the offline guarantee is **NOT met** —
> a fresh/offline machine loses leap motions (`s`/`S`/`gs` + vim-repeat dot-repeat),
> pipeline.nvim (`<leader>ci` view + the lualine pipeline component), and **all** diagram
> rendering. This is hard loss, not a benign one-time network touch.

### 5.4 Decommissioned

`mason.nvim`, `mason-lspconfig.nvim` — **removed** (§3). `neovim/nvim-lspconfig` — **kept** as a
Nix-provided dependency-only plugin.

---

## 6. Neutralizing every runtime-network behavior

| # | Behavior (§0.4) | Neutralization |
|---|---|---|
| 1 | lazy self-clone | lazy.nvim from `vimPlugins.lazy-nvim`; bootstrap uses `lnh.lazypath()` (§2.2). Clone branch kept only for non-Nix fallback. |
| 2 | per-plugin clone | every spec + every dependency gets `dir = get_plugin_path(name)` → store; `install.missing=false`, `change_detection=false`, `rocks.enabled=false` (§2.3–2.4). |
| 3 | treesitter `:TSUpdate` + `.install()` | parsers prebuilt via `withPlugins`; `build=false`, `.install()` removed (§4.3). |
| 4 | mason downloads `marksman` | mason removed; `marksman` is `pkgs.marksman` on PATH (§3). |
| 5 | neogit `git fetch --all` | **kept** — cmd-gated (`cmd="Neogit"`), user-facing VCS network; not a first-launch concern. |
| 6 | img-clip / image.nvim remote download | **kept** — user action; `curl` + `magick` now Nix-provided (the *tooling* is reproducible). |
| 7 | octo GitHub API via `gh` | **kept** — cmd-gated (`cmd="Octo"`); `gh` Nix-provided. |

After this, the first `nvim` launch on the Nix closure performs **zero install-time network
I/O** for plugin/parser/LSP provisioning (once the §5.3 overlays exist).

---

## 7. ZERO-FUNCTIONALITY-LOSS CHECKLIST (acceptance contract)

### 7.1 Plugins

| Feature / plugin | Post-migration provider |
|---|---|
| lazy.nvim (manager) | `vimPlugins.lazy-nvim` via `lnh.lazypath()`; clone fallback off-Nix only |
| lazy-nix-helper.nvim | `buildVimPlugin` (b-src), bootstrapped from hardcoded store path (§2.1) |
| kitty-scrollback.nvim | `vimPlugins.kitty-scrollback-nvim`; kitty.conf path repointed to store (§9) |
| vim-repeat | `vimPlugins.vim-repeat` (leap dot-repeat) |
| leap.nvim (codeberg fork) | overlay `buildVimPlugin` + `fetchgit` (codeberg `andyg`) — MANDATORY, §5.3 |
| nvim-colorizer.lua (catgoose) | `vimPlugins.nvim-colorizer-lua` (verify catgoose fork on pin) |
| indent-blankline (ibl) | `vimPlugins.indent-blankline-nvim` + `plugins/indent_blankline.lua` |
| nvim-treesitter | `vimPlugins.nvim-treesitter.withPlugins` (main branch), runtime install disabled (§4) |
| nvim-tree.lua | `vimPlugins.nvim-tree-lua` + `plugins/nvim-tree.lua`; `git`/`fd` on PATH |
| gitsigns.nvim | `vimPlugins.gitsigns-nvim` + `plugins/gitsigns.lua`; plenary dep `dir` |
| telescope.nvim | `vimPlugins.telescope-nvim` + `plugins/telescope.lua`; `rg` on PATH (`fd` optional) |
| plenary.nvim | `vimPlugins.plenary-nvim` (dependency-only key) |
| bufferline.nvim | `vimPlugins.bufferline-nvim` (config inline) |
| catppuccin | `vimPlugins.catppuccin-nvim` (`name='catppuccin'`; theme + custom highlights inline) |
| nvim-autopairs | `vimPlugins.nvim-autopairs` |
| twilight.nvim | `vimPlugins.twilight-nvim` |
| zen-mode.nvim | `vimPlugins.zen-mode-nvim`; kitty font bump needs `kitty` on PATH |
| render-markdown.nvim | `vimPlugins.render-markdown-nvim`; ts markdown/inline parsers prebuilt; deps `dir` |
| diffview.nvim | `vimPlugins.diffview-nvim`; `git` on PATH; `diffview-watcher.lua`; deps `dir` |
| neogit | `vimPlugins.neogit` + `plugins/neogit.lua`; `git`; cmd-gated; deps `dir` |
| octo.nvim | `vimPlugins.octo-nvim`; `gh`; cmd-gated; deps `dir` |
| img-clip.nvim | `vimPlugins.img-clip-nvim`; `wl-clipboard` (wl-paste) + `curl` (download_images, L301) on PATH |
| image.nvim | `vimPlugins.image-nvim`; `imagemagick` (magick_cli) + `magick` rock (build) + `curl` (remote, L316); kitty backend |
| diagram.nvim | overlay/`vimPlugins.diagram-nvim`; `mmdc`/`plantuml`/`d2`/`gnuplot` on PATH; image.nvim dep `dir` |
| neoscroll.nvim | `vimPlugins.neoscroll-nvim` + `plugins/neoscroll.lua` |
| lualine.nvim | `vimPlugins.lualine-nvim` + `plugins/lualine.lua`; web-devicons + catppuccin deps `dir` |
| pipeline.nvim | overlay/`vimPlugins.pipeline-nvim`; `yq-go` + `gh` on PATH |
| nvim-web-devicons | `vimPlugins.nvim-web-devicons` (dependency-only key); Nerd Font |
| mason / mason-lspconfig | **REMOVED** — replaced by `marksman` on PATH |
| nvim-lspconfig | `vimPlugins.nvim-lspconfig` (dependency-only key), direct `marksman.setup()` |

### 7.2 LSP / tools (all on nvim PATH via `extraPackages`, §1.2)

| Tool | Provider | For |
|---|---|---|
| marksman | `pkgs.marksman` | markdown LSP (replaces all of mason) |
| ripgrep | `pkgs.ripgrep` | telescope `grep_string` (`<leader>f`) — REQUIRED |
| fd | `pkgs.fd` | telescope/nvim-tree finder — optional, graceful degrade |
| git | `pkgs.git` | gitsigns/neogit/diffview/lualine/diffview-watcher/nvim-tree |
| gh | `pkgs.gh` | octo, pipeline |
| yq | `pkgs.yq-go` | pipeline.nvim (mikefarah yq, NOT `pkgs.yq`) |
| lazygit | `pkgs.lazygit` | `<leader>kg` (also absolute-pathed, §1.3) |
| curl | `pkgs.curl` | img-clip download_images (L301), image.nvim download_remote_images (L316) |
| ImageMagick (`magick`) | `pkgs.imagemagick` | image.nvim magick_cli, img-clip, diagram PNG |
| magick (LuaJIT rock) | `pkgs.luajitPackages.magick` via `extraLuaPackages` | builds `vimPlugins.image-nvim` (rockspec dep, §8 R5) |
| wl-clipboard | `pkgs.wl-clipboard` | unnamedplus + img-clip paste (also in `home.packages`) |
| xdg-open | `pkgs.xdg-utils` | `<leader>ko` |
| mermaid (`mmdc`) | `pkgs.mermaid-cli` | diagram.nvim (self-wraps chromium, §8 R4) |
| plantuml | `pkgs.plantuml` (+ `pkgs.graphviz` for `dot`) | diagram.nvim non-sequence UML |
| d2 | `pkgs.d2` | diagram.nvim |
| gnuplot | `pkgs.gnuplot` | diagram.nvim |
| kitty | `pkgs.kitty` | remote control, scrollback, image backend, zen font |

### 7.3 Local lua modules / keymaps / autocmds

| Feature | Provider |
|---|---|
| `options.lua` (opts, disabled builtins) | symlinked config, unchanged |
| `mappings.lua` (keymaps, Minimal(), neoscroll, kitty/yank maps) | unchanged; `<leader>kg`/`<leader>ko` absolute-pathed (§1.3); depends on `kitty`/`lazygit`/`xdg-open`/`wl-clipboard` on session PATH |
| `yank.lua` (yank-with-path for Claude Code) | unchanged except removal-proof `vim.hl.range` (§ below); `vim.fn.getregion` → nvim ≥0.10; `clipboard=unnamedplus` → `wl-clipboard` |
| `directory-watcher.lua` | unchanged (`vim.uv` fs_event) |
| `hotreload.lua` | unchanged; preserved via out-of-store symlink (§1.4) |
| `diffview-watcher.lua` | unchanged; `git check-ignore` → `git` on PATH |
| `external-changes.lua` (diff highlights + lualine comp) | unchanged (`vim.diff`/`vim.uv`) |
| lualine `shpool` component | env-gated (`vim.env.SHPOOL_SESSION_NAME`); carries over verbatim; no Nix provider needed |
| init.lua autocmds (TermOpen, BufEnter term, VimLeave cursor) | unchanged |
| Hot-reload editing workflow | preserved via out-of-store symlink (§1.4) |

**yank.lua removal-proof highlight (recommended).** `vim.highlight.range` was renamed to
`vim.hl.range` in 0.11 (deprecated, still resolves on 0.12 with a one-time warning). Make it
future-proof (2-line change, zero behavior change):

```lua
local ns = vim.api.nvim_create_namespace 'simulate_yank_highlight'
local hl_range = (vim.hl and vim.hl.range) or vim.highlight.range
hl_range(0, ns, 'IncSearch', { bounds.start_line - 1, bounds.start_col },
         { bounds.end_line - 1, bounds.end_col }, { priority = 200 })
```

---

## 8. Open risks / verify-before-lock

- **R1 — tree-sitter branch (RESOLVED, now a build assertion, not a footnote).** The live
  config is the **main/rewrite** branch; §4.3 retains that API. Default nixpkgs has shipped main
  since commit d5146f4 (2025-12-30), so any 2026 pin needs no overlay. The grammar wrapper is
  branch-agnostic (it only injects compiled `parser/*.so` + queries). **Assert** the pin is at/
  after d5146f4 and confirm the resolved version string contains `unstable-2025-12-29` or later.
  CONDITIONAL fallback (only if a frozen/older pin ships `master`): iofq overlay OR the classic
  `configs.setup` port + regression test. Default path needs neither.
- **R2 — leap.nvim codeberg fork.** `vimPlugins.leap-nvim` is ggandor upstream, NOT the `andyg`
  fork the config pins via `url=`. MANDATORY `buildVimPlugin` + `fetchgit` overlay (§5.3).
  Offline first boot must perform **no** codeberg clone; `get_plugin_path('leap.nvim')` must
  resolve to the `/nix/store` fork path.
- **R3 — pipeline.nvim / diagram.nvim presence.** Verify `vimPlugins.pipeline-nvim` /
  `vimPlugins.diagram-nvim` exist at an acceptable rev on the pin. If absent → the §5.3
  `buildVimPlugin` overlays (trivial pure-lua fetchFromGitHub). Until present, offline guarantee
  is not met (lose `<leader>ci` + lualine pipeline component + all diagram rendering).
- **R4 — mermaid offline render.** `pkgs.mermaid-cli` ALREADY self-wraps chromium
  (`PUPPETEER_SKIP_DOWNLOAD=true` at build; `--set PUPPETEER_EXECUTABLE_PATH ${chromium}` in the
  `mmdc` wrapper) — do **not** hand-roll a second makeWrapper around it (double-wrap risk). The
  residual risk is at *render* time: chromium's sandbox ("No usable sandbox!") and a writable
  `$HOME`/XDG/`/dev/shm`. If a ```mermaid block fails offline with a sandbox error, supply a
  puppeteer config via a thin wrapper that appends `-p`:

  ```nix
  mmdcPuppeteerConfig = pkgs.writeText "puppeteer-config.json" ''
    { "args": ["--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"] }
  '';
  mmdcWrapped = pkgs.symlinkJoin {              # wraps the already-wrapped mmdc; only appends -p,
    name = "mmdc-wrapped"; paths = [ pkgs.mermaid-cli ];   # so PUPPETEER_* from upstream survive
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''wrapProgram $out/bin/mmdc --add-flags "-p ${mmdcPuppeteerConfig}"'';
  };
  ```

  Put `mmdcWrapped` on PATH ahead of `pkgs.mermaid-cli` only if the bare package render fails.
  `pkgs.plantuml` needs `pkgs.graphviz` (`dot`) for non-sequence diagrams — added
  unconditionally in §1.2.
- **R5 — image.nvim magick rock (build-time dep, not runtime).** Upstream: `processor="magick_cli"`
  shells out to the ImageMagick CLI and never `require('magick')` at runtime (the only rock
  require is behind `processor=="magick_rock"`). **However**, the nixpkgs `vimPlugins.image-nvim`
  is built from the upstream rockspec (`buildNeovimPlugin`), and that rockspec hard-declares
  `magick` as a dependency — so the **Nix package fails to build** without the rock, regardless
  of runtime processor. Provide BOTH: `pkgs.imagemagick` on PATH (magick_cli runtime) AND
  `pkgs.luajitPackages.magick` on the Lua path via `extraLuaPackages` (build + belt-and-suspenders
  cpath; the rock is LuaJIT-only — `broken = !isLuaJIT` — and neovim is LuaJIT). Do **not** write
  "magick_cli means Nix needs only the CLI" — true upstream, false for the nixpkgs package path.
  Alternative (only if eliminating the rock is desired): package image.nvim with
  `vimUtils.buildVimPlugin` from source (rev+hash pin) — `buildVimPlugin` ignores the rockspec, so
  no rock; runtime still works on `magick_cli` with just `pkgs.imagemagick`. Pick the rock XOR the
  source build — not both. Kitty graphics require running inside kitty (already the env).
- **R6 — lazy-nix-helper API.** Pin `b-src/lazy-nix-helper.nvim`; the §2.2 lua uses the verified
  signature (`lazypath`, `input_plugin_table`, `friendly_plugin_names`, `auto_plugin_discovery`;
  `get_plugin_path`, `lazypath`). Do NOT reference `plugins_dir`, `input_plugin_table_version`,
  or any env var — they are not part of the API.
- **R7 — `dir` + dependencies (handled, verify).** Every `dependencies` entry has its own `dir`
  (§2.3). `:Lazy` must show **zero** plugins in a "not installed" state.
- **R8 — telescope-fzf-native (RESOLVED — do NOT add).** Confirmed unused (§5.1); adding it
  introduces a needless make build and/or net-new functionality.
- **R9 — PATH inheritance for kitty-launched tools (RESOLVED via §1.3).** `extraPackages` does
  NOT reach `kitty @ launch` children (kitty-daemon env). Fixed by the session-PATH wiring (A)
  plus absolute store paths for `<leader>kg`/`<leader>ko`/open-actions (B).
- **R10 — first-run lazy state (RESOLVED via §2.5).** The fail-closed startup assertion errors
  loudly on any `/nix/store` `dir` miss; cross-check `:Lazy` + `:checkhealth` against §7.1.

---

## 9. kitty-scrollback.nvim: repoint the kitten off the lazy clone dir

`kitty.conf` hardcodes the kitten at the lazy **clone** dir:

```
action_alias kitty_scrollback_nvim kitten ~/.local/share/nvim/lazy/kitty-scrollback.nvim/python/kitty_scrollback_nvim.py
```

Once lazy-nix-helper resolves the plugin from `/nix/store`, lazy never clones there, so that
path is empty and `kitty_mod+h`, `kitty_mod+g`, and the `ctrl+shift+right` mouse_map break. The
nixpkgs store layout is `${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty_scrollback_nvim.py`
(plain `buildVimPlugin`, whole upstream tree copied). kitty.conf is an **out-of-store symlink**,
so it cannot interpolate `${pkgs...}` and `action_alias` does not env-expand. Fix via a
templated in-store include fragment (recommended):

```nix
# home-manager: a store-backed kitty fragment beside the live (symlinked) kitty.conf
xdg.configFile."kitty/kitty-scrollback-nix.conf".text = ''
  # GENERATED — Nix-store path for kitty-scrollback.nvim kittens (offline-safe).
  action_alias kitty_scrollback_nvim kitten ${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty_scrollback_nvim.py
'';
```

Live edit `dotfiles/home/dot_config/kitty/kitty.conf`: **delete** the hardcoded `action_alias`
line and **replace** with `include kitty-scrollback-nix.conf` (relative include resolves against
`~/.config/kitty/`). Leave the `kitty_mod+h`/`kitty_mod+g`/mouse_map lines unchanged — they
reference the alias the fragment now defines.

> If HM rejects mixing a managed file into the symlinked dir, emit the fragment to a neutral
> path and `include` it by absolute path. **Fallback** (only if kitty.conf must stay byte-identical):
> `home.file.".local/share/nvim/lazy/kitty-scrollback.nvim".source = pkgs.vimPlugins.kitty-scrollback-nvim;`
> — works but recouples to lazy's runtime-managed dir; prefer the fragment.

---

## 10. Acceptance gate

Build → run `nvim` and assert, **offline** (e.g. `unshare -rn nvim` or
`systemd-run --property=PrivateNetwork=yes`):

- [ ] `nvim --version | head -1` reports **≥ 0.11.0** (build assertion in §1.1 enforces this too).
- [ ] No network I/O on `nvim` open; `:Lazy` shows **every** §7.1 plugin loaded from a
      `/nix/store` path with **zero** pending/failed clones (except intentionally none).
- [ ] §2.5 fail-closed assertion passes (no `lazy-nix-helper MISS`).
- [ ] `:lua print(require('lazy-nix-helper').get_plugin_path('telescope.nvim'))` →
      `/nix/store/...`; same for `leap.nvim` and `nvim-colorizer.lua` (highest mis-key risk);
      `:lua print(require('lazy-nix-helper').lazypath())` → `/nix/store/...`.
- [ ] `:TSInstall`/`:Mason` never invoked; `:checkhealth nvim-treesitter` clean; open a `.md`
      offline → highlights + render-markdown render with no `:TSInstall` prompt;
      `:lua =vim.treesitter.get_parser(0):lang()` → `"markdown"`.
- [ ] All 7 init.lua modules loaded:
      `:lua for _,m in ipairs({'options','mappings','plugins','directory-watcher','hotreload','diffview-watcher','external-changes'}) do assert(package.loaded[m]~=nil, m) end`
- [ ] `marksman` attaches on a markdown buffer; `:LspInfo` shows it running.
- [ ] `<leader>ya`/`<leader>yr` (visual) flash IncSearch and write `path:line-range` + selection
      to `+` (exercises `getregion` + `hl.range`/`highlight.range` fallback + clipboard provider).
- [ ] From a niri-spawned kitty window: `<leader>kg` opens lazygit; `<leader>ko` on a path opens
      a fully-tooled nested nvim; a file-manager open of a `.md` launches open-actions nvim with
      marksman + treesitter live.
- [ ] `kitty @ --to $KITTY_LISTEN_ON launch --type=os-window sh -c 'command -v lazygit marksman nvim; echo $PATH'`
      resolves all three and shows `~/.nix-profile/bin`.
- [ ] `kitty_mod+h` (default `ctrl+shift+h`) opens the kitty-scrollback nvim view offline;
      `readlink -f` of the fragment path resolves into `/nix/store`;
      `~/.local/share/nvim/lazy/kitty-scrollback.nvim` is NOT required to exist.
- [ ] Offline diagram smoke tests: ```mermaid renders inline (else capture mmdc stderr — must be
      a chromium sandbox error, apply R4 Mitigation A — NOT a puppeteer download); ```plantuml
      class diagram renders (confirms `graphviz`); ```d2 and ```gnuplot render.
- [ ] image.nvim: `:lua require('image')` loads without error and an inline PNG renders in kitty;
      a remote-image markdown reference downloads via `curl` and renders.
