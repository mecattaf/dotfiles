{ inputs, lib, ... }:
# Every closure records the flake revision it was built from:
# system.configurationRevision (read by `nixos-version --json` and
# fleet-status) and $out/fleet-revision.json {rev, dirty, lastModified}.
# Moved here unchanged from modules/update-adopt.nix when that module was
# deleted (2026-09-30, no clock-fired adoption in dotfiles).
let
  self = inputs.self;
  fleetRevision = {
    rev = self.rev or self.dirtyRev or "unknown";
    dirty = !(self ? rev);
    lastModified = self.lastModified or 0;
  };
in
{
  system.configurationRevision = lib.mkDefault fleetRevision.rev;
  system.systemBuilderCommands = ''
    printf '%s\n' ${lib.escapeShellArg (builtins.toJSON fleetRevision)} > "$out/fleet-revision.json"
  '';
}
