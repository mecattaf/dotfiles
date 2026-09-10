{ ... }:
# ─── The emergency rail: official tailscale.com, and ONLY here (2026-09-01) ───
#
# Tom's ruling 2026-09-01, alongside the headscale landing: official
# tailscale.com is RETIRED fleet-wide and survives on this box alone, as an
# always-connected-but-idle fallback. Idle is the design, not neglect — nothing
# routes over it in normal operation, and that is exactly what makes it
# trustworthy the one day it is needed.
#
# WHAT IT IS FOR, in one sentence: this box plus the Freebox wifi rail
# (./uplink-nas.nix's `freebox-uplink` profile) is the escape hatch when the NAS
# is offline. Every other remote path into the house now runs THROUGH the NAS —
# it is the router, the LAN resolver, and since 2026-09-01 the tailnet control
# plane (hosts/nas/headscale.nix). A NAS that is down or mid-rebuild therefore
# takes all of them down together, including the tailnet that would have been
# used to fix it. This rail owes the NAS nothing: a different control plane, a
# different uplink, a different box.
#
# THEREFORE, THE STANDING RULE: this file must never be "cleaned up" because
# headscale exists now. hosts/nas/headscale.nix carries the same warning from
# the other side. A fallback that shares a dependency with the thing it backs up
# is not a fallback, and the two things this one must not share are the NAS's
# control plane and the NAS's uplink.
#
# NOT A HEADSCALE CLIENT, on purpose: there is deliberately no --login-server
# here. That absence is the whole content of "official tailscale.com" — the
# flag's presence is what makes the NAS a client of its own server, and this box
# keeps controlplane.tailscale.com precisely so that a broken headscale cannot
# reach it.
#
# Consequence, accepted: reaching this box over the emergency rail is a
# tailscale.com session, so it depends on Tailscale's hosted coordination server
# and on the account behind it. That is a dependency on someone else's uptime,
# which is the reason the NAS moved off it — and simultaneously the reason it is
# the right choice HERE, since the failure being planned for is the house's own
# infrastructure, not Tailscale's.
#
# HISTORY: until 2026-09-01 all of this lived in modules/common.nix as a
# fleet-wide default (enable + --ssh on both flag paths) with the wayvnc :5900
# door beside it. The tombstone there records why the default had to go; what
# follows is that default, narrowed to the one host that ever wanted it.
{
  services.tailscale.enable = true;

  # Tailscale SSH: reach this box over the tailnet from any underlying network,
  # authenticated by tailnet identity — no user keypair needed on this path,
  # which is the point when the emergency is "the key material is on the laptop
  # I do not have". KEEP IT: emergency access IS what this rail is for, and an
  # emergency rail you cannot log in over is decoration.
  #
  # The flag goes on BOTH paths and both halves earn their place: `extraUpFlags`
  # lets the autoconnect unit recover a STOPPED node whose stored preferences
  # already have SSH enabled (`tailscale up` insists on being told every
  # non-default preference), while `extraSetFlags` repairs an ALREADY-RUNNING
  # node on every activation.
  #
  # NB: requires an `ssh` rule in the tailnet ACL allowing tag:mesh → tag:mesh
  # for users [autogroup:nonroot, root] — added in the Tailscale admin console.
  # That ACL lives in tailscale.com's console, NOT in
  # hosts/nas/headscale-policy.hujson; the two control planes share no policy.
  services.tailscale.extraUpFlags = [ "--ssh" ];
  services.tailscale.extraSetFlags = [ "--ssh" ];

  # The authkey needs no wiring here and deliberately gets none: the house
  # pattern in modules/secrets.nix delivers
  # secrets/tailscale-authkey-coordinator.age as `age.secrets.tailscale-authkey`
  # and sets services.tailscale.authKeyFile from it, gated on
  # `services.tailscale.enable && the per-host ciphertext exists`. Both halves
  # are true here and only here (secrets.nix scopes that ciphertext to
  # `coordinatorOnly`), so the enable above is what arms the join — and the
  # worker's mkForce-false is what keeps a stale key from ever re-joining it.
  # That same block orders tailscaled-autoconnect after network-online.target
  # with a 1-minute retry, which is the fix for this box's original first-boot
  # race (the boot-time `tailscale up` predated wifi association, refs #37) and
  # matters more on a rail whose whole job is to come back unattended.
  #
  # The NAS reaches the same "no secret at rest" property a different way — its
  # key is minted at runtime by its own headscale into /run — so do not read
  # that file's arrangement as a pattern to copy here. A pre-minted single-use
  # key is correct for a control plane we do not own.

  # wayvnc (:5900) is reachable ONLY over the tailnet — never the raw LAN/wifi.
  # Relocated from modules/common.nix 2026-09-01 with the rest of this tier.
  # This is the coordinator's door only: the NAS opens its own for the TV
  # session (hosts/nas/tv.nix, an exact-set assert in flake.nix guards it), and
  # the worker has no tailscale0 for such a rule to land on at all. The wayvnc
  # server itself is home-manager's (home/remote.nix) and runs with NO
  # authentication, so "which interface" IS the access control — which is why
  # this stays interface-scoped and never becomes a global allowedTCPPorts.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 5900 ];
}
