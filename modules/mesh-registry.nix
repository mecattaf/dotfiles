# The device mesh — ONE source of truth for the three NixOS hosts, consumed by
# both the SSH trust plumbing (modules/mesh.nix) and the Remmina VNC profiles
# (home/remote.nix).
#
# Per host: `aliases` (every name/IP the host answers to) and two PUBLIC keys that
# are safe to commit. Fill them in once, AFTER a host's first boot:
#   hostKey — the box's SSH host key:   cat /etc/ssh/ssh_host_ed25519_key.pub
#   userKey — tom's SSH user key:        cat ~/.ssh/id_ed25519.pub   (ssh-keygen -t ed25519 if absent)
# Commit the two lines → every OTHER host then trusts this one with zero TOFU, and
# tom on this host can reach the others. Empty keys are simply skipped, so the config
# stays valid while a host is still un-flashed.
# Host keys were generated offline (2026-07-05); the private halves live in the
# operator recovery bundle and are delivered at install via
# `nixos-anywhere --extra-files`. userKey is the fleet SSH key rotated on
# 2026-07-29 after the previous key was exposed on a returned device. It is an SSH
# login key only, never an agenix editor recipient; see ../secrets.nix.
{
  coordinator = {
    aliases = [ "coordinator" ];
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFPCZFlnHQSNH3D0R1/qs9A/W498f8xTNUNBtLWZgU2A root@coordinator";
    userKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINwxGJ4IgTFfdMI+A2SDJO/E3jsZ7M/5McAioO87VX8Z tom@mesh-20260729";
  };
  nas = {
    aliases = [
      "nas"
      "10.77.0.2"
    ];
    # Filled from the first installed boot before this draft can merge. Empty
    # means deploy-rs correctly refuses TOFU rather than trusting a guessed key.
    hostKey = "";
    # The appliance is inbound-only; coordinator deploys to it over the cable.
    userKey = "";
  };
  zenbook-duo = {
    aliases = [ "zenbook-duo" ];
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKvikHKjh49tlT9PDlG47hcRWyz8NX7uWw2ZhQoQJxxP root@zenbook-duo";
    userKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINwxGJ4IgTFfdMI+A2SDJO/E3jsZ7M/5McAioO87VX8Z tom@mesh-20260729";
  };
}
