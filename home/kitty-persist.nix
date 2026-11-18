{
  inputs,
  lib,
  ...
}:
# kitty-persist — persistent native Kitty terminals (flake input
# `kitty-persist`). Two halves, each its own upstream Home Manager module:
#
#   programs.kittyPersist.holder   the host that owns the sessions: the
#       `kitty-persist-holder` binary on PATH (the seat reaches it with a
#       plain `ssh -T <host> kitty-persist-holder bridge <id>`), the
#       xterm-kitty terminfo, the idle template unit `kitty-persist@.service`
#       and 0700 runtime/state/cache directories.
#   programs.kittyPersist.client   the host with the Kitty windows: the
#       `kitten-persist` binary, the Kitty-side kittens, wl-clipboard and two
#       generated files under ~/.config/kitty-persist/.
#
# Both are OFF here. A host turns its half on in its own file (hosts/nas,
# hosts/client), the way agencyKitty is gated per host.
#
# KITTY CONFIG. ~/.config/kitty is a whole-directory raw link, so nothing
# generated can live inside it (same constraint as kitty-scrollback-nix.conf
# and agency-kitty/kitty.conf). The client module writes
# ~/.config/kitty-persist/kitty.conf at a neutral path, with every kitten path
# resolved to the store, and the raw kitty.conf includes it; Kitty ignores the
# include on a host where the client is off.
#
# LIFECYCLE. Sessions must outlive the window, the ssh connection and a
# compositor restart, so nothing here is PartOf=graphical-session.target, and
# the template unit is Restart=no: a session that died is reported as lost,
# never started again under the same id. Lingering for the user is a host
# setting and is not changed here.
{
  imports = [
    inputs.kitty-persist.homeManagerModules.holder
    inputs.kitty-persist.homeManagerModules.client
  ];

  # The fleet's existing ssh name for the brain host (modules/fleet-hosts.nix).
  # mkDefault: a host that holds its own sessions sets "local" instead.
  programs.kittyPersist.client.host = lib.mkDefault "nas";
}
