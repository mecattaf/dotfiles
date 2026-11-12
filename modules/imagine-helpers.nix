# Client-side helpers that Imagine calls by name. Neither needs a NAS chat
# service, a Host restart or provider credentials.
# - agent windows: NAS agents open a fresh NAS terminal on this desktop
#   without taking focus (kitty-dsh agent-windows protocol, version 1).
# - layout identity: the running desktop's incarnation key, which Imagine's
#   layout persistence uses (~/.local/bin/agency-layout-identity).
{ ... }:
{
  home-manager.users.tom = {
    home.file.".local/lib/kitty-dsh/agent-windows-v1".source = ./imagine-helpers/agent-windows;
    xdg.configFile."kitty-dsh/agent-windows.json".text = builtins.toJSON {
      launcher = "/home/tom/.local/lib/kitty-dsh/agent-windows-v1/client";
    };
    home.file.".local/lib/imagine-layout/layout_identity.py".source = ./imagine-helpers/layout_identity.py;
  };
}
