{
  pkgs,
  lib,
  self,
  inputs,
}:
let
  c = self.nixosConfigurations.strix-coordinator.config;
  w = self.nixosConfigurations.strix-worker.config;
  moduleOf = host: host.hardware.thunderbolt-ibverbs.resolvedPackage;
  unitOf = host: host.systemd.services.gufo-tp2;
  sameRanks =
    lib.all
      (
        host:
        let
          rdma = host.hardware.thunderbolt-ibverbs;
          tp = host.services.gufo.tp2;
        in
        rdma.enable
        && !rdma.kernel.useProjectKernel
        && rdma.blacklist.enable
        && builtins.elem "thunderbolt_net" host.boot.blacklistedKernelModules
        && builtins.elem "thunderbolt_stream" host.boot.blacklistedKernelModules
        && !(builtins.elem "thunderbolt_net" host.boot.kernelModules)
        && !(builtins.elem "thunderbolt_stream" host.boot.kernelModules)
        && rdma.check.minReadyRails == 4
        && rdma.check.expectedRailSpeed == "20Gb/s"
        && lib.all (name: !(lib.hasPrefix "dmabuf_" name)) (builtins.attrNames rdma.config)
        # Phase A four rails: the five path options (driver default off) on
        # both controllers. Without them the driver forms zero rails.
        && lib.all (name: (rdma.config.${name} or false) == true) [
          "bind_services"
          "allocate_rings"
          "start_rings"
          "negotiate_native"
          "enable_tunnels"
        ]
        && (rdma.config.native_domain_mask or null) == 3
        && (moduleOf host).kernelVersion == host.boot.kernelPackages.kernel.version
        && (moduleOf host).donnerkeuleRevision == inputs.donnerkeule.rev
        && rdma.userspaceTools.package == self.packages.x86_64-linux.rdmaCoreUsb4
        && tp.package == self.packages.x86_64-linux.gufo-rdma
        && host.services.gufo.package == inputs.gufo.packages.x86_64-linux.default
        && (unitOf host).wantedBy == [ ]
        && (unitOf host).serviceConfig.Restart == "always"
        && tp.cpuDmaLatencyUs == 100
        && builtins.elem "gufo-tp2-latency.service" (unitOf host).requires
        && builtins.elem "gufo-tp2-latency.service" (unitOf host).after
        && host.systemd.services.gufo-tp2-latency.wantedBy == [ ]
        && host.systemd.services.gufo-tp2-latency.partOf == [ "gufo-tp2.service" ]
        && host.systemd.services.gufo-tp2-latency.unitConfig.StopWhenUnneeded
        && !(host.systemd.services ? usb4-stream-provision)
        && !(host.systemd.services ? fn-rdma-modules)
        && builtins.elem "thunderbolt-ibverbs-check.service" (unitOf host).after
        && builtins.elem "thunderbolt-ibverbs-check.service" (unitOf host).wants
        && builtins.elem "gufo-tp2.service" host.systemd.services.gufo-llm.conflicts
        && host.networking.nftables.enable
        && host.services.gufo.lanInterface == "enp191s0"
        && lib.hasInfix ''iifname "enp191s0" ip saddr ${tp.peerAddress} tcp dport { 18515, 18516 } accept'' host.networking.firewall.extraInputRules
        && !(builtins.elem 18515 host.networking.firewall.allowedTCPPorts)
        && !(builtins.elem 18516 host.networking.firewall.allowedTCPPorts)
      )
      [
        c
        w
      ];
  acl = (import ../../secrets.nix)."secrets/gufo-tp2-control-token.age".publicKeys;
  registry = import ../../modules/mesh-registry.nix;
in
assert c.boot.kernelPackages.kernel.version == w.boot.kernelPackages.kernel.version;
assert lib.versions.majorMinor c.boot.kernelPackages.kernel.version == "7.3";
assert (moduleOf c).donnerkeuleRevision == (moduleOf w).donnerkeuleRevision;
assert (moduleOf c).drvPath == (moduleOf w).drvPath;
assert self.packages.x86_64-linux.rdmaCoreUsb4.donnerkeuleRevision == inputs.donnerkeule.rev;
assert sameRanks;
# Both ranks load the identical module option string.
assert
  c.hardware.thunderbolt-ibverbs.renderedModuleOptions
  == w.hardware.thunderbolt-ibverbs.renderedModuleOptions;
assert c.services.gufo.tp2.rank == 0 && w.services.gufo.tp2.rank == 1;
assert
  c.services.gufo.tp2.peerAddress == "10.42.0.5" && w.services.gufo.tp2.peerAddress == "10.42.0.2";
assert c.services.gufo.tp2.modelName == w.services.gufo.tp2.modelName;
assert c.services.gufo.llm == w.services.gufo.llm;
assert (unitOf c).serviceConfig ? ExecStartPost;
assert !((unitOf w).serviceConfig ? ExecStartPost);
assert c.networking.networkmanager.ensureProfiles.profiles.tbv0.ipv4.address1 == "10.99.0.1/30";
assert w.networking.networkmanager.ensureProfiles.profiles.tbv0.ipv4.address1 == "10.99.0.2/30";
assert builtins.elem registry.strix-coordinator.hostKey acl;
assert registry.strix-worker.hostKey == "" || builtins.elem registry.strix-worker.hostKey acl;
assert !(builtins.elem "" acl);
assert !(builtins.elem registry.client.hostKey acl) && !(builtins.elem registry.nas.hostKey acl);
pkgs.runCommand "gufo-rdma-policy" { } ''
  ${pkgs.shellcheck}/bin/shellcheck ${(unitOf c).serviceConfig.ExecStart} ${(unitOf w).serviceConfig.ExecStart} \
    ${builtins.elemAt (unitOf c).serviceConfig.ExecStartPre 1} \
    ${c.systemd.services.gufo-tp2-latency.serviceConfig.ExecStart}
  ${pkgs.python3}/bin/python3 ${./test_latency_hold.py} \
    ${c.systemd.services.gufo-tp2-latency.serviceConfig.ExecStart} ${pkgs.bash}/bin/bash
  touch "$out"
''
