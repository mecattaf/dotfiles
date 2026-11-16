# Friends' Macs Tom administers over Tailscale. Each one is a node shared INTO
# Tom's tailnet from its owner's own tailnet: Tom is not a member of theirs, and
# the owner can revoke the share at any time.
#
# Kept apart from ./mesh-registry.nix on purpose: that file is the NixOS fleet,
# and its consumers (builders, NFS/journal admission, fleet-status fan-out,
# authorized_keys) must never pick these up. These rows only feed SSH: host-key
# pinning (./mesh.nix) and the `<name>-mac` aliases (../home/ssh.nix).
#
# Access is regular SSH with Apple Remote Login, never Tailscale SSH (the Mac
# app cannot serve it to a guest on a shared node). The login key is tom's
# mesh key (tom@mesh-20260729) in the owner's ~/.ssh/authorized_keys.
#
# hostKey: the Mac's /etc/ssh/ssh_host_ed25519_key.pub, checked against the
# fingerprint the owner reported from the machine itself. Do not rename a Mac:
# that can rename its Tailscale node and break the share.
{
  marwan = {
    user = "marwan";
    aliases = [
      "100.123.54.36"
      "mh-macbook-air.tailc491c1.ts.net"
    ];
    # SHA256:kdeeZAwAOUkj6ptXgE6qvQATyFB7FmqP7Ve6VPrTu/g, matched against the
    # fingerprint Marwan's Mac reported on 2026-11-16. MacBook Air, arm64,
    # macOS 27.2.1. Admin user, passwordless sudo via
    # /etc/sudoers.d/tom-temp-access, Full Disk Access for remote users.
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIJSqlmKzEKrLZYuBExvyBhW4cVhZuAazisxbdX3XeP";
  };

  frank = {
    user = "frankschmid";
    aliases = [
      "100.65.237.124"
      "frankschmids-mac-studio.tail662ae6.ts.net"
    ];
    # The key first accepted into ~/.ssh/known_hosts (node share since
    # 2026-10-16), still presented unchanged on 2026-11-16. Passwordless sudo
    # confirmed the same day.
    hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ+gMa4nJg1hfKJ7C/f3Cd3L2CKc7h8sYJU4YFXD0vik";
  };
}
