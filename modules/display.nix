{ lib, ... }:
# myDisplay — is there a seat in front of this box?
#
# A DISPLAY HOST is one a human sits at: it gets the compositor
# (programs.niri) and the greeter (services.greetd autologin to niri), both
# derived from this option in modules/common.nix, and it is the only kind of
# host where the display-bound user services mean anything — voxtype
# (home/voxtype.nix: dictation wtypes into the FOCUSED window) and piri
# (home/piri.nix: a niri IPC daemon, which needs a niri to talk to); wayvnc
# (home/remote.nix) was the third until the 2026-09-11 headless flip deleted
# it. Everything else in the tree — the herdr server, tally,
# the halogen client, the timers, the shell — is display-independent and
# stays exactly where it is.
#
# The default is TRUE because that is what the tree already says: common.nix
# turns the greetd→niri session on fleet-wide with plain assignments and the
# exceptions opt OUT. The worker (hosts/worker/default.nix) and any appliance
# running the headless profile (modules/headless.nix, i.e. the NAS) set it
# false; hosts/client needs no line at all, which is right — the client IS
# the seat as of 2026-09-11 (R-1/R-5, docs/zenbook-duo-return-2026-09-11.md).
#
# WHY IT EXISTS: the coordinator flipped to false on 2026-09-11, right after
# the client seat was proven (R-13; plan §8.3, §10 steps 9-11) — no
# compositor, no greeter, no VNC anywhere in the fleet, ssh and a blind VT
# getty its only inputs. Because niri, greetd, voxtype and piri (and wayvnc,
# while it existed) all derive from this one option, that flip was ONE line
# in hosts/coordinator/default.nix. What this
# is NOT is a free-standing feature flag: the flake's `home-profiles` check
# asserts each of those facts as an EQUALITY against this option, so a
# half-flip — the session off but the wayvnc unit, the :5900 door or the
# viewer profile still generated — does not build. Flip the line and delete
# the display-bound modules in the same commit, or answer to the check.
#
# NB: a fifth host added tomorrow is a seat unless it opts out. That is the
# honest default for a fleet of workstations, and the flake's hard-coded
# `displayHosts` list makes the omission visible at eval time.
{
  options.myDisplay.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Whether this host has a seat: a compositor, a greeter, and the
      display-bound user services (voxtype, piri). False on the worker, on
      headless appliances, and on the coordinator since 2026-09-11, when
      the thin client became Tom's only seat.
    '';
  };
}
