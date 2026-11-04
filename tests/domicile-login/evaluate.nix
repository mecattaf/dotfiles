let
  baseline = "efa52f55eb3052106cc8b808e762e503b46a606d";
  root = toString ../..;
  current = (builtins.getFlake root).nixosConfigurations.client.config;
  before = (builtins.getFlake "git+file://${root}?rev=${baseline}").nixosConfigurations.client.config;
  sameGreetd = current.services.greetd.settings == before.services.greetd.settings;
  sameSway =
    current.systemd.user.services.sway-physical.serviceConfig
    == before.systemd.user.services.sway-physical.serviceConfig;
  sameDomicile =
    current.programs.domicile.package.outPath == before.programs.domicile.package.outPath;
  failed = builtins.map (x: x.message) (builtins.filter (x: !x.assertion) current.assertions);
in
assert sameGreetd && sameSway && sameDomicile && failed == [ ];
{
  baseGreetdUnchanged = sameGreetd;
  swayServiceUnchanged = sameSway;
  sameDomicilePackage = sameDomicile;
  failedAssertions = failed;
  baseInitialSession = current.services.greetd.settings.initial_session;
  defaultSession = current.services.greetd.settings.default_session;
  trialInitialSession =
    current.specialisation.domicile.configuration.services.greetd.settings.initial_session;
  toplevel = current.system.build.toplevel.drvPath;
}
