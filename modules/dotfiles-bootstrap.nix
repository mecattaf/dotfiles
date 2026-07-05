{ pkgs, ... }:
# Ensure tom's dotfiles checkout exists at ~/mecattaf/dotfiles before the graphical
# session starts. home-manager deploys ~/.config/* and ~/.local/bin as OUT-OF-STORE
# symlinks into that path (home/home.nix `mkOutOfStoreSymlink`, for niri hot-reload);
# on a fresh flash the checkout is absent so every config dangles and niri boots on
# defaults (the jul5 duo bug). Two layers deliver it:
#
#   PRIMARY  — the flash operator stages a full clone into the nixos-anywhere
#              --extra-files bundle and `--chown /home/tom/mecattaf/dotfiles 1000:100`,
#              so the repo is on disk before the box ever boots (see the flash runbook).
#   FALLBACK — this oneshot. It only fires when the primary was skipped/failed
#              (ConditionPathExists gate → "skipped", not "failed", when .git exists),
#              e.g. a rebuilt VM or a flash that forgot the flag. Ordered before greetd
#              so niri sees the config; soft network-online + non-fatal so a network-
#              less boot degrades to default config instead of a hung login screen.
#
# Clone-to-temp + atomic mv means an interrupted clone never leaves a half-populated
# dir that the ConditionPathExists gate would mistake for "done" (the wedge the earlier
# greetd-wrapper had).
let
  repoDir = "/home/tom/mecattaf/dotfiles";
  repoUrl = "https://github.com/mecattaf/dotfiles.git";
  cloneScript = pkgs.writeShellScript "dotfiles-bootstrap-clone" ''
    set -u
    repo="${repoDir}"
    tmp="$repo.bootstrap-tmp"
    ${pkgs.coreutils}/bin/rm -rf "$tmp"
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$repo")"
    echo "dotfiles-bootstrap: cloning ${repoUrl} -> $repo" >&2
    if ${pkgs.git}/bin/git clone "${repoUrl}" "$tmp"; then
      ${pkgs.coreutils}/bin/rm -rf "$repo"
      ${pkgs.coreutils}/bin/mv "$tmp" "$repo"
      echo "dotfiles-bootstrap: checkout ready" >&2
    else
      echo "dotfiles-bootstrap: clone failed (offline?) — niri will use default config; retry next boot" >&2
      ${pkgs.coreutils}/bin/rm -rf "$tmp"
      exit 1
    fi
  '';
in
{
  systemd.services.dotfiles-bootstrap = {
    description = "Ensure ${repoDir} checkout exists (home-manager out-of-store configs need it)";
    wantedBy = [ "multi-user.target" ];
    before = [ "greetd.service" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    # No-op ("condition skipped", not a failure) once the checkout is present — so it
    # costs nothing on hosts provisioned via --extra-files, and self-heals otherwise.
    unitConfig.ConditionPathExists = "!${repoDir}/.git";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "tom";
      Group = "users";
      TimeoutStartSec = "120";
      ExecStart = cloneScript;
      # A failed clone must NOT block boot/login — treat exit 1 as tolerated so the
      # unit finishes; the gate re-runs it next boot since .git still won't exist.
      SuccessExitStatus = "0 1";
    };
  };

  # greetd waits for the checkout to land (so niri reads the real config on first
  # boot), but softly: Wants, not Requires, and a skipped/failed bootstrap still lets
  # the login proceed rather than wedging the greeter.
  systemd.services.greetd = {
    after = [ "dotfiles-bootstrap.service" ];
    wants = [ "dotfiles-bootstrap.service" ];
  };
}
