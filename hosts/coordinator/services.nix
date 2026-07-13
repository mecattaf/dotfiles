{ config, lib, ... }:
# The coordinator's containerised services, as ROOTLESS podman quadlets
# (ported 2026-07-05 from tom's live ~/.config/containers/systemd on harness).
#
# Delivery: /etc/containers/systemd/users/1000/ — podman's system-wide user
# quadlet dir — instead of home/dot_config, so the stack stays coordinator-only
# (home-manager's config tree deploys to EVERY host). tom lingers, so
# default.target units start at boot without a login.
#
#   auto-started — immich (+pg/redis/ml), navidrome.
#   (twenty / openwebui / cloudflare-tunnel: DEPRECATED per Tom 2026-07-05,
#   deliberately not ported. adguard: RETIRED with the BE550 router 2026-07-13 —
#   DNS filtering is now per-box in modules/adguardhome.nix, not a LAN quadlet.)
#
# Secrets arrive via agenix (owner tom so the user manager can read them):
# /run/agenix/immich-db and /run/agenix/navidrome-credentials. The quadlet
# files and cliamp shell wrapper reference those paths, so the stack needs
# mySecrets.enable — gate everything on it.
#
# DATA: named volumes live in ~/.local/share/containers/storage/volumes and
# ALL regenerate from scratch — immich never held data (Tom, 2026-07-05); it
# starts fresh with the random DB password in immich-db.age and its photo
# library is the drive's photos folder bind (/mnt/nas/photos).
let
  quadletFiles = [
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

    # navidrome admin credentials — sourced by cliamp at launch via
    # `set -a && source /run/agenix/navidrome-credentials && set +a`.
    # Format: NAVIDROME_USER=… / NAVIDROME_PASSWORD=… (env file).
    age.secrets.navidrome-credentials = {
      file = ../../secrets/navidrome-credentials.age;
      owner = "tom";
      group = "users";
      mode = "400";
    };

    environment.etc = lib.listToAttrs (map (f: {
      name = "containers/systemd/users/1000/${f}";
      value.source = ./quadlets/${f};
    }) quadletFiles);

    # Keep aardvark-dns (rootless container DNS) off port 53. Originally forced
    # because the retired adguard quadlet published 53:53 and netavark's hostport
    # DNAT (`udp dport 53 dnat ip to <adguard>`) hijacked container DNS, killing
    # immich-server with EAI_AGAIN on immich-postgres (found 2026-07-06). AdGuard
    # is gone (2026-07-13) so the DNAT no longer exists, but moving aardvark to
    # 10053 is harmless and keeps container DNS clear of anything else on :53.
    virtualisation.containers.containersConf.settings.network.dns_bind_port = 10053;

    # Quadlet's user generator only runs for logged-in/lingering users; tom
    # lingers so adguard/immich/navidrome come up at boot, headless.
    users.users.tom.linger = true;
  };
}
