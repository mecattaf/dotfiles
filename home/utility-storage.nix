{ config, lib, osConfig, pkgs, ... }:
let isBrain = osConfig.myFleet.has "brain";
in {
  home.packages = [ pkgs.utility-storage ];
  # Concrete host paths belong in the private local config, outside the repo.
  home.activation.utilityStorage = lib.mkIf isBrain (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.utility-storage}/bin/utility-path --prepare --watch paper --watch speech
  '');
  systemd.user.paths.speech-queue = lib.mkIf isBrain {
    Unit.Description = "Watch configured speech intake";
    Path = { PathChanged = "%h/.local/share/utility-data/speech/intake"; MakeDirectory = true; DirectoryMode = "0700"; Unit = "speech-queue.service"; };
    Install.WantedBy = [ "paths.target" ];
  };
  systemd.user.services.speech-queue = lib.mkIf isBrain {
    Unit = { Description = "Render queued speech on compute and play on the originating seat"; X-RestartIfChanged = false; };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.speech-session}/bin/speech-queue --qwen ${pkgs.qwen-speech}/bin/qwen-speech --player speech-play";
      TimeoutStartSec = "infinity";
      UMask = "0077";
    };
  };
  systemd.user.timers.speech-queue = lib.mkIf isBrain {
    Unit.Description = "Release speech held during quiet hours";
    Timer = { OnCalendar = "*-*-* 06:05:00"; Persistent = true; };
    Install.WantedBy = [ "timers.target" ];
  };
}
