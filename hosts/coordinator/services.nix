{ config, lib, ... }:
# The coordinator's media services — Immich (photos) and Navidrome (music) — as
# NATIVE NixOS modules. Migrated 2026-07-13 from the rootless podman quadlets
# they were ported to on 2026-07-05 (see git history for the old .container
# stack). This removes the last containers from the coordinator entirely: no
# podman network, no aardvark DNS workaround, no user lingering for quadlets,
# and updates now ride the one fleet flake-rebuild path instead of a second
# AutoUpdate=registry mechanism.
#
# LaCie access — the crux. Both libraries live on the directly-attached LaCie
# USB NAS at /mnt/nas (see uplink-nas.nix), which is ntfs3-mounted with EVERY
# file forced to uid=1000/gid=100 and the on-disk dirs at 0755 (owner-write
# only). So both services run as tom:users — uid 1000 is the only identity that
# can write the library, and it owns every file on the mount by construction.
# The native modules assume a local mediaLocation and add no mount ordering, so
# each unit gets RequiresMountsFor=/mnt/nas to fire the x-systemd.automount
# before the service (and, for navidrome, before its sandbox bind-mounts the
# music folder read-only). A future ext4 reformat of the LaCie (parked GH issue)
# would restore normal POSIX ownership and let these move to dedicated system
# users — revisit user/group then.
#
# No secrets: services.immich provisions its own postgresql over a unix socket
# (peer auth, database.host=/run/postgresql), so the module's assertion is
# satisfied WITHOUT a password file and the old immich-db.age secret is retired.
# services.immich also subsumes the redis + machine-learning sidecars natively.
# The navidrome-credentials secret is unrelated to the server — it is consumed
# client-side by the cliamp fish function — and is delivered in
# modules/secrets.nix (coordinator + zenbook-duo both run cliamp).
#
# Reachability: both bind 0.0.0.0, but the firewall opens their ports ONLY on
# tailscale0 (same trust model as wayvnc:5900), so they are reachable across the
# tailnet — e.g. Tom's phone — but never the raw LAN/wifi. This restores the
# phone access that went away with the retired BE550 LAN segment.
{
  services.immich = {
    enable = true;
    mediaLocation = "/mnt/nas/photos";
    host = "0.0.0.0"; # tailnet-reachable; firewall below scopes it to tailscale0
    port = 2283;
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
    # machine-learning stays enabled (module default) for face/object search.
  };
  # The LaCie is an x-systemd.automount; pull the real mount in before the server
  # touches mediaLocation (uses the .automount, so the drive still spins down).
  systemd.services.immich-server.unitConfig.RequiresMountsFor = [ "/mnt/nas" ];

  services.navidrome = {
    enable = true;
    user = "tom";
    group = "users";
    settings = {
      MusicFolder = "/mnt/nas/music";
      Address = "0.0.0.0"; # tailnet-reachable; scoped to tailscale0 by firewall
      Port = 4533;
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
  systemd.services.navidrome.unitConfig.RequiresMountsFor = [ "/mnt/nas" ];

  # atuin — self-hosted shell-history sync server, same tailnet-only posture as
  # Immich/Navidrome above (no extra app-level auth; the tailnet IS the trust
  # boundary). Postgres is auto-provisioned by the module (database.createLocally
  # defaults true). The encryption key that makes cross-device history readable
  # is fleet state, delivered via agenix — see secrets.nix + modules/secrets.nix.
  #
  # One-time enrollment per device (interactive, cannot be scripted — needs a
  # password): on THIS host, `atuin register -u <user> -e <email>` (silently
  # reuses the agenix-delivered key already at ~/.local/share/atuin/key, since
  # `register` never prompts for one). On every OTHER host, `atuin login -u
  # <user> -p <password>` and hit Enter (blank) at the key prompt — same reason.
  #
  # openRegistration stays on so enrollment above doesn't need a second rebuild
  # cycle; flip to false once every device is registered if you'd rather close it.
  #
  # port: NOT the atuin default (8888) — that's Jupyter's well-known default too
  # and gets scanned/guessed reflexively; picked something off the beaten path
  # instead, tailnet-only exposure or not.
  services.atuin = {
    enable = true;
    host = "0.0.0.0"; # tailnet-reachable; firewall below scopes it to tailscale0
    port = 27321;
    openRegistration = true;
  };

  # Immich (2283) + Navidrome (4533) + atuin (27321) reachable across the
  # tailnet ONLY. Merges with the tailscale0 ports declared in default.nix (asr)
  # and common.nix (vnc).
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
    2283
    4533
    27321
  ];

  # navidrome-credentials delivery moved to modules/secrets.nix (2026-07-13):
  # it's NOT consumed by the navidrome server here — only read client-side by
  # the cliamp fish function — and cliamp now also runs from zenbook-duo, so a
  # single host-agnostic block covers both recipients instead of duplicating it.
}
