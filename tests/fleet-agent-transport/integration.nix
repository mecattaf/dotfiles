# Inspect actual combined production configurations. No module, kernel,
# filesystem or transport overrides are applied by this helper.
{ flake }:
let
  configs = flake.nixosConfigurations;
  configFacts =
    name: host:
    let
      c = host.config;
    in
    {
      kernel = c.boot.kernelPackages.kernel.version;
      tailscale = c.services.tailscale.enable;
      tailscaleFlags = c.services.tailscale.extraSetFlags;
      failures = map (a: a.message) (builtins.filter (a: !a.assertion) c.assertions);
      drvPath = c.system.build.toplevel.drvPath;
    }
    // flake.inputs.nixpkgs.lib.optionalAttrs (name == "nas") {
      localBuildJobs = c.nix.settings.max-jobs;
      builders = map (b: b.hostName) c.nix.buildMachines;
      dsh = c.home-manager.users.tom.programs.dsh.enable;
      inference = c.services.utilityModel.endpoint;
      herdrKeepOld = c.home-manager.users.tom.systemd.user.services.herdr.Unit.X-SwitchMethod;
      herdrOOM = c.home-manager.users.tom.systemd.user.services.herdr.Service.OOMPolicy;
      substratePuller = c.systemd.user.services ? substrate-puller;
    };
in
{
  facts = {
    productionConfigurations = true;
    integrationRev = flake.rev or "dirty";
    hosts = builtins.mapAttrs configFacts configs;
  };
  check = flake.checks.x86_64-linux.fleet-agent-transport;
}
