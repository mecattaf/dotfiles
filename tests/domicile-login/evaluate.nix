let
  baseline = "b330226a643e733541745c6cb8b70a80dd6ec2c6";
  root = toString ../..;
  host = (builtins.getFlake root).nixosConfigurations.client;
  current = host.config;
  before = (builtins.getFlake "git+file://${root}?rev=${baseline}").nixosConfigurations.client.config;
  sameGreetd = current.services.greetd.settings == before.services.greetd.settings;
  sameSway =
    current.systemd.user.services.sway-physical.serviceConfig
    == before.systemd.user.services.sway-physical.serviceConfig;
  # A later matched-engine package replacement is expected integration work.
  sameDomicile =
    current.programs.domicile.package.outPath == before.programs.domicile.package.outPath;
  probePackage = host.pkgs.symlinkJoin {
    name = "domicile-console-trial-package-probe";
    paths = [ current.programs.domicile.package ];
    passthru.providedSessions = current.programs.domicile.package.providedSessions;
  };
  probe =
    (host.extendModules {
      modules = [ { programs.domicile.package = probePackage; } ];
    }).config.programs.domicilePhysical;
  hasFragment =
    fragment: script:
    host.pkgs.lib.hasInfix (builtins.unsafeDiscardStringContext fragment) (
      builtins.unsafeDiscardStringContext script
    );
  overrideWiring =
    hasFragment "${probePackage}/bin/domicile" probe.sessionPackage.text
    && hasFragment "${probePackage}/bin/domicile" probe.recoveryPackage.text
    && hasFragment "${probePackage}/bin" probe.trialPackage.text;
  failed = builtins.map (x: x.message) (builtins.filter (x: !x.assertion) current.assertions);
in
assert sameGreetd && sameSway && overrideWiring && failed == [ ];
{
  baseGreetdUnchanged = sameGreetd;
  swayServiceUnchanged = sameSway;
  sameDomicilePackage = sameDomicile;
  configuredPackageOverrideWiring = overrideWiring;
  engineABI = "UNSUPPORTED: cached engine, native integration unfinished";
  failedAssertions = failed;
  baseInitialSession = current.services.greetd.settings.initial_session;
  defaultSession = current.services.greetd.settings.default_session;
  trialInitialSession =
    current.specialisation.domicile.configuration.services.greetd.settings.initial_session;
  consoleTrial = current.programs.domicilePhysical.trialPackage.outPath;
  toplevel = current.system.build.toplevel.drvPath;
}
