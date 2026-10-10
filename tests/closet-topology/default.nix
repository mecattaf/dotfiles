{
  pkgs,
  lib,
  self,
}:
let
  s = self.nixosConfigurations.strix.config;
  n = self.nixosConfigurations.nas.config;
  c = self.nixosConfigurations.client.config;
  registry = import ../../modules/mesh-registry.nix;
  names = [
    "client"
    "nas"
    "strix"
  ];
  alias = [
    "strix"
    "coordinator"
  ];
  settings = builtins.fromJSON (builtins.readFile ../../home/dot_claude/settings.json);
in
assert builtins.attrNames self.nixosConfigurations == names;
assert builtins.attrNames self.deploy.nodes == names;
assert builtins.attrNames registry == names;
assert s.networking.hostName == "strix";
assert s.networking.hosts."10.42.0.2" == alias;
assert c.networking.hosts."10.42.0.2" == alias;
assert builtins.all (name: builtins.elem name n.networking.hosts."10.42.0.2") alias;
assert builtins.elem "9c:bf:0d:00:f6:73,strix,10.42.0.2,infinite"
  n.services.dnsmasq.settings.dhcp-host;
assert builtins.attrNames s.networking.networkmanager.ensureProfiles.profiles == [ "lan" ];
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
assert builtins.elem "--accept-routes" c.services.tailscale.extraSetFlags;
assert
  c.networking.networkmanager.ensureProfiles.profiles.thomas-6ghz.ipv4.routing-rule1
  == "priority 2500 to 10.42.0.0/24 table 254";
assert s.services.halogen.autoStart;
assert s.services.halogen.client.endpoint == "http://strix:8731";
assert n.services.immich.environment.IMMICH_MACHINE_LEARNING_URL == "http://strix:3003";
assert s.systemd.services.immich-machine-learning.wantedBy == [ ];
assert s.systemd.services.immich-machine-learning.unitConfig.StopWhenUnneeded;
assert s.systemd.sockets ? immich-ml-access;
assert s.services.immich.package.version == n.services.immich.package.version;
assert s.hardware.printers.ensureDefaultPrinter == "Brother_HL_L2445DW";
assert
  (builtins.head s.hardware.printers.ensurePrinters).deviceUri == "ipp://10.42.0.4:631/ipp/print";
assert s.home-manager.users.tom.systemd.user.paths ? paper-daemon;
assert s.home-manager.users.tom.systemd.user.services.herdr.Unit.X-SwitchMethod == "keep-old";
assert !(settings ? model) && !(settings ? effortLevel) && !(settings ? modelSettings);
assert builtins.all (host: !lib.hasInfix "10.42.0.5" host.services.nfs.server.exports) [ n ];
assert n.myAxFleet.agentAddresses == [ "10.42.0.2" ];
assert s.myAxFleet.lan.interface == "enp191s0" && s.myAxFleet.lan.extraInterfaces == [ ];
assert builtins.elem "user@1000.service" s.systemd.services.keyring-unlock-boot.wantedBy;
assert builtins.elem "user@1001.service" c.systemd.services.keyring-unlock-boot.wantedBy;
assert builtins.elem "user@1001.service" c.systemd.services.keyring-unlock-boot.partOf;
assert builtins.elem "sys-subsystem-net-devices-wlo1.device"
  c.systemd.services.wpa_supplicant.after;
pkgs.runCommand "closet-topology" { } ''touch "$out"''
