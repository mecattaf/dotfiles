{ lib, ... }:
# ─── fleet-hosts: the twins' name→address table ─────────────────────────────
#
# THE TWINS ONLY (imported from hosts/coordinator/default.nix and
# hosts/worker/default.nix). The NAS deliberately does NOT get this file: it
# carries its own pins in hosts/nas/network.nix and keeps the stock loopback
# self-mapping, because it is an appliance and not a rank in a job.
#
# WHAT THIS UNDOES, and why it cost a night (#273). Stock NixOS gives every host
#   networking.hosts."127.0.0.2" = [ hostName ]
# (nixpkgs nixos/modules/config/networking.nix, `hostnames` — FQDN first when
# networking.domain is set, which it is not here). Fine on a laptop. On a
# two-node compute fleet it is a trap, because a large class of distributed
# libraries discovers "its own" address by calling gethostname() and binding
# whatever that resolves to:
#   1. honour an explicit override, else
#   2. resolve the hostname and bind it IF IT RESOLVES, else
#   3. fall back to loopback and WARN.
# Step 2 succeeds. 127.0.0.2 is a perfectly usable address, so the loopback
# fallback and its warning never fire: both boxes advertise a loopback address
# to each other and the peer's own loopback refuses the connection. Measured on
# these two boxes, torch 2.13.0+rocm7.14.0 / Gloo, two ranks:
#   [rank0] hostname coordinator -> 127.0.0.2 | GLOO_SOCKET_IFNAME=None
#   failed to connect ... local=[127.0.0.1]:162 remote=[127.0.0.2]:9608
#   error=SO_ERROR: Connection refused  -> Engine core initialization failed
#   [rank0] FAIL after 6.3s     [rank1] HUNG until a 90 s hard kill
# Note the asymmetry: rank 0 errors in six seconds, rank 1 hangs forever. In a
# service that is a silent hang with an empty log, not a diagnosable crash. On a
# distro that maps the hostname to 127.0.1.1, or to nothing at all, the same bug
# is LOUD. NixOS's specific choice is what disguises it.
#
# So: each twin's own name resolves to its own LAN address, and the PEER's name
# to the peer's. The twins share nothing but the house LAN — the worker is
# wired into the BE550 in another room — so these are the only answers, and
# they are static on both boxes (hosts/coordinator/uplink-nas.nix .2,
# hosts/worker/default.nix .5). A coordinator whose wifi is down will find that
# gethostname() resolves to an address it does not currently hold, and a
# binder will fail LOUDLY there instead of binding loopback quietly: that is
# the intended trade.
#
# ⚠ HAZARDS — /etc/hosts IS NOT AN ORDERED ANSWER HERE. Two of them:
#   (1) nsswitch on these boxes is
#         hosts: mymachines mdns4_minimal [NOTFOUND=return] resolve \
#                [!UNAVAIL=return] files myhostname dns
#       `resolve` comes BEFORE `files` and LLMNR is on (+LLMNR -mDNS), so
#       systemd-resolved answers first and /etc/hosts is consulted through it,
#       not instead of it.
#   (2) When one name has TWO entries, resolved decides the order, NOT the file.
#       Proven live 2026-08-31: the worker's /etc/hosts listed `10.42.0.5 worker`
#       BEFORE `127.0.0.2 worker`, yet `getent ahosts worker` returned
#       127.0.0.2 first. And nixpkgs renders networking.hosts with
#       `lib.attrNames`, i.e. LEXICOGRAPHIC by address string.
#   Consequence, and the rule this file follows: every name gets EXACTLY ONE
#   answer per host. Never two entries reconciled by ordering — that is not a
#   knob we own. The pins below are therefore the twins' ONLY entries for these
#   two names; hosts/nas/network.nix carries the NAS's, and modules/common.nix
#   must not grow a fleet-wide copy that would double them here (the flake
#   asserts the exact lists).
{
  # nixpkgs filters empty lists out of /etc/hosts (stringHosts uses
  # `filterAttrs (_: v: v != [])`), so mkForce [] DELETES the line rather than
  # emitting a bare, malformed "127.0.0.2". mkForce, not a merge: the stock
  # definition is a plain one, not mkDefault.
  networking.hosts."127.0.0.2" = lib.mkForce [ ];

  # Both LAN identities on both twins: self so gethostname() binds the LAN,
  # peer so cross-node hostname use reaches it. Registry aliases
  # (modules/mesh-registry.nix), so ssh to either name stays TOFU-free.
  networking.hosts."10.42.0.2" = [ "coordinator" ];
  networking.hosts."10.42.0.5" = [ "worker" ];
}
