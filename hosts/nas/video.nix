{
  config,
  lib,
  pkgs,
  ...
}:
# ─── #130 ws1: Jellyfin on the NAS ──────────────────────────────────────────
#
# READ THIS BEFORE FLIPPING THE GATE — this module is NOT the video server that
# is running today.
#
# `hosts/nas/media.nix` already serves the `videos` subvolume with **Plex**
# (Tom's 2026-08-02 ruling, made after #130 was written and shipped in #131 /
# #132: coordinator relay on 32400, `videos.internal` front door, and
# `checks.nas-topology` asserts `services.plex.enable`). #130 ws1 predates that
# call and proposed Jellyfin. Both are implemented, only one is on.
#
# So this file is an ALTERNATIVE, staged gated-off. Nothing about enabling it is
# automatic, and nothing about it disturbs Plex: different ports (Plex 32400,
# Jellyfin 8096), different state dirs, different relays. They can legitimately
# run side by side against the same read-only-ish library while a comparison is
# made — two scanners over one tree is safe, they only read the media files.
#
# RUNBOOK — enable Jellyfin
#   1. hosts/nas/default.nix:            myNas.video.enable = true;
#      hosts/coordinator/default.nix:    myNasClient.relayVideo = true;
#      (both, in the same commit — the flake check asserts they agree.)
#   2. Deploy the NAS first, then the coordinator (same order as #131: the
#      backend must exist before the relay points at it).
#   3. Reach it at http://coordinator:8096/ from any tailnet host, or
#      http://jellyfin.internal/ once the AdGuard rewrite exists. First load
#      wakes the disk and can take ~20s; that is the wake proxy working.
#   4. In the web setup wizard add ONE library, type "Movies"/"Shows", pointed
#      at /mnt/nas/videos. Do not let Jellyfin write metadata next to the media
#      (Settings → Libraries → uncheck "Save artwork/NFO into media folder") —
#      that would dirty the LaCie mirror's videos tree with churn on every scan.
#   5. VERIFY VA-API ACTUALLY ENGAGES. This is the known failure mode: Jellyfin
#      silently falls back to software transcoding and the UI says nothing.
#      Force a transcode (play a file with a client set to a lower bitrate),
#      then, on the NAS:
#        journalctl -u jellyfin -n 200 | grep -i -- '-hwaccel\|vaapi\|Failed'
#      The ffmpeg command line must contain `-hwaccel vaapi` AND
#      `-init_hw_device vaapi=...:/dev/dri/renderD128`. If it shows `-c:v
#      libx264` with no vaapi device, hardware encode is NOT happening.
#      Cross-check the device itself is sane first:
#        vainfo --display drm --device /dev/dri/renderD128
#      (libva-utils is already in the headless package set.) Expect
#      VAProfileH264High / VAEntrypointEncSlice entries; `radeonsi` must load.
#      While a transcode runs, `sudo cat /sys/kernel/debug/dri/*/amdgpu_pm_info`
#      or a busy `radeontop` is the second, independent confirmation.
#   6. If you decide Jellyfin replaces Plex, that is a SEPARATE commit: drop
#      `services.plex` from media.nix, drop the plex relay + `videos.internal`
#      vhost from nas-client.nix, and update `checks.nas-topology`. Do not do it
#      in the same change that turns Jellyfin on — you want one variable at a
#      time when the question is "is this actually better".
#
# PORTS — why the NAS-side wake socket is 8095, not 8096
#   Jellyfin's HTTP port is NOT a NixOS option; it lives in its own network.xml
#   and is only settable at runtime. So jellyfin itself keeps the stock 8096 and
#   the wake socket takes 8095. The firewall admits ONLY 8095 from the
#   coordinator, so 8096 on the NAS is unreachable and every client necessarily
#   arrives through the wake proxy. Everything a human ever types stays :8096 —
#   the coordinator relay listens on 8096 and dials nas:8095.
let
  cfg = config.myNas.video;
  storageRoot = "/mnt/nas";
  libraryDir = "${storageRoot}/videos";
  inherit (import ./wake-helpers.nix { inherit lib pkgs; })
    socketProxyd
    waitForHttp
    proxyHardening
    ;
in
{
  options.myNas.video.enable = lib.mkEnableOption "Jellyfin on the NAS videos subvolume (#130 ws1; Plex in media.nix is the incumbent)";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.myNas.storage.enable;
        message = "myNas.video requires the verified myNas.storage mount";
      }
    ];

    services.jellyfin = {
      enable = true;
      # Same identity Immich/Navidrome/Plex run as, so the 0750 tom:users
      # `videos` subvolume is readable without loosening its mode. tom is in
      # `render` and `video` (modules/common.nix), which is what gets
      # /dev/dri/renderD128 open — the module sets DeviceAllow but does NOT add
      # a supplementary group, so a `jellyfin` system user would have hit
      # EACCES on the render node and fallen back to software transcoding.
      user = "tom";
      group = "users";
      hardwareAcceleration = {
        enable = true;
        type = "vaapi";
        device = "/dev/dri/renderD128";
      };
      # Without this, a pre-existing encoding.xml wins and the module only logs
      # a WARN — i.e. the exact silent-software-fallback this workstream is
      # supposed to prevent. With it, this file is the single source of truth
      # for encoding settings and the web dashboard's transcoding page is
      # overwritten on every restart. That tradeoff is deliberate.
      forceEncodingConfig = true;
      transcoding = {
        enableHardwareEncoding = true;
        # One rotating disk and one small APU: a second concurrent transcode
        # thrashes both. Direct play is NOT a transcode and is unaffected by
        # this limit, so in practice it only bites on a genuine second remux.
        maxConcurrentStreams = 1;
        # Stop reading (and therefore stop spinning the disk) once the encoder
        # is far enough ahead of the player.
        throttleTranscoding = true;
        # Reclaim the tmpfs when a stream stops instead of at session expiry —
        # the scratch is 2G, not 200G.
        deleteSegments = true;
      };
      # The firewall rule below is the access control; never let a module open
      # ports on every interface of an appliance.
      openFirewall = false;
    };

    # Transcode scratch on tmpfs, per #130: it is pure churn and would defeat
    # spin-down on /mnt/nas and burn write cycles on the eMMC root. 2G is sized
    # for Jellyfin's throttled segment-ahead buffer, not for a whole movie —
    # tmpfs only occupies what is actually written. If a 4K HDR transcode ever
    # ENOSPCs here, the escape hatch is the NVMe fast tier rather than a bigger
    # tmpfs on an 8 GB box: point cacheDir at /mnt/fast/jellyfin-cache and drop
    # this mount.
    fileSystems."/var/cache/jellyfin" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [
        "size=2G"
        "mode=0700"
        "uid=tom"
        "gid=users"
        "noatime"
      ];
    };

    systemd.tmpfiles.rules = [
      # 'z' not 'd', same doctrine as storage.nix: `videos` is a SUBVOLUME made
      # by the Day-2 runbook. A 'd' here would silently manufacture a plain
      # directory if that step were ever skipped, and the library would land
      # somewhere btrbk cannot snapshot.
      "z ${libraryDir} 0750 tom users -"
    ];

    systemd.services.jellyfin = {
      wantedBy = lib.mkForce [ ];
      unitConfig = {
        StopWhenUnneeded = true;
        RequiresMountsFor = [
          storageRoot
          "/var/cache/jellyfin"
        ];
      };
    };

    systemd.sockets.video-access = {
      description = "Wake NAS Jellyfin on the first client connection";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "0.0.0.0:8095";
        NoDelay = true;
      };
    };
    systemd.services.video-access = {
      description = "On-demand proxy for NAS Jellyfin";
      requires = [ "jellyfin.service" ];
      after = [ "jellyfin.service" ];
      serviceConfig = proxyHardening // {
        # /health answers 200 "Healthy" with no auth once the server is up.
        ExecStartPre = waitForHttp "Jellyfin" "http://127.0.0.1:8096/health";
        ExecStart = "${socketProxyd} --exit-idle-time=15min 127.0.0.1:8096";
      };
    };

    networking.firewall.extraInputRules = ''
      ip saddr 10.77.0.1 tcp dport 8095 accept comment "Jellyfin wake proxy from coordinator"
    '';
  };
}
