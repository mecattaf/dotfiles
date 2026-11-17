{ pkgs, ... }:
# Connected-device battery reader for Imagine's F9 menu. Discovery reads whichever
# AirPods are connected, not a configured address. No daemon, timer, Bluetooth
# restart or change to existing keyboard/trackpad pairing is needed.
{
  services.pipewire.wireplumber.extraConfig."52-airpods-call-profile" = {
    "wireplumber.settings"."bluetooth.autoswitch-to-headset-profile" = true;
  };
  environment.systemPackages = [ (pkgs.callPackage ../../pkgs/podpower { }) ];
}
