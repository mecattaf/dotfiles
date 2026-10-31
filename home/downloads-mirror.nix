{ config, lib, osConfig, pkgs, ... }:
{
  # The small helper is available on both ends through the raw-dotfiles bin
  # link. Substrate invokes it on the brain; no timer or background loop lives
  # here. The source's SSH server provides its ordinary rsync binary.
  home.packages = lib.optionals (osConfig.myFleet.has "brain" || osConfig.myFleet.has "seat") [
    pkgs.rsync
  ];

  # A browser's final rename raises an event; this is a reactive producer, not
  # a second clock. Concrete paths come from the host's XDG file at activation.
  home.activation.downloadsMirrorWatch = lib.mkIf (osConfig.myFleet.has "seat") (
    lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "linkGeneration" ] ''
      run ${config.home.homeDirectory}/.local/bin/downloads-mirror --prepare-watch
    ''
  );
  systemd.user.paths.downloads-mirror-watch = lib.mkIf (osConfig.myFleet.has "seat") {
    Unit.Description = "Notify the download receiver when browser downloads change";
    Path.Unit = "downloads-mirror-notify.service";
    Install.WantedBy = [ "default.target" ];
  };
  systemd.user.services.downloads-mirror-notify = lib.mkIf (osConfig.myFleet.has "seat") {
    Unit = {
      Description = "Request an event-driven download copy on the agent host";
      StartLimitIntervalSec = 0;
    };
    Service = {
      Type = "oneshot";
      ExecStart = "%h/.local/bin/downloads-mirror --notify";
      TimeoutStartSec = 40;
      UMask = "0077";
    };
  };
}
