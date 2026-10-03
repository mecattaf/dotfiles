{ lib, ... }:
# A physical seat gets a compositor, greetd and (on niri) Piri. Herdr remains
# independent of graphical-session.target. Coordinator and client are seats;
# worker and NAS are not. The optional headless browser desktop is a separate
# capability.
#
# scroll/transition (2026-10-01): the compositor is a choice. `session` picks
# what greetd starts; `keepNiri` keeps niri installed beside scroll for
# rollback (flip `session` back to "niri" and rebuild). modules/common.nix
# derives programs.scroll / programs.niri / greetd from these three options.
{
  options.myDisplay = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether this host runs a physical desktop and greeter.";
    };

    session = lib.mkOption {
      type = lib.types.enum [
        "scroll"
        "niri"
      ];
      default = "scroll";
      description = ''
        The compositor greetd starts on this seat. "scroll" (dawsers/scroll
        master, modules/scroll.nix) is the default on the scroll/transition
        branch; "niri" is the rollback.
      '';
    };

    keepNiri = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Keep niri (programs.niri, its portals table and niri-session) installed
        on a scroll seat, so rolling back is a one-option rebuild and
        `niri-session` stays startable from a VT. Turned off at niri
        retirement (scoping S9).
      '';
    };
  };
}
