{ pkgs }:
pkgs.runCommand "ps4-installer-check"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    PS4_USB_SOURCE = "${../../pkgs/ps4-installer/ps4_usb.py}";
  }
  ''
    python3 ${./test_ps4_usb.py}
    touch "$out"
  ''
