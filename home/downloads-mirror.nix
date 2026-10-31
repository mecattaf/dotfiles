{ lib, osConfig, pkgs, ... }:
{
  # Pin the interpreter and both transport executables. Activation and user
  # services do not inherit an interactive shell's PATH.
  home.packages = lib.optionals (osConfig.myFleet.has "brain" || osConfig.myFleet.has "seat") [
    pkgs.downloads-mirror
    pkgs.rsync
  ];

  # A browser's final rename raises an event; this is a reactive producer, not
  # a second clock. Concrete paths come from the host's XDG file at activation.
  home.activation.downloadsMirrorWatch = lib.mkIf (osConfig.myFleet.has "seat") (
    lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "linkGeneration" ] ''
      run ${lib.getExe pkgs.downloads-mirror} --prepare-watch
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
      ExecStart = "${lib.getExe pkgs.downloads-mirror} --notify";
      TimeoutStartSec = 40;
      UMask = "0077";
    };
  };
}
