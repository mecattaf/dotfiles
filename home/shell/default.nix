{
  config,
  lib,
  pkgs,
  ...
}:
# home/shell: the Home Manager entry point of the consolidated Wayland shell
# (lane code-nix-wiring, 2026-10-22, branch dryrun/shell-consolidation-2026-10-22).
#
# What it is. One module that home/home.nix imports next to ./vicinae.nix. It
# imports the sibling shell modules other lanes write under home/shell/ and
# places the raw files of the shell that home.nix does not already place. The
# description of the shell lives in docs/shell/SHELL.md (ruling R1); this file
# only wires.
#
# Sibling modules. Each is imported only when it exists, so a lane that has
# not landed, or a file that is not yet tracked by git (a flake source only
# carries tracked files), never breaks evaluation:
#   session.nix  idle, lock and capture (lane code-session-idle-lock-capture,
#                ruling R4: swayidle plus swaylock beside sway-local.conf)
# A new sibling is one more line in `siblings`.
#
# Raw files, and why vicinae is NOT a whole directory link. home.nix links
# sway, kitty and fish as whole directories (`configDirs`). ~/.config/vicinae
# cannot be one: home/vicinae.nix already places files inside it
# (vicinae/commands.toml here, the settings file through the Vicinae module),
# and a whole directory link would make those entries land inside the link
# target, a read only store path on the client (rawDotfiles.inStore) and the
# checkout everywhere else (INFERRED from how Home Manager builds home files,
# not measured by a build). So the palette script is linked as a single file,
# through the same `link` helper home.nix uses, which already respects
# rawDotfiles.inStore (home/raw-dotfiles-guard.nix).
#
# Why `palette` is a PATH wrapper and not ~/.local/bin/palette. ~/.local/bin
# is itself one whole directory link (home.nix: home.file.".local/bin").
# Home Manager cannot place a second file inside it for the same reason as
# above. The wrapper lands in ~/.nix-profile/bin, which is on the session PATH
# (home.nix home.sessionPath), and execs the linked script, so editing
# home/dot_config/vicinae/palette still hot reloads on hosts with a checkout.
# TODO(code-sway-config, 2026-10-22): palette.conf calls ~/.local/bin/palette
# and falls back to `vicinae toggle`; point $palette at plain `palette`, or
# commit a relative symlink home/dot_local/bin/palette pointing at
# ../../dot_config/vicinae/palette (owner of home/dot_local/bin decides).
#
# Deliberately absent: no option changes to Sway, kitty, fish or Vicinae, no
# host gating (each sibling gates itself), no font files (fonts are named by
# family only, bytes stay on the NAS behind requireFile).
let
  link = config.lib.rawDotfiles.link;

  siblings = [ ./session.nix ];

  paletteScript = "${config.xdg.configHome}/vicinae/palette";

  paletteWrapper = pkgs.writeShellScriptBin "palette" ''
    # palette: PATH entry for ~/.config/vicinae/palette (home/shell/default.nix).
    exec ${pkgs.bash}/bin/bash ${lib.escapeShellArg paletteScript} "$@"
  '';
in
{
  imports = builtins.filter builtins.pathExists siblings;

  # The palette script, next to the catalog home/vicinae.nix already links
  # at ~/.config/vicinae/commands.toml (the script's default PALETTE_CATALOG).
  # `executable` stays unset: on an out of store link Home Manager would try
  # to copy the target to set a mode; the wrapper runs it through bash anyway.
  xdg.configFile."vicinae/palette".source = link "dot_config/vicinae/palette";

  home.packages = [ paletteWrapper ];
}
# Not verified
# Home Manager build of the home files on any host (only parse and eval ran).
# That `palette` collides with no other program of that name on PATH.
# No second reader (Tom's light verification rule, 2026-10-20).
