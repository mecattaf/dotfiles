# The device mesh — ONE source of truth for the fleet's NixOS hosts, consumed by
# the SSH trust plumbing (modules/mesh.nix). Until the 2026-09-11 headless flip
# it also fed the Remmina VNC profiles; there is no VNC in the fleet now.
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
    aliases = [
      "coordinator"
      # The static LAN address (hosts/coordinator/uplink-nas.nix).
      "10.42.0.2"
    ];
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFPCZFlnHQSNH3D0R1/qs9A/W498f8xTNUNBtLWZgU2A root@coordinator";
    userKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINwxGJ4IgTFfdMI+A2SDJO/E3jsZ7M/5McAioO87VX8Z tom@mesh-20260729";
  };
  # PERMANENTLY BACK (Tom's ruling 2026-08-21: "the worker is FULLY BACK to
  # my device list. not a lease"). This is the very device whose 2026-07-29
  # departure forced the fleet key rotation.
  #
  # hostKey was read live from the running box on ruling day and is UNCHANGED
  # by the #229 reintegration — that is deliberate and load-bearing: because the
  # box keeps its host key, agenix keeps decrypting (the host key IS the agenix
  # identity) and every other host's known_hosts stays valid, which is why the
  # reintegration is a `nixos-rebuild switch --target-host` and not a reflash.
  #
  # userKey was held EMPTY from 2026-08-21 until this commit, on purpose: the
  # box was still running the pre-rotation closure that holds the OLD tom@mesh
  # key, and authorizing that key anywhere would have undone the rotation its
  # own departure forced. It now carries the SHARED ROTATED key —
  # byte-identical to the coordinator's row (and, since 2026-09-11, to the
  # client's) — because the
  # closure that ships with this commit delivers exactly that key to the box
  # (modules/secrets.nix, ssh-user-key.age, re-minted here to include this
  # host). The old tom@mesh key is never to reappear in this file.
  #
  # One rail, one alias: the LAN identity 10.42.0.5 (static in
  # hosts/worker/default.nix, pinned by name in hosts/nas/network.nix and
  # modules/fleet-hosts.nix). An alias that answers nowhere only buys TOFU
  # prompts against a host that cannot reply, so nothing else is listed.
  worker = {
    aliases = [
      "worker"
      "10.42.0.5"
    ];
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC9xaf+UX4cjDEme+Ath3EZYLiUJla/+3QlG4TvCzwLO root@worker";
    userKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINwxGJ4IgTFfdMI+A2SDJO/E3jsZ7M/5McAioO87VX8Z tom@mesh-20260729";
  };
  # The ASUS Zenbook Duo UX8406MA, back as Tom's thin client on 2026-09-11
  # after three days as Marwan's Omarchy laptop in omarchy-fleet. hostKey is
  # the key omarchy-fleet generated offline on 2026-09-07 and delivered at its
  # flash — read live off the box on return day and REUSED on purpose: the
  # return is an in-place `nixos-rebuild switch --target-host`, and keeping
  # the key is what lets the delivered tier decrypt and every other host's
  # known_hosts stay valid (the worker's 2026-08-21 precedent). It is not the
  # 2026-07-05 `zenbook-duo` key, which left the tree with that host and is
  # public in git history. userKey is the shared rotated fleet key, same
  # string as the twins.
  #
  # Two aliases: the name, and the DHCP lease the NAS hands this MAC
  # (a0:b3:39:06:75:a7 → 10.42.0.16, pinned in hosts/nas/router.nix). The NAS
  # resolver serves no DHCP client names, so the twins carry the `client` →
  # .16 line in modules/fleet-hosts.nix and the address rides here so ssh to
  # it stays TOFU-free.
  client = {
    aliases = [
      "client"
      "10.42.0.16"
    ];
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAoNjOhvz1H+SO5AhDdb4Z1FZlzUC+/KlMR1Oa7V0+YM root@zenbook-duo";
    userKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINwxGJ4IgTFfdMI+A2SDJO/E3jsZ7M/5McAioO87VX8Z tom@mesh-20260729";
  };
  nas = {
    aliases = [
      "nas"
      # The LAN identity, and the only one. The 2026-08-20 rewire's second
      # transitional rail — the direct 10.77.0.0/30 cable — is retired: the
      # cable is physically gone and the address answers nowhere, so keeping
      # it here only bought TOFU prompts against a host that cannot reply
      # (#264).
      "10.42.0.1"
    ];
    # Generated on the appliance's first installed boot (2026-08-01) and read
    # over the direct /30 cable. Deliberately NOT --copy-host-keys: that would
    # have inherited key material first generated by the vendor OS.
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ0sfr0Sr5HaHKEAn/aO4qPbixN7PDYwIpuQvLlue4dU root@nas";
    # The appliance is inbound-only; coordinator deploys to it over the cable.
    userKey = "";
  };
}
