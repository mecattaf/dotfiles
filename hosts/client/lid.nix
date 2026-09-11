{ ... }:
# client lid semantics — the lid does NOTHING, on any power source, in any dock
# state. F10 (the backlight toggle that lands on binds.kdl's F10 row with the
# rest of the client's chords) is the explicit "go dark" verb on this seat.
# Plan Q-15, closed with its default on 2026-09-11; §4.2's logind row is the
# argument.
#
# ── why a file at all: the two-display clause ───────────────────────────────
# dotfiles set no lid option anywhere before this (`grep -rn HandleLidSwitch
# modules/ hosts/ home/*.nix` was empty fleet-wide), so the client inherited
# logind's defaults: HandleLidSwitch = "suspend", HandleLidSwitchDocked =
# "ignore". systemd 261.2 logind.conf(5) says which of the two applies: "If the
# system is inserted in a docking station, or if more than one display is
# connected, the action specified by HandleLidSwitchDocked= occurs".
#
# On THIS machine the display count is not a property of the lid, it is a
# property of the keyboard:
#
#   keyboard detached → eDP-1 and eDP-2 are both connected → more than one
#     display → the *Docked* action (ignore) → closing the lid does not
#     suspend. niri then turns the internal panel off on its own ("niri will
#     already automatically turn the internal laptop monitor on and off in
#     accordance with the laptop lid", niri 26.04 wiki
#     Configuration:-Switch-Events.md), so eDP-1 goes dark and every window
#     migrates onto eDP-2 — the panel underneath the closed lid.
#
#   keyboard snapped on → modules/zenbook-duo-daemon.nix forces eDP-2's DRM
#     status to `off` → exactly one display → the *plain* action (suspend) →
#     the same gesture suspends the box.
#
# One physical gesture, two opposite outcomes, selected by where the keyboard
# happens to be sitting. That is the defect being fixed here, not the choice of
# action: the seat has to answer the lid the same way every time.
#
# ── why ignore rather than suspend ─────────────────────────────────────────
# The client is a thin client into the coordinator: the work is ssh sessions
# and a herdr projector, and suspending the seat tears down exactly the state
# Tom is in the middle of. "Go dark" also happens far more often than "go
# away" on a two-panel laptop that lives open on a desk. So the lid is made
# inert on all three keys and the dark verb is made explicit and reversible:
# F10 saves and zeroes intel_backlight (`brightnessctl -s -d intel_backlight
# set 0`) and restores it (`-r`), with the daemon's 500 ms sync carrying eDP-2
# along. HandleLidSwitchExternalPower is set too, otherwise the answer would
# still change when the charger is plugged in.
#
# ── the accepted consequence ───────────────────────────────────────────────
# A closed lid in a bag does not sleep. The machine keeps running until the
# battery reaches the floor, where upower powers it off
# (hosts/client/default.nix:201-204, percentageAction = 5, criticalPowerAction
# = "PowerOff"). There is no swap partition and therefore no hibernate, so
# that floor is a clean shutdown, not a resume. Tom carries this device rarely
# (R-14/R-16: boots are expensive and rare); if that changes, the fix is a
# ruling to flip these three keys to "suspend", not a special case.
#
# ── the recovery path, if the eDP-1-off migration is the real nuisance ──────
# Step 8 of the plan exercises lid-close in both dock states. If windows
# sliding onto the panel under the closed lid turns out to be what actually
# annoys, the countermeasure is a niri switch-events block in the CLIENT's
# generated ~/.config/niri-local.kdl (written by home/home.nix), NOT here:
#
#   switch-events {
#       lid-close { spawn-sh "~/.local/bin/brightness off"; }
#       lid-open  { spawn-sh "~/.local/bin/brightness restore"; }
#   }
#
# (~/.local/bin/brightness has had off/restore/toggle since M-3; F10 on the
# client already calls `toggle`). That is a compositor concern and
# belongs in the per-host niri slot; this file stays the logind half of the
# answer either way.
{
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "ignore";
  };
}
