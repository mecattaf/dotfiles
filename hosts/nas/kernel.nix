{ freshPkgs, ... }:
# ── Linux 7.2 on the frozen appliance: the one deliberate exception ────────
#
# The NAS base system rides nixpkgs-stable (#135) and stays there. The KERNEL
# alone is lifted to the 7.2 series (#244 fleet migration, NAS scope added
# 2026-08-29), because the A8500 mt7925u uplink dongle is this box's whole
# reason to exist as a router and 7.1.x keeps failing it in the field:
#
#   * 2026-08-23 — firmware wedge, 4.5 days dead until a hand power-cycle
#     (#235; wan-watchdog.nix was born from that post-mortem).
#   * 2026-08-29 13:01:49 — the Freebox deauthed wan0 with Reason 16
#     (GROUP_KEY_HANDSHAKE_TIMEOUT): the firmware missed a group-key rekey.
#     The watchdog ladder recovered it in ~4 min (rungs 1-2 failed, rung 3
#     USB re-enumeration worked), but the coordinator had already failed
#     over to the Freebox rail 100 s earlier and sat there all afternoon.
#
# 7.2 is where the mt7925 payoff lives: the comprehensive wedge-class fixes
# that were still in upstream review on 7.1.x (research note 2026-08-28 in
# wan-watchdog.nix), plus the A8500's USB ID entering the stock mt7925u
# table — which is what retired the a8500-new-id shim (see router.nix).
#
# Sourcing doctrine, in order of what was rejected:
#   * stable's linuxPackages_latest — 7.1.5, doesn't have the fixes.
#   * unstablePkgs (main `nixpkgs` input) — pinned at 7.1.4 at the time of
#     writing; the twins deliberately hold that pin until the fn-rdma
#     re-bake (#244), and the NAS must not wait on that campaign.
#   * freshPkgs.linuxPackages_latest — would silently jump to 7.3 the next
#     time fresh moves for chrome/uv. Wrong risk profile for a house router.
#   * freshPkgs.linuxPackages_7_2 — CHOSEN: the versioned attr advances only
#     within the 7.2.x stable series on fresh updates (point fixes yes,
#     series jumps never). When 7.2 ages out of nixpkgs entirely, eval
#     breaks loudly and this file gets a deliberate successor — the same
#     fail-loud-not-drift shape as the rest of the fleet's pins.
#
# A kernel is self-contained against the stable userland (no ZFS here, btrfs
# only, no out-of-tree modules on this host) — this is NOT a precedent for
# mixing fresh into the appliance's package set. Reboot to take effect is
# Tom's hand at the box (he wants the BIOS auto-power-on toggle checked in
# the same visit); until then the running 7.1.5 keeps its live new_id
# binding, so removing the shim from the closure is safe on a live switch.
{
  boot.kernelPackages = freshPkgs.linuxPackages_7_2;
}
