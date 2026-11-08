{
  pkgs,
  domicile,
  imagineSource,
  source,
  sdkSource,
}:
assert builtins.isString sdkSource && builtins.match "[a-f0-9]{40}" sdkSource != null;
let
  payload = pkgs.runCommand "dsh-domicile-client-payload" { } ''
    mkdir -p "$out"
    cp ${source}/client_helper.py "$out/client_helper.py"
    cp ${source}/protocol.py "$out/protocol.py"
  '';
  package = pkgs.writeShellScriptBin "dsh-domicile-client" ''
    exec ${pkgs.python3}/bin/python3 ${payload}/client_helper.py "$@"
  '';
  clientConfig = pkgs.writeText "dsh-domicile-client.json" (
    builtins.toJSON {
      desktopId = "zenbook";
      # Existing client UID, verified on the device; not an Imagine default.
      runtimeDirectory = "/run/user/1001";
      domicileBinary = "${domicile}/bin/domicile";
      imagineSource = toString imagineSource;
      inherit sdkSource;
      replyRoot = ".local/state/dsh-domicile/replies";
    }
  );
  stage = pkgs.writeShellScript "stage-imagine-snapshot-config" ''
    set -euo pipefail
    umask 077
    configDirectory="$1"
    mkdir -p "$configDirectory"
    chmod 0700 "$configDirectory"
    stagedConfig=$(mktemp "$configDirectory/.client.json.XXXXXX")
    trap 'rm -f -- "$stagedConfig"' EXIT
    install -m 0600 ${clientConfig} "$stagedConfig"
    mv -Tf -- "$stagedConfig" "$configDirectory/client.json"
    trap - EXIT
  '';
in
{
  inherit
    package
    stage
    clientConfig
    payload
    ;
}
