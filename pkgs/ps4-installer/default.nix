{
  writeShellApplication,
  python3,
  util-linux,
}:
writeShellApplication {
  name = "ps4-usb";
  runtimeInputs = [
    python3
    util-linux
  ];
  text = ''
    exec python3 ${./ps4_usb.py} "$@"
  '';
}
