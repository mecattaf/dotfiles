# Production build proof only: inspect the actual flake configurations.
# No extendModules, invented filesystem identities or transport overrides.
{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  configs = flake.nixosConfigurations;
  kernel = host: configs.${host}.config.boot.kernelPackages.kernel;
  selected = kernel "strix-coordinator";
  rdma = host: configs.${host}.config.hardware.thunderbolt-ibverbs.resolvedPackage;
  nas = configs.nas.config;
  registry = import ../../modules/mesh-registry.nix;
  configFacts =
    name: host:
    let
      c = host.config;
    in
    {
      kernel = (kernel name).version;
      kernelDrv = (kernel name).drvPath;
      toplevelDrv = c.system.build.toplevel.drvPath;
      roles = c.myFleet.roles;
      tailscale = c.services.tailscale.enable;
      tailscaleFlags = c.services.tailscale.extraSetFlags;
      tailscaleAuthKeyDelivered = c.services.tailscale.authKeyFile != null;
      rawDotfilesInStore = c.home-manager.users.tom.rawDotfiles.inStore;
      gufo = c.services.gufo.enable or false;
      gufoBootTargets = c.systemd.services.gufo-llm.wantedBy or [ ];
      tp2 = c.services.gufo.tp2.enable or false;
      tp2BootTargets = c.systemd.services.gufo-tp2.wantedBy or [ ];
    };
in
assert lib.versions.majorMinor selected.version == "7.3";
assert builtins.all (
  name: (kernel name).version == selected.version && (kernel name).drvPath == selected.drvPath
) (builtins.attrNames configs);
assert (rdma "strix-coordinator").drvPath == (rdma "strix-worker").drvPath;
assert (rdma "strix-coordinator").kernelVersion == selected.version;
assert !(configs.nas.options.myNas.homeDisk ? partUuid);
assert nas.myNas.homeDisk.layout == "shared-btrfs";
assert nas.fileSystems."/home".device == "${nas.myNas.homeDisk.device}-part1";
assert nas.fileSystems."/mnt/fast".device == nas.fileSystems."/home".device;
assert builtins.elem "subvol=@fast" nas.fileSystems."/mnt/fast".options;
{
  hosts = builtins.mapAttrs (_: host: host.config.system.build.toplevel) configs;
  facts = {
    productionConfigurations = true;
    configurationOverrides = [ ];
    hosts = builtins.mapAttrs configFacts configs;
    nas = {
      homeDevice = nas.fileSystems."/home".device;
      homeOptions = nas.fileSystems."/home".options;
      homeRequiredByUserManager = nas.systemd.services."user@1000".unitConfig.RequiresMountsFor;
      localBuildJobs = nas.nix.settings.max-jobs;
      builders = map (b: {
        inherit (b)
          hostName
          protocol
          sshUser
          maxJobs
          ;
      }) nas.nix.buildMachines;
      inference = nas.services.utilityModel.endpoint;
      dsh = nas.home-manager.users.tom.programs.dsh.enable;
      herdrSwitchMethod = nas.home-manager.users.tom.systemd.user.services.herdr.Unit.X-SwitchMethod;
    };
    donnerkeule = {
      revision = flake.inputs.donnerkeule.rev;
      drv = (rdma "strix-coordinator").drvPath;
      kernel = (rdma "strix-coordinator").kernelVersion;
    };
    gufoRdma = {
      revision = flake.inputs.gufo-rdma.rev;
      drv = flake.packages.x86_64-linux.gufo-rdma.drvPath;
      cpuDmaLatencyUs = configs.strix-coordinator.config.services.gufo.tp2.cpuDmaLatencyUs;
    };
    readiness = {
      workerHostKeyRecorded = registry.strix-worker.hostKey != "";
      tp2TokenCiphertextPresent = builtins.pathExists ../../secrets/gufo-tp2-control-token.age;
      legacyUsb4NetworkBlacklisted = builtins.elem "thunderbolt_net" configs.strix-coordinator.config.boot.blacklistedKernelModules;
      legacyUsb4StreamBlacklisted = builtins.elem "thunderbolt_stream" configs.strix-coordinator.config.boot.blacklistedKernelModules;
    };
  };
}
