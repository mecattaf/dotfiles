# Build proof only. NEVER activate the NAS fixture: its PARTUUID is invented.
# Production NAS configuration and its PARTUUID assertion remain untouched.
{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  testUuid = "11111111-2222-4333-8444-555555555555";
  configs = flake.nixosConfigurations // {
    nas = flake.nixosConfigurations.nas.extendModules {
      modules = [ { myNas.homeDisk.partUuid = lib.mkForce testUuid; } ];
    };
  };
  kernels = builtins.mapAttrs (_: host: host.config.boot.kernelPackages.kernel) configs;
  selected = kernels.strix-coordinator;
  rdma = host: configs.${host}.config.hardware.thunderbolt-ibverbs.resolvedPackage;
in
assert lib.all (k: k.version == selected.version && k.drvPath == selected.drvPath) (
  builtins.attrValues kernels
);
assert (rdma "strix-coordinator").drvPath == (rdma "strix-worker").drvPath;
assert (rdma "strix-coordinator").kernelVersion == selected.version;
{
  hosts = builtins.mapAttrs (_: host: host.config.system.build.toplevel) configs;
  facts = {
    inherit testUuid;
    hosts = builtins.mapAttrs (name: host: {
      kernel = kernels.${name}.version;
      kernelDrv = kernels.${name}.drvPath;
      toplevelDrv = host.config.system.build.toplevel.drvPath;
      testFixture = name == "nas";
    }) configs;
    donnerkeule = {
      revision = flake.inputs.donnerkeule.rev;
      drv = (rdma "strix-coordinator").drvPath;
      kernel = (rdma "strix-coordinator").kernelVersion;
    };
    gufoRdma = {
      revision = flake.inputs.gufo-rdma.rev;
      drv = flake.packages.x86_64-linux.gufo-rdma.drvPath;
    };
  };
}
