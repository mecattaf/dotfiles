{ pkgs, ... }:
let
  mount = device: {
    inherit device;
    fsType = "nfs4";
    options = [
      "ro"
      "noatime"
      "soft"
      "timeo=30"
      "retrans=3"
      "nofail"
      "_netdev"
      "x-systemd.automount"
      "x-systemd.idle-timeout=10min"
      "x-systemd.mount-timeout=30s"
      "x-systemd.requires=library-reachable.service"
    ];
  };
in
{
  # Read-only model and document views, adapted from the former worker. Media
  # relays and the historical coordinator /mnt/nas mount are host exceptions.
  boot.supportedFilesystems = [ "nfs" ];
  fileSystems."/mnt/library" = mount "nas:/models";
  services.local-models.libraryPath = "/mnt/library/weights";
  systemd.services.library-reachable = {
    description = "Wait for the NAS Library export before mounting it";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "3min";
      ExecStart = pkgs.writeShellScript "wait-library-reachable" ''
        for _ in $(${pkgs.coreutils}/bin/seq 120); do
          if ${pkgs.bash}/bin/bash -c 'exec 3<>/dev/tcp/nas/2049' 2>/dev/null; then
            exit 0
          fi
          ${pkgs.coreutils}/bin/sleep 1
        done
        echo "nas:2049 unreachable after 120s; letting mount.nfs4 try anyway" >&2
      '';
    };
  };
}
