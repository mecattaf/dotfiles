{ lib, ... }:
# ─── fleet-hosts: the twins' name→address table ─────────────────────────────
#
# THE TWINS ONLY (imported from hosts/coordinator/default.nix and
# hosts/worker/default.nix). The NAS deliberately does NOT get this file — see
# the §worker pin note at the bottom.
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
# is LOUD. NixOS's specific choice is what disguises it. Same shape applies to
# MPI, Dask, Ray in some modes, and several other torch backends; a per-library
# env pin (GLOO_SOCKET_IFNAME landed downstream in flashnext as the immediate
# unblock) fixes exactly the one library you thought of and nothing else.
#
# So: each twin's own name resolves to its own FLEET IDENTITY, and the PEER's
# name to the peer's. 10.99.9.x/32 is already this estate's declared stable
# identity (hosts/coordinator/eth-fleet.nix:15 "the STABLE identity", :51 and
# hosts/worker/default.nix:332 `ip addr replace 10.99.9.x/32 dev lo`). Two
# properties make it the right target here:
#   - it lives on lo, so gethostname() can never resolve to an address that goes
#     down with a cable, a link, or an AP association;
#   - it is routable from the peer over whichever rail is up — the eth-fleet
#     /32 route at metric 20 (eth-fleet.nix:75, worker/default.nix:350) with the
#     imperative Thunderbolt route behind it at 50 (#240 flip).
# After this, every library in the class above finds a correct, reachable
# address with no application-level pin at all.
#
# Pointing the PEER's name at the wire is the other half (#277): the fleet-wide
# `worker` pin used to answer 10.42.0.5, the house 6 GHz wifi. Measured
# coordinator -> worker on 2026-08-31: 26.977/104.895/167.264 ms min/avg/max to
# 10.42.0.5 against 0.096/0.109/0.126 ms to 10.99.9.2 — ~960x on average and
# wildly variable (the 8.862 ms in #277 no longer reproduces; wifi got worse,
# not better). Anything fleet-side resolving a peer by name silently took the
# slow path and nothing at this layer would flag it. This estate has already
# paid for that twice in other guises: Ray advertised the wifi address on both
# nodes until --node-ip-address, and vLLM's get_ip() (UDP-probes 8.8.8.8, reads
# the local sockname = the default route = wlp192s0) did the same until
# VLLM_HOST_IP was pinned per node. Both were found by running into them.
#
# ⚠ HAZARDS — /etc/hosts IS NOT AN ORDERED ANSWER HERE. Two of them:
#   (1) nsswitch on these boxes is
#         hosts: mymachines mdns4_minimal [NOTFOUND=return] resolve \
#                [!UNAVAIL=return] files myhostname dns
#       `resolve` comes BEFORE `files` and LLMNR is on (+LLMNR -mDNS), so
#       systemd-resolved answers first and /etc/hosts is consulted through it,
#       not instead of it. Proven live on 2026-08-31, before this file existed:
#       on the worker `getent hosts coordinator` returned 10.99.1.1 — the
#       eth-fleet address, learned over LLMNR on enp191s0 — while the worker had
#       no `coordinator` line in /etc/hosts at all.
#   (2) When one name has TWO entries, resolved decides the order, NOT the file.
#       Also proven live: the worker's /etc/hosts listed `10.42.0.5 worker`
#       BEFORE `127.0.0.2 worker`, yet `getent ahosts worker` returned
#       127.0.0.2 first. And nixpkgs renders networking.hosts with
#       `lib.attrNames`, i.e. LEXICOGRAPHIC by address string, so "10.42.0.5"
#       sorts ahead of "10.99.9.2" regardless of declaration order anyway.
#   Consequence, and the rule this file follows: every name gets EXACTLY ONE
#   answer per host. Never two entries reconciled by ordering — that is not a
#   knob we own.
#   That rule is why the 10.42.0.5 `worker` pin no longer lives in
#   modules/common.nix (fleet-wide, therefore also on the twins, where the wifi
#   line even SORTED FIRST) and is host-scoped to hosts/nas/network.nix instead
#   (#277, 2026-08-31): the NAS's Immich genuinely wants the wifi answer for
#   http://worker:3003, the twins genuinely want the wire, and those are two
#   host-scoped answers rather than one ambiguous pair. The flake asserts the
#   absence on the twins, not merely the presence on the NAS.
#
# ⚠ A service that binds by hostname now depends on systemd-services
# fleet-identity being up (it puts 10.99.9.x on lo). That unit is a oneshot at
# network-pre.target, i.e. before anything that could bind — but a unit that
# binds the hostname and starts EARLIER than that would now fail loudly instead
# of binding loopback quietly. That is the intended trade: loud beats silent.
#
# NOT DONE, deliberately: the `coordinator.fleet` / `worker.fleet` alias shape
# #277 offers as its alternative. Extra names at every call site buy
# unambiguity we get for free from one-answer-per-host, and would leave the
# loopback self-mapping (the actual #273 bug) in place.
{
  # nixpkgs filters empty lists out of /etc/hosts (stringHosts uses
  # `filterAttrs (_: v: v != [])`), so mkForce [] DELETES the line rather than
  # emitting a bare, malformed "127.0.0.2". mkForce, not a merge: the stock
  # definition is a plain one, not mkDefault.
  networking.hosts."127.0.0.2" = lib.mkForce [ ];

  # Both fleet identities on both twins: self so gethostname() binds the wire,
  # peer so cross-node hostname use takes the wire. Registry aliases
  # (modules/mesh-registry.nix), so ssh to either name stays TOFU-free.
  networking.hosts."10.99.9.1" = [ "coordinator" ];
  networking.hosts."10.99.9.2" = [ "worker" ];
}
