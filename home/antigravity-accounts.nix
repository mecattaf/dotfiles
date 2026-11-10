{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  unwrapped = pkgs.llm-agents.antigravity-cli;
  launcher = pkgs.writeShellApplication {
    name = "agy";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      AGY_EXECUTABLE=${lib.escapeShellArg "${unwrapped}/bin/agy"}
    ''
    + builtins.readFile ./antigravity-accounts.sh;
  };
  accounts = pkgs.symlinkJoin {
    name = "antigravity-cli-accounts";
    paths = [ launcher ];
    postBuild = ''
      ln -s agy "$out/bin/agy2"
      ln -s agy "$out/bin/agy3"
    '';
    passthru = { inherit unwrapped; };
  };
in
lib.mkIf (osConfig.myFleet.has "brain") {
  # Only wrapped commands reach PATH; the raw binary would crash on the NAS's
  # known-bad RDRAND implementation and would share the vendor's default login.
  home.packages = [ accounts ];
}
