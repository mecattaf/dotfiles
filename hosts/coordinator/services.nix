{ config, lib, ... }:
# The coordinator's containerised services, as ROOTLESS podman quadlets
# (ported 2026-07-05 from tom's live ~/.config/containers/systemd on harness).
#
# Delivery: /etc/containers/systemd/users/1000/ — podman's system-wide user
# quadlet dir — instead of home/dot_config, so the stack stays coordinator-only
# (home-manager's config tree deploys to EVERY host). tom lingers, so
# default.target units start at boot without a login.
#
#   auto-started — adguard (LAN DNS), immich (+pg/redis/ml), navidrome.
#   (twenty / openwebui / cloudflare-tunnel: DEPRECATED per Tom 2026-07-05,
#   deliberately not ported.)
#
# Secrets arrive via agenix (owner tom so the user manager can read them):
# /run/agenix/immich-db. The quadlet files reference that path, so the stack
# needs mySecrets.enable — gate everything on it.
#
# DATA: named volumes live in ~/.local/share/containers/storage/volumes and
# ALL regenerate from scratch — immich never held data (Tom, 2026-07-05); it
# starts fresh with the random DB password in immich-db.age and its photo
# library is the drive's Pictures folder bind (/mnt/nas/Pictures).
let
  quadletFiles = [
    "adguard.container"
    "adguard.network"
    "adguard-config.volume"
    "adguard-work.volume"
    "adguard-logs.volume"
    "immich.network"
    "immich-server.container"
    "immich-postgres.container"
    "immich-redis.container"
    "immich-ml.container"
    "navidrome.container"
  ];
in
{
  config = lib.mkIf config.mySecrets.enable {
    age.secrets.immich-db = {
      file = ../../secrets/immich-db.age;
      owner = "tom";
      group = "users";
      mode = "400";
    };

    environment.etc = lib.listToAttrs (map (f: {
      name = "containers/systemd/users/1000/${f}";
      value.source = ./quadlets/${f};
    }) quadletFiles);

    # Quadlet's user generator only runs for logged-in/lingering users; tom
    # lingers so adguard/immich/navidrome come up at boot, headless.
    users.users.tom.linger = true;
  };
}
