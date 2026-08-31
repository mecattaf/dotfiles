{ ... }:
# The flashnext TP=2 lane, as far as systemd is concerned (#270).
#
# Until 2026-08-31 the dual-Strix flashnext plane was INVISIBLE to systemd:
# grepping this whole config for "flashnext" found the anti-prune artifact,
# the fn-rdma staging path, and comments — no unit, no Conflicts, no After,
# no slice. Arbitration against llama-swap existed only one-directionally and
# imperatively: the flashnext repo's host/fn-cluster-up.sh stops llama-swap on
# both twins and records an arrival state (swap-arbitration.json,
# arrival: inactive|active) so its teardown can restore what it found. That
# protocol protects a flashnext run from llama-swap; nothing protects
# llama-swap from flashnext, and nothing protects either from NixOS itself —
# a `nixos-rebuild switch` restarts llama-swap underneath a live TP=2 run
# (measured stakes: ~77.6 GiB/rank claimed by flashnext against a llama-swap
# that runs with LimitMEMLOCK=infinity, both entitled to most of one 128 GiB
# UMA pool — a memory fight, not a port clash), and after any reboot
# llama-swap returns automatically while the podman pair does not.
#
# This target is the dotfiles-side half of the handshake: a declared name the
# flashnext scripts wrap themselves in, carrying a mutual Conflicts with
# llama-swap so systemd itself enforces "exactly one plane holds the GPUs" in
# BOTH directions, on each twin, surviving reboots and rebuilds.
#
# REBOOT BEHAVIOR IS A DECISION, NOT A DEFAULT (chosen here, 2026-08-31):
# llama-swap wins on boot. The target is deliberately wantedBy NOTHING — after
# a reboot llama-swap (wantedBy multi-user.target) rises and the flashnext
# lane stays down until an operator or script starts it. The previous answer
# ("llama-swap wins because it is the only one systemd knows about") was the
# same outcome inherited by accident; now it is written down. Stopping the
# target likewise does NOT restart llama-swap: teardown of a TP=2 run leaves
# the box quiet, and llama-swap returns only via explicit `systemctl start
# llama-swap` or the next boot/switch. That replaces the arrival-state
# restore, which could not stay correct across a switch it never saw.
#
# What the flashnext side must do to complete the handshake (scripts live in
# github.com/mecattaf/flashnext, out of this repo's reach):
#   fn-cluster-up.sh:   systemctl start flashnext-lane.target on BOTH twins
#                       (locally and via ssh worker) BEFORE podman brings up
#                       either rank — the target is per-box and arbitrates
#                       only its own llama-swap; starting it only on the
#                       coordinator leaves the worker's proxy free to swap
#                       gemma4-31b onto the rank-1 shard, the exact blindness
#                       #270 names. Then run each rank as a transient unit
#                       bound to the lane, e.g.
#                         systemd-run --unit=fn-rank0 \
#                           --property=BindsTo=flashnext-lane.target \
#                           --property=After=flashnext-lane.target -- podman ...
#                       so losing the lane tears the rank down instead of
#                       orphaning it.
#   fn-cluster-down.sh: systemctl stop flashnext-lane.target on both twins;
#                       drop the swap-arbitration.json arrival-restore for
#                       llama-swap (the restore decision now lives above).
#
# HAZARDS:
#  * Conflicts is symmetric EVICTION, not admission control. `systemctl start
#    llama-swap` while the lane is active — including a nixos-rebuild switch
#    that restarts a *changed* llama-swap unit — stops the lane (and every
#    rank BindsTo'd to it). Deliberate: the invariant is "one holder", and a
#    loud teardown of the loser beats two engines allocating out of the same
#    125 GiB pool. A switch during a TP=2 run therefore still kills the run;
#    it can no longer corrupt the arbitration state.
#  * The two twins' targets are independent. systemd cannot express the
#    cross-node atom; until the #270 gateway row (or llama-swap `peers`
#    federation) lands, the both-twins start/stop ordering above IS the
#    cross-node protocol, and a hand-run that skips the worker recreates the
#    old blindness there.
{
  systemd.targets.flashnext-lane = {
    description = "flashnext dual-Strix TP=2 lane (holds this twin's GPUs; mutually exclusive with llama-swap)";
    # Mutual exclusion, direction 1: starting the lane stops llama-swap.
    conflicts = [ "llama-swap.service" ];
    # ONE ordering edge, deliberately not two. systemd orders a stop job
    # before a start job across an After= edge in BOTH mixed transactions, so
    # this single line already means "the loser finishes dying before the
    # winner rises" whichever direction the eviction runs (llama-swap's 2min
    # TimeoutStopSec backend unload completes before ranks allocate, and the
    # lane's teardown completes before the proxy binds). Declaring the mirror
    # After= on llama-swap as well would create an ordering cycle the moment
    # both units hold stop jobs in one transaction (shutdown.target), which
    # systemd breaks by deleting an arbitrary job.
    after = [ "llama-swap.service" ];
  };

  # Mutual exclusion, direction 2, declared explicitly even though systemd's
  # Conflicts already acts both ways — so that reading EITHER unit shows the
  # arbitration, and so this half survives if the target's stanza is ever
  # edited in isolation.
  systemd.services.llama-swap.conflicts = [ "flashnext-lane.target" ];
}
