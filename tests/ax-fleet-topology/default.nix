{
  pkgs,
  lib,
  self,
}:
# checks.x86_64-linux.ax-fleet-topology (DESIGN.md 12.3): evaluation-only
# assertions over the REAL host configurations. Every assert is eval-time and
# sits in front of the runCommand, so each runs under --no-build.
#
# Not asserted here, on purpose: "no 8731 on the coordinator's wlp192s0". That
# is #461's change; nas-topology already asserts exactly it and fails on
# origin/main until #461 is merged (inherited, not introduced). Duplicating it
# here would make this check red for a reason outside this PR.
let
  hostCfg = host: self.nixosConfigurations.${host}.config;
  offCfg =
    host:
    (self.nixosConfigurations.${host}.extendModules {
      modules = [ { myAxFleet.enable = lib.mkForce false; } ];
    }).config;

  flagsOf =
    cfg:
    let
      raw = cfg.systemd.services.k3s.serviceConfig.ExecStart;
      s = if builtins.isList raw then lib.concatStringsSep " " raw else raw;
    in
    lib.filter (w: w != "" && w != "\\") (lib.splitString " " (lib.replaceStrings [ "\n" ] [ " " ] s));

  has = cfg: flag: builtins.elem flag (flagsOf cfg);
  hasPrefix = cfg: p: builtins.any (lib.hasPrefix p) (flagsOf cfg);

  nas = hostCfg "nas";
  coord = hostCfg "coordinator";
  worker = hostCfg "worker";
  client = hostCfg "client";
  ax = cfg: cfg.myAxFleet;

  axLines = text: lib.filter (l: lib.hasInfix "ax-fleet:" l) (lib.splitString "\n" text);

  # ── the kill switch: with enable = mkForce false nothing from this PR renders ──
  killed =
    host:
    let
      c = offCfg host;
      units = lib.attrNames c.systemd.services ++ lib.attrNames c.systemd.sockets;
    in
    !c.services.k3s.enable
    && !c.services.dockerRegistry.enable
    && !(builtins.any (lib.hasPrefix "ax-fleet") units)
    && !(builtins.any (lib.hasPrefix "ax-server-proxy") units)
    && !(builtins.any (m: m.where == "/var/lib/rancher") c.systemd.mounts)
    && !(c.environment.etc ? "NetworkManager/conf.d/90-ax-fleet.conf")
    && !(c.environment.etc ? "rancher/k3s/registries.yaml")
    && !(c.system.activationScripts ? ax-fleet-sysctl-snapshot)
    && !(lib.hasInfix "ax-fleet-guard" c.networking.firewall.extraCommands)
    && !(lib.hasInfix "ax-fleet:" (c.networking.firewall.extraInputRules or ""));

  # ── parity with the VM test: flags and firewall text, interfaces substituted ──
  testNodes = self.checks.x86_64-linux.ax-fleet.nodes;
  testOn = name: testNodes.${name}.specialisation.ax-on.configuration;
  # Flags that legitimately differ: the token source and the VM's kubelet
  # reservations (a VM has 8 GiB, the desk 128).
  volatile =
    f:
    f == "--token-file"
    || lib.hasSuffix "/k3s-token" f
    || lib.hasSuffix "-ax-fleet-vm-token" f
    || lib.hasInfix "reserved=" f
    || lib.hasInfix "eviction-hard=" f;
  normFlags =
    subst: cfg:
    lib.sort (a: b: a < b) (
      map (lib.replaceStrings (lib.attrNames subst) (lib.attrValues subst)) (
        lib.filter (f: !(volatile f)) (flagsOf cfg)
      )
    );
  nasSubst = {
    "enp1s0" = "eth1";
  };
  coordSubst = {
    "wlp192s0" = "eth1";
    "tailscale0" = "eth2";
  };
  guardText =
    subst: cfg:
    map (lib.replaceStrings (lib.attrNames subst) (lib.attrValues subst)) (
      lib.filter (l: lib.hasInfix "ax-fleet-guard" l || lib.hasInfix "8472" l) (
        lib.splitString "\n" cfg.networking.firewall.extraCommands
      )
    );
in
# nas: the control node
assert (ax nas).enable && (ax nas).role == "control";
assert has nas "--flannel-iface=enp1s0";
assert has nas "--node-ip=10.42.0.1";
assert has nas "--flannel-backend=vxlan";
assert !(hasPrefix nas "--node-taint");
assert has nas "--node-label=ate.dev/substrate-version=none";
assert has nas "--node-label=ax.mecattaf.dev/role=control";
assert has nas "--default-local-storage-path=/mnt/nas/services/ax-fleet/local-path";
assert !(builtins.any (lib.hasInfix "local-storage") nas.services.k3s.disable);
assert has nas "--kube-apiserver-arg=runtime-config=certificates.k8s.io/v1beta1=true";
assert has nas "--service-node-port-range=30000-30999";
assert !(hasPrefix nas "--data-dir");
assert !(hasPrefix nas "--cluster-init");
assert nas.services.k3s.containerdConfigTemplate == null;
assert nas.services.k3s.package == (ax nas).k3sPackage;
assert (ax nas).k3sPackage.version == "1.36.2+k3s1";
# every ax-fleet NAS rule is scoped to a source and to an interface, none to the tailnet
assert builtins.length (axLines nas.networking.firewall.extraInputRules) == 4;
assert builtins.all (l: lib.hasInfix "ip saddr" l && lib.hasInfix "iifname" l) (
  axLines nas.networking.firewall.extraInputRules
);
assert !(builtins.any (lib.hasInfix "tailscale0") (axLines nas.networking.firewall.extraInputRules));
assert nas.services.dockerRegistry.listenAddress == "10.42.0.1";
assert !nas.services.dockerRegistry.openFirewall;
assert lib.hasPrefix "/mnt/nas/" nas.services.dockerRegistry.storagePath;
assert builtins.all (m: lib.hasPrefix "/mnt/fast/" m.what) (
  lib.filter (m: m.where == "/var/lib/rancher" || m.where == "/var/lib/kubelet" || m.where == "/var/log/pods") nas.systemd.mounts
);
assert builtins.length (lib.filter (m: lib.hasPrefix "/mnt/fast/k3s" m.what) nas.systemd.mounts) == 3;
# the shared PostgreSQL is not touched: identical settings with the switch off
assert nas.services.postgresql.settings == (offCfg "nas").services.postgresql.settings;
assert nas.services.postgresql.authentication == (offCfg "nas").services.postgresql.authentication;

# coordinator: the harness node
assert (ax coord).enable && (ax coord).role == "harness";
assert has coord "--flannel-iface=wlp192s0";
assert has coord "--node-ip=10.42.0.2";
assert has coord "--server";
assert has coord "https://10.42.0.1:6443";
assert has coord "--node-taint=${(ax coord).harnessTaint}";
assert (ax coord).harnessTaint == "ate.dev/sandboxClass=gvisor:NoSchedule";
assert has coord "--node-label=ate.dev/substrate-version=${(ax coord).substrateVersion}";
assert (ax coord).substrateVersion == (ax nas).substrateVersion;
assert coord.services.k3s.containerdConfigTemplate == null;
assert coord.services.k3s.package == nas.services.k3s.package;
assert lib.hasInfix "ax-fleet-guard" coord.networking.firewall.extraCommands;
assert lib.hasInfix "-s 10.42.0.1 -p udp --dport 8472" coord.networking.firewall.extraCommands;
assert !(coord.networking.firewall.interfaces ? cni0);
assert coord.environment.etc ? "NetworkManager/conf.d/90-ax-fleet.conf";
# NO NetworkManager restart trigger: NetworkManager.conf renders byte-identical with the switch off
assert
  coord.environment.etc."NetworkManager/NetworkManager.conf".source
  == (offCfg "coordinator").environment.etc."NetworkManager/NetworkManager.conf".source;
assert coord.networking.networkmanager.unmanaged == (offCfg "coordinator").networking.networkmanager.unmanaged;
assert coord.boot.kernel.sysctl."net.ipv4.conf.default.proxy_arp" == 1;
assert !(coord.boot.kernel.sysctl ? "net.ipv4.conf.all.proxy_arp") || coord.boot.kernel.sysctl."net.ipv4.conf.all.proxy_arp" == null;
assert (coord.boot.kernel.sysctl."net.ipv6.conf.all.forwarding" or 0) == 0;
assert coord.services.tailscale.useRoutingFeatures == "none";
assert coord.systemd.sockets.ax-server-proxy.listenStreams == [ "127.0.0.1:8080" ];
assert coord.myAxClient.enable;

# worker: inference, nothing at runtime
assert (ax worker).enable && (ax worker).role == "inference";
assert !worker.services.k3s.enable;
assert builtins.elem 8731 worker.networking.firewall.interfaces.enp191s0.allowedTCPPorts;
# client: untouched
assert !(client ? myAxFleet);
assert !client.services.k3s.enable;

# the kill switch
assert builtins.all killed [
  "nas"
  "coordinator"
  "worker"
];

# parity with the VM test
assert normFlags nasSubst nas == normFlags { } (testOn "nas");
assert normFlags coordSubst coord == normFlags { } (testOn "coordinator");
assert
  map (lib.replaceStrings [ "enp1s0" ] [ "eth1" ]) (axLines nas.networking.firewall.extraInputRules)
  == axLines (testOn "nas").networking.firewall.extraInputRules;
assert guardText coordSubst coord == guardText { } (testOn "coordinator");

pkgs.runCommand "ax-fleet-topology" { } ''
  touch "$out"
''
