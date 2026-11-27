{ writeShellApplication, python3 }:
writeShellApplication {
  name = "ps4-host-check";
  runtimeInputs = [ python3 ];
  text = ''exec python3 ${./check.py} "$@"'';
}
