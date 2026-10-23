# Inspect the combined stack without modifying its checkout. Diagnostic mode
# supplies an INVENTED home PARTUUID and emulates removal of #608's worker
# disable. Its NAS build fixture must NEVER be installed, booted or activated.
{
  flake,
  kernelPackages ? null,
  diagnostic ? false,
}:
let
  inherit (flake.inputs.nixpkgs) lib;
  configs = builtins.mapAttrs (
    name: host:
    host.extendModules {
      modules = [
        { imports = [ ../../modules/fleet-transport.nix ]; }
      ]
      ++ lib.optional (name == "nas") { imports = [ ../../modules/agent-offload.nix ]; }
      ++ lib.optional (kernelPackages != null) { boot.kernelPackages = lib.mkForce kernelPackages; }
      ++ lib.optionals diagnostic [
        (lib.optionalAttrs (name == "strix-worker") {
          services.tailscale.enable = lib.mkOverride 40 true;
        })
        (lib.optionalAttrs (name == "nas") {
          myNas.homeDisk.partUuid = lib.mkForce "11111111-2222-4333-8444-555555555555";
        })
      ];
    }
  ) flake.nixosConfigurations;
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
    }
    // lib.optionalAttrs diagnostic {
      drvPath = c.system.build.toplevel.drvPath;
    }
    // lib.optionalAttrs (name == "nas") {
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
    inherit diagnostic;
    integrationRev = flake.rev or "dirty";
    hosts = builtins.mapAttrs configFacts configs;
  };
  check = import ./. {
    pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
    inherit lib;
    self = flake // {
      nixosConfigurations = configs;
    };
  };
  nasBuildFixture =
    assert diagnostic;
    configs.nas.config.system.build.toplevel;
}
