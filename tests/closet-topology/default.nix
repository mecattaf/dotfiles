{
  pkgs,
  lib,
  self,
}:
let
  s = self.nixosConfigurations.strix-coordinator.config;
  w = self.nixosConfigurations.strix-worker.config;
  n = self.nixosConfigurations.nas.config;
  c = self.nixosConfigurations.client.config;
  registry = import ../../modules/mesh-registry.nix;
  # The NAS admits the worker only while its registry row is in service.
  workerActive = n.myFleet.active "strix-worker";
  names = [
    "client"
    "nas"
    "strix-coordinator"
    "strix-worker"
  ];
  alias = [
    "strix-coordinator"
    "strix"
  ];
  settings = builtins.fromJSON (builtins.readFile ../../home/dot_claude/settings.json);
in
assert builtins.attrNames self.nixosConfigurations == names;
assert builtins.attrNames self.deploy.nodes == names;
assert builtins.attrNames registry == names;
# Keep at most 3 NixOS generations on every host (common.nix mkDefault, #639).
assert builtins.all (h: h.boot.loader.systemd-boot.configurationLimit == 3) [
  s
  w
  n
  c
];
assert
  s.myFleet.roles == [
    "compute"
  ];
assert s.networking.hosts."10.42.0.2" == alias;
assert c.networking.hosts."10.42.0.2" == alias;
assert builtins.all (name: builtins.elem name n.networking.hosts."10.42.0.2") alias;
assert builtins.elem "9c:bf:0d:00:f6:73,strix-coordinator,10.42.0.2,infinite"
  n.services.dnsmasq.settings.dhcp-host;
assert
  builtins.attrNames s.networking.networkmanager.ensureProfiles.profiles == [
    "lan"
    "tbv0"
  ];
assert
  s.networking.networkmanager.ensureProfiles.profiles.lan.connection.interface-name == "enp191s0";
assert s.networking.networkmanager.ensureProfiles.profiles.lan.ipv4.address1 == "10.42.0.2/24";
assert s.networking.networkmanager.ensureProfiles.profiles.lan.ipv4.gateway == "10.42.0.3";
assert builtins.elem "mt7925e" s.boot.blacklistedKernelModules;
assert !s.myDisplay.enable && !s.services.greetd.enable;
assert s.services.tailscale.enable;
assert builtins.elem "--accept-dns=false" s.services.tailscale.extraSetFlags;
assert builtins.elem "--accept-routes=false" s.services.tailscale.extraSetFlags;
assert builtins.elem "--ssh=false" s.services.tailscale.extraSetFlags;
assert !s.hardware.bluetooth.enable;
assert c.myTripwire.strix-reachability.enable;
assert c.myTripwire.strix-reachability.sustainSeconds == 90;
assert !n.services.headscale.enable;
assert !(n.containers ? nas-saas);
assert n.services.tailscale.enable;
assert builtins.elem "--advertise-routes=10.42.0.0/24" n.services.tailscale.extraSetFlags;
assert builtins.elem "--state=/var/lib/tailscale-personal/tailscaled.state"
  n.services.tailscale.extraDaemonFlags;
# Serve's HTTPS (herdr-web-ui) needs a state directory for its certificates.
assert builtins.elem "--statedir=/var/lib/tailscale-personal"
  n.services.tailscale.extraDaemonFlags;
assert builtins.elem "--accept-routes=true" c.services.tailscale.extraSetFlags;
assert builtins.elem "--accept-dns=true" c.services.tailscale.extraSetFlags;
# D-55 "no-exit-client": the Zenbook's internet never depends on the NAS, so a
# dead NAS leaves the Freebox rung of the Wi-Fi ladder usable.
assert builtins.elem "--exit-node=" c.services.tailscale.extraSetFlags;
assert !builtins.elem "--exit-node=nas" c.services.tailscale.extraSetFlags;
assert !builtins.elem "--exit-node-allow-lan-access=true" c.services.tailscale.extraSetFlags;
assert
  c.networking.networkmanager.ensureProfiles.profiles.thomas-6ghz.ipv4.routing-rule1
  == "priority 2500 to 10.42.0.0/24 table 254";
# Both strix LAN profiles carry the client's rule: with accepted Tailscale
# routes 10.42.0.0/24 resolved through tailscale0 (table 52) and the
# coordinator lost the LAN on 2026-10-25. Neither accepts the route now (the
# coordinator runs --accept-routes=false, the worker has no Tailscale); the
# rule stays as a guard.
assert builtins.all
  (
    cfg:
    cfg.networking.networkmanager.ensureProfiles.profiles.lan.ipv4.routing-rule1
    == c.networking.networkmanager.ensureProfiles.profiles.thomas-6ghz.ipv4.routing-rule1
  )
  [
    s
    w
  ];
# The client's home Wi-Fi ladder (hosts/client/wifi-ladder.nix, Tom 2026-10-25):
# rung 1 gives up fast, rung 2 bypasses the NAS through the BE550 and keeps the
# LAN direct, and nothing in it is a clock.
assert c.networking.networkmanager.ensureProfiles.profiles.thomas-6ghz.connection.autoconnect-retries == 2;
assert c.networking.networkmanager.ensureProfiles.profiles.thomas-6ghz.ipv4.dhcp-timeout == 20;
assert c.networking.networkmanager.ensureProfiles.profiles.thomas-6ghz-direct.ipv4.gateway == "10.42.0.3";
assert
  c.networking.networkmanager.ensureProfiles.profiles.thomas-6ghz-direct.ipv4.routing-rule1
  == c.networking.networkmanager.ensureProfiles.profiles.thomas-6ghz.ipv4.routing-rule1;
assert
  c.networking.networkmanager.ensureProfiles.profiles.thomas-6ghz-direct.connection.autoconnect-priority
  < c.networking.networkmanager.ensureProfiles.profiles.thomas-6ghz.connection.autoconnect-priority;
assert c.networking.networkmanager.settings.connectivity.interval == 60;
assert
  c.systemd.services.wifi-ladder-return.wantedBy == [ ]
  && c.systemd.services.wifi-ladder-guard.wantedBy == [ ];
assert !(c.systemd.timers ? wifi-ladder-return) && !(c.systemd.timers ? wifi-ladder-guard);
assert s.services.gufo.autoStart;
assert s.services.utilityModel.endpoint == "http://strix-coordinator:8731";
assert n.services.immich.environment.IMMICH_MACHINE_LEARNING_URL == "http://strix-coordinator:3003";
assert s.systemd.services.immich-machine-learning.wantedBy == [ ];
assert s.systemd.services.immich-machine-learning.unitConfig.StopWhenUnneeded;
assert s.systemd.sockets ? immich-ml-access;
assert s.services.immich.package.version == n.services.immich.package.version;
assert n.hardware.printers.ensureDefaultPrinter == "Brother_HL_L2445DW";
assert
  (builtins.head n.hardware.printers.ensurePrinters).deviceUri == "ipp://10.42.0.4:631/ipp/print";
assert builtins.all
  (
    h:
    !h.services.printing.enable && !h.services.avahi.enable && !(h.systemd.services ? ensure-printers)
  )
  [
    s
    w
  ];
assert !(s.home-manager.users.tom.systemd.user.paths ? paper-daemon);
assert !(s.home-manager.users.tom.systemd.user.services ? herdr);
assert !(settings ? model) && !(settings ? effortLevel) && !(settings ? modelSettings);
assert lib.hasInfix "10.42.0.5" n.services.nfs.server.exports == workerActive;
assert registry.strix-worker.dormant -> !workerActive;
assert !n.services.k3s.enable && !s.services.k3s.enable;
assert !n.services.dockerRegistry.enable;
assert builtins.elem "user@1000.service" s.systemd.services.keyring-unlock-boot.wantedBy;
assert builtins.elem "user@1001.service" c.systemd.services.keyring-unlock-boot.wantedBy;
assert builtins.elem "user@1001.service" c.systemd.services.keyring-unlock-boot.partOf;
assert builtins.elem "sys-subsystem-net-devices-wlo1.device"
  c.systemd.services.wpa_supplicant.after;
assert builtins.elem "9c:bf:0d:01:cc:65,strix-worker,10.42.0.5,infinite"
  n.services.dnsmasq.settings.dhcp-host;
assert builtins.all (cfg: cfg.networking.hosts."10.42.0.5" == [ "strix-worker" ]) [
  s
  w
  n
  c
];
assert w.networking.hosts."127.0.0.2" == [ ];
assert
  w.networking.networkmanager.ensureProfiles.profiles.lan.connection.interface-name == "enp191s0";
assert w.networking.networkmanager.ensureProfiles.profiles.lan.ipv4.address1 == "10.42.0.5/24";
assert w.networking.networkmanager.ensureProfiles.profiles.lan.ipv4.gateway == "10.42.0.3";
assert w.networking.networkmanager.ensureProfiles.profiles.lan.ipv4.dns == "10.42.0.1";
assert w.networking.networkmanager.ensureProfiles.profiles.lan.ipv6.method == "disabled";
# Tom, 2026-10-25: the coordinator keeps its own Tailscale login as the
# independent recovery box (no exit node, no accepted routes, internet through
# the BE550); the worker is not on the tailnet and is reached over the LAN.
assert
  s.myFleetTransport.enable
  && s.services.tailscale.enable
  && s.services.tailscale.useRoutingFeatures == "client"
  && s.services.tailscale.authKeyFile == null
  && s.services.tailscale.extraUpFlags == s.services.tailscale.extraSetFlags
  &&
    s.services.tailscale.extraSetFlags == [
      "--hostname=strix-coordinator"
      "--accept-dns=false"
      "--ssh=false"
      "--accept-routes=false"
      "--exit-node="
    ];
assert !w.myFleetTransport.enable && !w.services.tailscale.enable;
assert !(w.systemd.services ? tailscaled-set);
assert !w.services.k3s.enable && !w.mySecrets.enable;
assert builtins.all (name: name == "gufo-tp2-control-token") (builtins.attrNames w.age.secrets);
assert !w.myDisplay.enable && !w.services.greetd.enable;
assert !(w.systemd.sockets ? immich-ml-access);
assert w.services.gufo.enable && w.services.qwen-tts.enable;
assert w.boot.kernelPackages.kernel.version == s.boot.kernelPackages.kernel.version;
assert builtins.attrNames w.disko.devices.disk == [ "w1t" ];
assert w.disko.devices.disk.w1t.device == "/dev/disk/by-id/nvme-WD_BLACK_SN7100_1TB_26051Y809195";
assert
  w.disko.devices.disk.w1t.content.partitions.ESP.uuid == "25db1b50-f51c-499b-a628-26a25fa02662";
assert
  w.disko.devices.disk.w1t.content.partitions.root.uuid == "e4869fbf-f6c5-4bf5-960f-cf19376e139d";
assert w.fileSystems."/".device == "/dev/disk/by-partuuid/e4869fbf-f6c5-4bf5-960f-cf19376e139d";
assert !w.boot.loader.efi.canTouchEfiVariables;
assert w.home-manager.users.tom.rawDotfiles.inStore;
assert !(w.systemd.services ? dotfiles-bootstrap);
assert s.home-manager.users.tom.rawDotfiles.inStore;
assert !(s.systemd.services ? dotfiles-bootstrap);
assert
  w.disko.devices.disk.w1t.content.partitions.ESP.uuid
  != s.disko.devices.disk.main.content.partitions.ESP.uuid;
assert
  w.disko.devices.disk.w1t.content.partitions.root.uuid
  != s.disko.devices.disk.main.content.partitions.root.uuid;
assert w.fileSystems."/".fsType == "ext4" && w.fileSystems."/boot".fsType == "vfat";
assert builtins.elem "umask=0077" w.fileSystems."/boot".options;
assert builtins.all
  (
    cfg:
    cfg.fileSystems."/mnt/library".device == "nas:/models"
    && builtins.elem "ro" cfg.fileSystems."/mnt/library".options
  )
  [
    s
    w
  ];
assert w.fileSystems."/mnt/nas/documents".device == "nas:/documents";
assert builtins.elem "ro" w.fileSystems."/mnt/nas/documents".options;
assert
  lib.hasInfix "10.42.0.5(ro,sync,fsid=6,no_subtree_check,root_squash)" n.services.nfs.server.exports
  == workerActive;
assert
  lib.hasInfix "10.42.0.5(ro,sync,fsid=3,no_subtree_check,root_squash)" n.services.nfs.server.exports
  == workerActive;
assert
  lib.hasInfix "ip saddr 10.42.0.5 tcp dport 2049 accept" n.networking.firewall.extraInputRules
  == workerActive;
assert
  lib.hasInfix "ip saddr 10.42.0.5 tcp dport 19532 accept" n.networking.firewall.extraInputRules
  == workerActive;
assert builtins.elem "10.42.0.5" n.services.adguardhome.settings.dns.ratelimit_whitelist;
assert builtins.all
  (
    rule:
    !(builtins.elem registry.strix-coordinator.hostKey rule.publicKeys)
    && !(builtins.elem "" rule.publicKeys)
  )
  (
    builtins.attrValues (
      builtins.removeAttrs (import ../../secrets.nix) [ "secrets/gufo-tp2-control-token.age" ]
    )
  );
assert n.systemd.services ? handwriting-annotation;
assert !(s.systemd.services ? handwriting-annotation);
assert n.services.caddy.virtualHosts ? "https://handwriting.internal";
assert builtins.any (p: (p.name or "") == "wifi-ladder") c.environment.systemPackages;
pkgs.runCommand "closet-topology"
  {
    # Building this check builds the ladder script, and writeShellApplication
    # runs shellcheck on it.
    wifiLadder = builtins.filter (p: (p.name or "") == "wifi-ladder") c.environment.systemPackages;
  }
  ''touch "$out"''
