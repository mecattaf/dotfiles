{ pkgs, ... }:
# On-demand BLE battery reader for Imagine's F9 menu. Discovery reads whichever
# AirPods are connected, not a configured address. No daemon, timer, Bluetooth
# restart or change to existing keyboard/trackpad pairing is needed.
{
  environment.systemPackages = [ (pkgs.callPackage ../../pkgs/podpower { }) ];
}
