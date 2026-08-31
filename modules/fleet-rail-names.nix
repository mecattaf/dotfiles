# Cable-bound names for the two USB4 rails (#266).
#
# THE PROBLEM THIS CLOSES. `thunderbolt0` is not a cable. It is whichever of
# the two USB4 NHIs won the race to register tbnet on this boot, and until
# this module every consumer in the fleet bound to it by that name: the two
# NM profiles, both firewall doors, fn-rdma's roce_netdev and its UDP 4791
# door, and usb4-stream's rail entry point. The 2026-08-31 12:27 reboot
# proved it is not theoretical — the names flipped on BOTH twins at once, so
# tb-fleet's 10.99.0.x /30 came up on cable B while the stream provisioner
# (which anchors on the NHI, and was therefore right) stayed on cable A, and
# tb-fleet2 — which demanded interface-name=thunderbolt1 AND match.path=cable
# B, by then a contradiction — parked itself. Rail 2 went dark exactly as its
# author intended it to, which is the good half of that story; the bad half
# is that a name-bound rail 0 had already moved cables silently.
#
# THE FIX, AND WHY A RENAME IS SAFE HERE. tb-fleet.nix's 2026-08-31 note
# rejected a .link rename because "renaming inside the kernel's thunderbolt%d
# namespace races EEXIST when two netdevs swap". That objection is real and
# it does not apply to this module: the EEXIST race needs the source and
# target namespaces to OVERLAP (rename thunderbolt0 -> thunderbolt1 while the
# other device still holds the name). Renaming OUT to a disjoint namespace —
# rail0/rail2, which the kernel never mints — can never collide, whichever
# order the two devices probe in.
#
# The names encode the rail numbering the rest of the fleet already speaks,
# so there is no second vocabulary to learn:
#
#   rail0   cable A   coord 0000:c5:00.6 <-> worker 0000:c4:00.5   10.99.0.x/30
#   rail2   cable B   coord 0000:c5:00.5 <-> worker 0000:c4:00.6   10.99.2.x/30
#   (rail 1 is the 5GbE, enp191s0, 10.99.1.x/30 — already a stable name)
#
# The cable map is triple-verified (unique_id reciprocity, configfs hopid
# interlock, byte-counter cross-match; #275) and the two cabling crossings
# cancel, which is why cable A reaches domain1 on the coordinator and domain0
# on the worker. That asymmetry is the reason the table below is keyed by
# hostName and the values are soldered PCI functions: one host's constant can
# never be consulted on the other, and a wrong value fails CLOSED (the netdev
# keeps its kernel name, every profile that wants rail0/rail2 parks, and the
# rail-2 tripwire fires) rather than addressing the wrong cable.
#
# THIS TABLE IS THE FLEET'S ONE COPY. modules/usb4-stream.nix's railNhi reads
# cableA from here rather than repeating it — the previous duplicate pair was
# the shape that produced #267, where a stale constant sat in one file and
# silently disagreed with the hardware.
#
# IF THE CABLES ARE EVER RE-PLUGGED into swapped ports, these paths go stale
# on BOTH ends at once. Update both hosts in one commit, from
# `udevadm info /sys/class/net/rail0 | grep ID_PATH`.
{ config, lib, ... }:
let
  cfg = config.myFleetRails;
  # udev's ID_PATH for a PCI function, which is what .link's Path= matches.
  idPath = fn: "pci-${fn}";
in
{
  options.myFleetRails = {
    enable = lib.mkEnableOption "cable-bound rail0/rail2 names for the two USB4 rails (#266)";

    cableA = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default =
        {
          coordinator = "0000:c5:00.6";
          worker = "0000:c4:00.5";
        }
        .${config.networking.hostName} or null;
      defaultText = lib.literalMD ''
        per-host table — coordinator `"0000:c5:00.6"`, worker `"0000:c4:00.5"`;
        `null` on hosts that are not twins
      '';
      description = ''
        PCI function of the NHI that cable A — the fast rail, 10.99.0.x, the
        one usb4-stream provisions — enters on THIS host. Named `rail0`.
      '';
    };

    cableB = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default =
        {
          coordinator = "0000:c5:00.5";
          worker = "0000:c4:00.6";
        }
        .${config.networking.hostName} or null;
      defaultText = lib.literalMD ''
        per-host table — coordinator `"0000:c5:00.5"`, worker `"0000:c4:00.6"`;
        `null` on hosts that are not twins
      '';
      description = ''
        PCI function of the NHI that cable B — rail 2, 10.99.2.x, the bench
        and aggregation cable — enters on THIS host. Named `rail2`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.cableA != null && cfg.cableB != null;
        message = ''
          myFleetRails.enable is on but this host (${config.networking.hostName})
          has no entry in the cable table. Add its two NHI functions to
          modules/fleet-rail-names.nix, read from
          `udevadm info /sys/class/net/thunderbolt* | grep ID_PATH`.
        '';
      }
      {
        assertion = cfg.cableA != cfg.cableB;
        message = ''
          myFleetRails.cableA and cableB are both ${toString cfg.cableA} on
          ${config.networking.hostName}. The two rails are separate NHIs on
          separate domains; identical values would race both .link files onto
          one device and leave the other rail unnamed.
        '';
      }
    ];

    # Driver= is belt-and-braces next to Path=: it keeps the rename off any
    # non-tbnet netdev that might ever appear under the same PCI function.
    # These sort before 99-default.link, and .link units are honored by udev
    # whether or not systemd-networkd is enabled — this fleet runs
    # NetworkManager, which consumes the renamed device normally.
    systemd.network.links."10-rail0" = {
      matchConfig = {
        Path = idPath cfg.cableA;
        Driver = "thunderbolt-net";
      };
      linkConfig.Name = "rail0";
    };
    systemd.network.links."10-rail2" = {
      matchConfig = {
        Path = idPath cfg.cableB;
        Driver = "thunderbolt-net";
      };
      linkConfig.Name = "rail2";
    };
  };
}
