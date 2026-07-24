# The device mesh — ONE source of truth for the 4 hosts, consumed by both the SSH
# trust plumbing (modules/mesh.nix) and the Remmina VNC profiles (home/remote.nix).
#
# Per host: `aliases` (every name/IP the host answers to) and two PUBLIC keys that
# are safe to commit. Fill them in once, AFTER a host's first boot:
#   hostKey — the box's SSH host key:   cat /etc/ssh/ssh_host_ed25519_key.pub
#   userKey — tom's SSH user key:        cat ~/.ssh/id_ed25519.pub   (ssh-keygen -t ed25519 if absent)
# Commit the two lines → every OTHER host then trusts this one with zero TOFU, and
# tom on this host can reach the others. Empty keys are simply skipped, so the config
# stays valid while a host is still un-flashed.
# Host keys were generated offline (2026-07-05); the private halves live in the
# secrets-staging install-files/ tree and are delivered at install via
# `nixos-anywhere --extra-files`. userKey is the shared `tom@mesh` key (private half
# on the operator box + USB). See the agenix handoff.
{
  coordinator = {
    aliases = [
      "coordinator"
      "10.77.0.1"
    ];
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFPCZFlnHQSNH3D0R1/qs9A/W498f8xTNUNBtLWZgU2A root@coordinator";
    userKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAlTzKx0n2pQ4/1qv3mThyyh1+QCuT/Qcg+/40Nr1JB6 tom@mesh";
  };
  worker = {
    aliases = [
      "worker"
      "10.77.0.2"
    ];
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC9xaf+UX4cjDEme+Ath3EZYLiUJla/+3QlG4TvCzwLO root@worker";
    userKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAlTzKx0n2pQ4/1qv3mThyyh1+QCuT/Qcg+/40Nr1JB6 tom@mesh";
  };
  zenbook-duo = {
    aliases = [ "zenbook-duo" ];
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKvikHKjh49tlT9PDlG47hcRWyz8NX7uWw2ZhQoQJxxP root@zenbook-duo";
    userKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAlTzKx0n2pQ4/1qv3mThyyh1+QCuT/Qcg+/40Nr1JB6 tom@mesh";
  };
}
