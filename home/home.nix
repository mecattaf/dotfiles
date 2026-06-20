{ ... }:
# home-manager — Layer 1 bridge. MINIMAL for now (skeleton evaluation).
# Next increments fill in (per dotfiles-sweep.md + nvim-sweep.md):
#   - RAW out-of-store symlink configs (niri/kitty/fish/…) — TEMPORARY scaffolding;
#     the committed end-state is maximally nix-native.
#   - user packages (eza/zoxide/atuin/starship/… from nixpkgs)
#   - 12 PWA .desktop launchers rewritten flatpak → google-chrome-stable --app (per-file)
#   - Claude Code config COPY activation
#   - programs.git (TYPED), the only typed exception
#   - nvim per nvim-sweep.md (programs.neovim + lazy-nix-helper)
{
  home.username = "tom";
  home.homeDirectory = "/home/tom";

  programs.home-manager.enable = true;

  home.stateVersion = "26.05";
}
