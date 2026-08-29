{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myNasClient;
  socketProxyd = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd";

  # #139. One poke below the mountpoint is the whole fix; everything else here
  # is the bound on how long that poke may cost a login. Budget: each attempt
  # gets 5s (enough to fire the automount trigger; a cold soft-mount round is
  # timeo=100 now and may outlive the poke — fine, findmnt below is what
  # decides), and the
  # retry loop gives up 10s in — the retries exist only for the cold-boot case,
  # where greetd autologins tom→niri (modules/common.nix) while enp191s0 or the
  # NAS itself is still a couple of seconds behind. Success is checked against
  # the kernel, not against `ls`: a failed automount leaves the empty autofs
  # trigger directory in place, which `ls` reports as an ordinary empty dir.
  warmNasAutomount = pkgs.writeShellScript "nas-automount-warm" ''
    deadline=$(( $(${pkgs.coreutils}/bin/date +%s) + 10 ))
    while :; do
      ${pkgs.coreutils}/bin/timeout 5s ${pkgs.coreutils}/bin/ls /mnt/nas/ >/dev/null 2>&1 || :
      ${pkgs.util-linux}/bin/findmnt --type nfs4 --mountpoint /mnt/nas >/dev/null 2>&1 && exit 0
      [ "$(${pkgs.coreutils}/bin/date +%s)" -ge "$deadline" ] && exit 0
      ${pkgs.coreutils}/bin/sleep 1
    done
  '';
in
{
  options.myNasClient = {
    useRemoteStorage = lib.mkEnableOption "mounting the NAS NFS export at the historical /mnt/nas path";
    relayMedia = lib.mkEnableOption "relaying tailnet Immich and Navidrome traffic to the Ethernet-only NAS";
    # Separate gates, not additions to relayMedia: relayMedia is LIVE, and each
    # of these turns on with its own NAS-side gate in its own commit.
    # relayAttic stays declared solely so the flake's topology check can
    # assert it is FALSE forever (the 2026-08-21 direct-serve move made a
    # relay architecturally wrong, not merely unused).
    relayAttic = lib.mkEnableOption "DEAD OPTION — never enable; the NAS serves the cache directly since 2026-08-21";
    relayPaperless = lib.mkEnableOption "relaying tailnet Paperless traffic to the Ethernet-only NAS (#136)";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.useRemoteStorage {
      boot.supportedFilesystems = [ "nfs" ];
      # soft/timeo/retrans are the load-bearing options: with the default hard
      # mount, a dead NAS makes every I/O on /mnt/nas retry FOREVER in the
      # kernel, and on 2026-08-02 that wedged PID 1 mid `nixos-rebuild switch`
      # long enough for the 30s hardware watchdog (modules/strix.nix) to reset
      # the box. soft stays; timeo/retrans were retuned for the 2026-08-20
      # rewire: the original timeo=50/retrans=2 (~15s worst case) was sized
      # for the dedicated /30 cable, where any retry meant the NAS was
      # genuinely down. This mount now rides wifi (this box → BE550 → wire →
      # NAS), where multi-second stalls are ordinary contention, not death —
      # timeo=100 (10s/try, deciseconds) + retrans=3 (~70s worst case with
      # backoff) keeps EIO for real outages without surfacing it on every
      # busy-airtime moment. Mind the 2m hardware watchdog (strix.nix:128):
      # a single op still bounds well inside it. No x-systemd.device-timeout:
      # 'nas:/' is not a device path, so systemd ignores it with a warning on
      # every generator run.
      fileSystems."/mnt/nas" = {
        device = "nas:/";
        fsType = "nfs4";
        options = [
          "noatime"
          "nofail"
          "noauto"
          "soft"
          "timeo=100"
          "retrans=3"
          "x-systemd.automount"
          "x-systemd.mount-timeout=30s"
          "_netdev"
        ];
      };

      # ── NFS readahead: undo the kernel's 128KB default (2026-08-29) ────────
      # Since kernel ~5.18 every NFS mount gets a 128KB bdi readahead window
      # regardless of rsize (it used to be 15x rsize = 15MB). On this wifi
      # path's ~2.7ms RTT that starves the RPC pipeline: measured live on this
      # box, a sequential Library read did 88 MB/s stock and 113 MB/s at 16MB
      # readahead — within ~6% of the raw-TCP ceiling (~120 MB/s), so this one
      # knob closes the whole NFS-vs-TCP gap. The knobs it replaces: rsize/
      # wsize already negotiate to 1MB (checked live, do not add them), and
      # nconnect is not worth a remount — a single stream already saturates
      # the air (~74% of the 1297 Mbit/s PHY rate is normal wifi MAC
      # efficiency).
      #
      # Hooked to the MOUNT UNIT, not boot: the bdi device is recreated with
      # the 128KB default on every automount trigger, so the setter must
      # re-fire each time the mount comes up.
      systemd.services.nfs-nas-readahead = {
        description = "Raise NFS readahead on /mnt/nas (kernel default 128KB caps the wifi path at ~88MB/s)";
        wantedBy = [ "mnt-nas.mount" ];
        after = [ "mnt-nas.mount" ];
        serviceConfig.Type = "oneshot";
        script = ''
          echo 16384 > "/sys/class/bdi/$(${pkgs.util-linux}/bin/mountpoint -d /mnt/nas)/read_ahead_kb"
        '';
      };

      # ── #139: warm the automount before the graphical session ──────────────
      # home/home.nix points the Music/Videos XDG user dirs and the Photos
      # bookmark at /mnt/nas. When the automount is still cold at session start
      # those paths do not resolve, GLib drops them, and the Nautilus sidebar
      # comes up without them — `nautilus -q` plus a relaunch on a warm mount
      # was the manual workaround. Nothing sets TimeoutIdleSec on the automount,
      # so mounting it once at session start keeps it up for the rest of the
      # boot and every later-launched app sees real directories.
      #
      # Ordered Before= but only Wants=/WantedBy= graphical-session.target: niri
      # itself is likewise Before= that target, so the compositor comes up in
      # parallel and even the worst case delays session-scoped services (portals,
      # piri), never the desktop appearing. A dead NAS therefore degrades to
      # exactly today's behaviour — sidebar entries absent — bounded by the
      # script's own 10s deadline, with TimeoutStartSec as the hard backstop for
      # the pathological case where the poke is stuck in the kernel (a start-job
      # timeout completes the job, so the target is never held past it). The
      # soft-mount options above stay untouched: this only touches the mount, it
      # does not change what happens when the touch fails.
      #
      # The "-" prefix keeps a cold NAS from marking the unit failed: an
      # unreachable NAS is a normal outcome here, not something worth a marker
      # in modules/failure-surfacing.nix (which watches per-user units too).
      systemd.user.services.nas-automount-warm = {
        description = "Warm the /mnt/nas automount before the graphical session";
        before = [ "graphical-session.target" ];
        # PartOf so a logout resets this oneshot and the next session warms the
        # mount again; the user manager lingers, so without it a second login in
        # the same boot would skip the poke.
        partOf = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "-${warmNasAutomount}";
          TimeoutStartSec = "20s";
        };
      };
    })

    (lib.mkIf cfg.relayMedia {
      assertions = [
        {
          assertion = !config.myCoordinatorMedia.enable;
          message = "coordinator media core and NAS relay cannot own ports 2283/4533 together";
        }
      ];

      systemd.sockets.immich-relay = {
        description = "Coordinator front door for Ethernet-only NAS Immich";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = "0.0.0.0:2283";
          NoDelay = true;
        };
      };
      systemd.services.immich-relay = {
        description = "Relay Immich to nas:2283 over the private link";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = "${socketProxyd} nas:2283";
          DynamicUser = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
        };
      };

      systemd.sockets.navidrome-relay = {
        description = "Coordinator front door for Ethernet-only NAS Navidrome";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = "0.0.0.0:4533";
          NoDelay = true;
        };
      };
      systemd.services.navidrome-relay = {
        description = "Relay Navidrome to nas:4533 over the private link";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = "${socketProxyd} nas:4533";
          DynamicUser = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
        };
      };

      systemd.sockets.plex-relay = {
        description = "Coordinator front door for Ethernet-only NAS Plex";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = "0.0.0.0:32400";
          NoDelay = true;
        };
      };
      systemd.services.plex-relay = {
        description = "Relay Plex to nas:32400 over the private link";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = "${socketProxyd} nas:32400";
          DynamicUser = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
        };
      };

      # Existing clients keep coordinator.tail8dd1.ts.net; only coordinator has
      # a Tailscale identity, and these sockets relay across the private cable.
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
        2283
        4533
        32400
      ];

      # Memorable intranet front doors ADDED on top of the port URLs, never
      # replacing them: photos/music/videos.internal resolve fleet-wide via
      # the per-box AdGuard rewrites (modules/adguardhome.nix) to whichever
      # coordinator address is closest to the asking host — loopback here, the
      # /30 cable on the NAS, the tailnet only from the roaming zenbook — and
      # Caddy (:80, see caddy-artifacts.nix for the matching firewall zones)
      # hands them to the same socket relays the port URLs use. Plain HTTP by
      # the same v1 posture as the artifact plane: WireGuard is the transport
      # security and `.internal` never resolves publicly.
      services.caddy.virtualHosts = {
        "http://photos.internal".extraConfig = ''
          reverse_proxy 127.0.0.1:2283
        '';
        "http://music.internal".extraConfig = ''
          reverse_proxy 127.0.0.1:4533
        '';
        "http://videos.internal".extraConfig = ''
          # Plex answers 401 on its bare API root; the human entrance is /web.
          redir / /web/ 302
          reverse_proxy 127.0.0.1:32400
        '';
      };
    })

    # ── NAS reachability tripwire (2026-08-21, "who watches the watcher") ──
    # The NAS is the house's router, DNS, cache, and archive; if it goes dark
    # the failure smells like "the internet is broken", not "the NAS died".
    # This box is the only always-on witness with its own escape hatch (the
    # Freebox fallback rail), so it carries the watch: a ping probe every
    # 5 minutes, a failure marker (shown at next interactive login) after
    # sustained silence. Marker-based like everything else — no paging.
    {
      myTripwire.nas-reachability = {
        description = "the NAS answers pings on its LAN address";
        intervalSeconds = 300;
        onBootSec = "5min";
        threshold = 1;
        comparison = "ge";
        # Sustained silence, not a single lost probe: ~15 min dark before
        # the marker fires (three consecutive failed 5-min probes).
        sustainSeconds = 900;
        rearm = 0;
        refractorySeconds = 21600;
        valueField = "NAS_DARK";
        sensorPath = [ pkgs.iputils ];
        sensor = ''
          if ping -c 2 -W 3 10.42.0.1 >/dev/null 2>&1; then
            echo "0 nas 1"
          else
            echo "1 nas 1"
          fi
        '';
        onFirePath = [ pkgs.coreutils ];
        onFire = ''
          mkdir -p /var/lib/failure-markers
          printf '%s — the NAS has not answered pings for ~15 min (episode %s)\n  the house router may be down: check TV-corner HDMI console, power, BE550\n' \
            "$(date '+%Y-%m-%d %H:%M')" "$4" \
            > /var/lib/failure-markers/nas-reachability
        '';
      };
    }

    # (The #130 ws5 binary-cache relay that lived here was DELETED 2026-08-21:
    # the direct-serve move made it dead code — every host dials
    # http://nas:8080/fleet itself. See hosts/nas/attic.nix.)

    # ── #136: Paperless relay ───────────────────────────────────────────────
    # The durable tailnet front door for the NAS-hosted Paperless backend:
    # a declarative Caddy route (paperless.internal, same .internal doctrine
    # as the media front doors above) plus a port relay. Like attic, no wake
    # proxy — Paperless is always-on on the NAS (consumer + scheduler; see
    # the exception note in hosts/nas/paperless.nix). Deliberately NOT a TTL
    # artifact drop-dir entry: this route outlives any artifact sweep.
    (lib.mkIf cfg.relayPaperless {
      systemd.sockets.paperless-relay = {
        description = "Coordinator front door for NAS Paperless";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = "0.0.0.0:28981";
          NoDelay = true;
        };
      };
      systemd.services.paperless-relay = {
        description = "Relay Paperless to nas:28981 over the private link";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = "${socketProxyd} nas:28981";
          DynamicUser = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
        };
      };

      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 28981 ];

      services.caddy.virtualHosts."http://paperless.internal".extraConfig = ''
        reverse_proxy 127.0.0.1:28981
      '';
    })
  ];
}
