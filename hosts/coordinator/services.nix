{
  config,
  lib,
  pkgs,
  ...
}:
let
  socketProxyd = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd";
  waitForHttp =
    name: url:
    pkgs.writeShellScript "${name}-wait-for-http" ''
      for _ in $(${pkgs.coreutils}/bin/seq 1 90); do
        if ${pkgs.curl}/bin/curl --fail --silent --max-time 1 ${lib.escapeShellArg url} >/dev/null; then
          exit 0
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done
      echo "${name} did not become ready within 90 seconds" >&2
      exit 1
    '';
in
# The coordinator's media services — Immich (photos) and Navidrome (music) — as
# NATIVE NixOS modules. Migrated 2026-07-13 from the rootless podman quadlets
# they were ported to on 2026-07-05 (see git history for the old .container
# stack). This removes the last containers from the coordinator entirely: no
# podman network, no aardvark DNS workaround, no user lingering for quadlets,
# and updates now ride the one fleet flake-rebuild path instead of a second
# AutoUpdate=registry mechanism.
#
# LaCie access — the crux. Both libraries live on the directly-attached LaCie
# USB NAS at /mnt/nas (see uplink-nas.nix), migrated to Btrfs on 2026-07-23.
# The media subvolumes have ordinary on-disk POSIX ownership as tom:users, so
# both services continue to run as that identity during the verified restore
# and later integration. Preserve each accepted tree's existing mode.
# The native modules assume a local mediaLocation and add no mount ordering, so
# each unit gets RequiresMountsFor=/mnt/nas to fire the x-systemd.automount
# before the service (and, for navidrome, before its sandbox bind-mounts the
# music folder read-only). Moving these services to dedicated system users is a
# separate post-restore decision; it is not coupled to the filesystem anymore.
#
# No secrets: services.immich provisions its own postgresql over a unix socket
# (peer auth, database.host=/run/postgresql), so the module's assertion is
# satisfied WITHOUT a password file and the old immich-db.age secret is retired.
# services.immich also subsumes the redis + machine-learning sidecars natively.
# The navidrome-credentials secret is unrelated to the server — it is consumed
# client-side by the cliamp fish function — and is delivered in
# modules/secrets.nix (coordinator only since the zenbook-duo left the fleet,
# 2026-08-30; it was the second cliamp host).
#
# Reachability: both bind 0.0.0.0, but the firewall opens their ports ONLY on
# tailscale0 (same trust model as wayvnc:5900, whose door now sits beside this
# one in ./tailscale.nix), so they are reachable across the tailnet — e.g. Tom's
# phone — but never the raw LAN/wifi. This restores the phone access that went
# away with the retired BE550 LAN segment.
#
# WHICH tailnet, since 2026-09-01 there are two: this box's tailscale0 belongs to
# official tailscale.com, and in headscale phase 1 that is still the only path
# into the house from outside it (hosts/nas/headscale.nix is LAN-only until its
# publicEndpoint gate flips). So a roaming phone reaches these doors exactly as
# it always did. What phase 2 will need thinking about, and what is recorded here
# rather than guessed at: a phone that MOVES to the headscale tailnet reaches
# this box over the NAS's advertised 10.42.0.0/24 route, arriving on the LAN
# interface — which these tailscale0-scoped rules do not admit. That is a
# deliberate open question for the phase-2 runbook, not a bug to pre-fix here.
{
  options.myCoordinatorMedia.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Keep the pre-cutover Immich and Navidrome core on the coordinator";
  };

  config = lib.mkIf config.myCoordinatorMedia.enable {
    services.immich = {
      enable = true;
      mediaLocation = "/mnt/nas/photos";
      # The public 2283 listener is the socket-activated proxy below. Immich stays
      # private on 2284 and only runs while someone is actually using it.
      host = "127.0.0.1";
      port = 2284;
      user = "tom";
      group = "users";
      # The postgres it provisions is reached over a unix socket with PEER auth,
      # which maps the OS user to a same-named DB role — so the DB role must be
      # "tom" too. And the module's ensureDBOwnership couples the role name to the
      # database name, so the DB is named "tom" as well. (Immich doesn't care what
      # the database is called; it just needs to own it.) This is the price of
      # running as tom, which we must do for LaCie write access — see header.
      database.user = "tom";
      database.name = "tom";
      # ML is a separate, socket-activated coordinator service (immich-ml.nix),
      # so it survives the later core-service cutover to the NAS.
      machine-learning.enable = false;
    };
    # Originals remain on LaCie under mediaLocation. Generated/rebuildable Immich
    # state stays on the internal disk and is overlaid onto Immich's expected
    # mediaLocation paths inside the service mount namespace. This avoids filling
    # the archive disk with thumbnails/transcodes while keeping upstream's fixed
    # directory layout intact.
    systemd.tmpfiles.rules = [
      "d /var/lib/immich/generated 0700 tom users -"
      "d /var/lib/immich/generated/thumbs 0700 tom users -"
      "d /var/lib/immich/generated/encoded-video 0700 tom users -"
      "d /var/lib/immich/generated/profile 0700 tom users -"
      "d /var/lib/immich/generated/backups 0700 tom users -"
    ];
    # The LaCie is an x-systemd.automount; pull the real mount in before the server
    # touches mediaLocation (uses the .automount, so the drive still spins down).
    systemd.services.immich-server = {
      # The proxy is the only long-lived entry point. The three Immich workers are
      # deliberately absent from multi-user.target and stop when the proxy has
      # seen no connections for 15 minutes. This releases Node's post-job heap and
      # lets the LaCie return to standby instead of keeping a rarely-used gallery
      # resident around the clock.
      wantedBy = lib.mkForce [ ];
      requires = [ "redis-immich.service" ];
      after = [ "redis-immich.service" ];
      environment.CPU_CORES = "4";
      unitConfig.StopWhenUnneeded = true;
      unitConfig.RequiresMountsFor = [ "/mnt/nas" ];
      serviceConfig.BindPaths = [
        "/var/lib/immich/generated/thumbs:/mnt/nas/photos/thumbs"
        "/var/lib/immich/generated/encoded-video:/mnt/nas/photos/encoded-video"
        "/var/lib/immich/generated/profile:/mnt/nas/photos/profile"
        "/var/lib/immich/generated/backups:/mnt/nas/photos/backups"
      ];
    };
    systemd.services.redis-immich = {
      wantedBy = lib.mkForce [ ];
      unitConfig.StopWhenUnneeded = true;
    };

    systemd.sockets.immich-access = {
      description = "Wake Immich on the first client connection";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "0.0.0.0:2283";
        NoDelay = true;
      };
    };
    systemd.services.immich-access = {
      description = "On-demand proxy for Immich";
      requires = [ "immich-server.service" ];
      after = [ "immich-server.service" ];
      serviceConfig = {
        ExecStartPre = waitForHttp "Immich" "http://127.0.0.1:2284/api/server/ping";
        ExecStart = "${socketProxyd} --exit-idle-time=15min 127.0.0.1:2284";
        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        TimeoutStartSec = "2min";
      };
    };

    services.navidrome = {
      enable = true;
      user = "tom";
      group = "users";
      settings = {
        MusicFolder = "/mnt/nas/music";
        # As with Immich, the stable public port belongs to the on-demand proxy.
        Address = "127.0.0.1";
        Port = 4534;
        # @daily, not hourly: an hourly rescan walks /music and wakes the LaCie
        # from standby (hd-idle parks it after 20 min — see uplink-nas.nix),
        # defeating the power-down suite. New media appears after the nightly scan
        # or a manual "Scan" in the UI.
        ScanSchedule = "@daily";
        LogLevel = "info";
        # 0.62.0+ rejects unit-less durations ("missing unit in duration").
        SessionTimeout = "168h";
        AutoImportPlaylists = true;
      };
    };
    systemd.services.navidrome = {
      wantedBy = lib.mkForce [ ];
      unitConfig = {
        RequiresMountsFor = [ "/mnt/nas" ];
        StopWhenUnneeded = true;
      };
    };

    systemd.sockets.navidrome-access = {
      description = "Wake Navidrome on the first client connection";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "0.0.0.0:4533";
        NoDelay = true;
      };
    };
    systemd.services.navidrome-access = {
      description = "On-demand proxy for Navidrome";
      requires = [ "navidrome.service" ];
      after = [ "navidrome.service" ];
      serviceConfig = {
        ExecStartPre = waitForHttp "Navidrome" "http://127.0.0.1:4534/";
        ExecStart = "${socketProxyd} --exit-idle-time=15min 127.0.0.1:4534";
        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        TimeoutStartSec = "2min";
      };
    };

    # The two service front doors are reachable across the tailnet only.
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
      2283
      4533
    ];

    # navidrome-credentials delivery moved to modules/secrets.nix (2026-07-13):
    # it's NOT consumed by the navidrome server here — only read client-side by
    # the cliamp fish function. It moved there when cliamp gained a second host
    # (zenbook-duo, retired 2026-08-30) and a single host-agnostic block beat
    # duplicating the delivery; it stays there now that the coordinator is the
    # only recipient again, because that is where secret delivery belongs.
  };
}
