{
  config,
  lib,
  pkgs,
  ...
}:
# raw-dotfiles-guard (#313, 2026-09-13).
#
# Every raw dotfile (home/home.nix `link`, home/herdr.nix, home/nvim.nix) is an
# out-of-store symlink into the checkout at `rawDotfiles.repoDir`, never into
# the flake a switch was taken from; that is what makes hot-reload-by-editing
# work, and #313 keeps it (option 2, anchoring at the switched flake, would
# move hot-reload to whichever tree was switched from). So a switch taken from
# a worktree delivers the store half and silently drops the raw half, and a
# unit whose ExecStart is `%h/.local/bin/<program>` can land while <program>
# does not exist yet.
#
# This module fails the activation instead: before checkLinkTargets and
# writeBoundary (so before any backup move, linkGeneration and every unit
# reload), each such program must be executable in the checkout. A missing
# checkout only warns.
#
# Coverage: ExecStart, ExecStartPre and ExecStartPost of Home Manager user
# units whose command (or a list element) STARTS with `%h/.local/bin/`.
# A program reached through an interpreter (`python3 $HOME/.local/bin/x`)
# is not matched.
#
# Deliberately NOT here: the flake's rev. A "store half from <rev>, raw half
# from <HEAD>" note would put inputs.self.rev into the Home Manager generation
# and change every host's toplevel drvPath on every commit, the whole-source
# coupling flows/tally-flows.nix just removed. `git -C ~/mecattaf/dotfiles
# log -1` answers the same question on demand.
#
# IN-STORE HOSTS (`rawDotfiles.inStore`, 2026-10-11). A host that sets it
# carries no checkout at all: every raw dotfile is copied from the flake source
# into the Nix store, so both halves of a switch come from the same rev and the
# deploy is the only update path. The client sets it (hosts/client/default.nix,
# Tom: "i dnt need here" about ~/dotfiles and ~/mecattaf on the thin client),
# which also turns off this guard there (nothing to check) and
# modules/dotfiles-bootstrap.nix (nothing to clone). Hot-reload by editing is
# given up on such a host; nothing there writes into the raw tree at runtime.
# Every other host keeps the out-of-store links unchanged.
#
# The three readers (home.nix, herdr.nix, nvim.nix) build their links with
# config.lib.rawDotfiles.{link,path}, so the choice is made here once.
let
  cfg = config.rawDotfiles;
  # `p` is relative to home/ in this repository.
  inStoreSource = p: ./. + "/${p}";
  programOf =
    cmd:
    let
      m = builtins.match "%h/\\.local/bin/([^ ]+)( .*)?" cmd;
    in
    if m == null then [ ] else [ (builtins.head m) ];
  commandsOf =
    unit:
    lib.concatMap (
      k: map toString (lib.toList ((unit.Service or { }).${k} or [ ]))
    ) [ "ExecStart" "ExecStartPre" "ExecStartPost" ];
  guard = pkgs.callPackage ../pkgs/raw-dotfiles-guard.nix { };
in
{
  options.rawDotfiles = {
    inStore = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Copy every raw dotfile from the flake source into the Nix store instead
        of linking it out of store into `repoDir`. The host then needs no
        checkout, and a switch or deploy is its only update path.
      '';
    };
    repoDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/mecattaf/dotfiles";
      readOnly = true;
      description = "The checkout every raw dotfile links into (not the flake source).";
    };
    programs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      internal = true;
      default = lib.sort lib.lessThan (
        lib.unique (
          lib.concatMap (u: lib.concatMap programOf (commandsOf u)) (
            lib.attrValues config.systemd.user.services
          )
        )
      );
      description = "Programs under ~/.local/bin that this generation's user units execute.";
    };
  };

  config = {
    # link: a Home Manager `source` for one raw file or directory.
    # path: the same thing as an absolute path string (a .desktop Icon=).
    # Out of store, both are byte-identical to what the readers built before.
    lib.rawDotfiles = {
      link =
        p:
        if cfg.inStore then
          inStoreSource p
        else
          config.lib.file.mkOutOfStoreSymlink "${cfg.repoDir}/home/${p}";
      path = p: if cfg.inStore then "${inStoreSource p}" else "${cfg.repoDir}/home/${p}";
    };

    # Before checkLinkTargets as well as writeBoundary: with
    # home-manager.backupFileExtension set (flake.nix), checkLinkTargets already
    # moves colliding files aside, which is a write. An in-store host has no
    # checkout to check: its programs are in the generation itself.
    home.activation.rawDotfilesGuard = lib.mkIf (!cfg.inStore) (
      lib.hm.dag.entryBefore [ "checkLinkTargets" "writeBoundary" ] ''
        ${lib.getExe guard} ${lib.escapeShellArgs ([ cfg.repoDir ] ++ cfg.programs)}
      ''
    );
  };
}
