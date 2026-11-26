# Client-side helpers that Imagine calls by name. The first two need no NAS chat
# service, a Host restart or provider credentials.
# - agent windows: NAS agents open a fresh NAS terminal on this desktop
#   without taking focus (kitty-dsh agent-windows protocol, version 1).
# - layout identity: the running desktop's incarnation key, which Imagine's
#   layout persistence uses (~/.local/bin/agency-layout-identity).
# - agency-relay: the rail's session catalogue (Imagine's `sessionCatalogue.relay`),
#   the NAS floor's `agency relay --watch` frames over BatchMode ssh (R41).
{ lib, pkgs, ... }:
let
  agencyRelay = pkgs.writeShellApplication {
    name = "agency-relay";
    runtimeInputs = [ pkgs.openssh pkgs.coreutils ];
    # The file keeps its own shebang for reading and running by hand.
    text = lib.removePrefix "#!/bin/sh\n" (builtins.readFile ./imagine-helpers/agency-relay/agency-relay);
  };
in
{
  home-manager.users.tom = {
    home.packages = [ agencyRelay ];
    home.file.".local/lib/kitty-dsh/agent-windows-v1".source = ./imagine-helpers/agent-windows;
    xdg.configFile."kitty-dsh/agent-windows.json".text = builtins.toJSON {
      launcher = "/home/tom/.local/lib/kitty-dsh/agent-windows-v1/client";
    };
    home.file.".local/lib/imagine-layout/layout_identity.py".source = ./imagine-helpers/layout_identity.py;
  };
}
