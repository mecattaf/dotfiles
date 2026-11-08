# Evaluation-only fixture: execute its whole generated script with test doubles.
let
  host = (builtins.getFlake (toString ../..)).nixosConfigurations.client.extendModules {
    modules = [
      {
        environment.sessionVariables = {
          DOMICILE_LOGIN_NATIVE_PROBE = "native-from-candidate";
          DOMICILE_CONFIG_FILE = "/unselected-probe.json";
        };
        home-manager.users.tom.home.sessionVariables = {
          HOME = "/unselected-home";
          XDG_CONFIG_HOME = "/unselected-config";
        };
      }
    ];
  };
in
host.config.programs.domicilePhysical.sessionPackage.text
