{ writeShellApplication, python3, bun, google-chrome }:
writeShellApplication {
  name = "chrome-stream";
  runtimeInputs = [ python3 bun google-chrome ];
  text = ''
    exec python3 ${./launch.py} --assets ${./.} "$@"
  '';
}
