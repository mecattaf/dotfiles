{
  pkgs,
  lib,
  self,
}:
let
  nas = self.nixosConfigurations.nas.config;
  client = self.nixosConfigurations.client.config;
  compute =
    name:
    (self.nixosConfigurations.strix.extendModules {
      modules = [
        {
          networking.hostName = lib.mkForce name;
          myFleet.roles = lib.mkForce [ "compute" ];
        }
      ];
    }).config;
  coordinator =
    if self.nixosConfigurations ? strix-coordinator then
      self.nixosConfigurations.strix-coordinator.config
    else
      compute "strix-coordinator";
  worker =
    if self.nixosConfigurations ? strix-worker then
      self.nixosConfigurations.strix-worker.config
    else
      compute "strix-worker";
  # Tom, 2026-10-25 ("default vanilla, make it work"): the NAS is the only
  # exit node, nobody selects it, the coordinator keeps its own login as the
  # recovery box, and the worker is not on the tailnet.
  consumers = [
    client
    coordinator
  ];
  members = [ nas ] ++ consumers;
  flags = c: c.services.tailscale.extraSetFlags;
  hasHerdrWebUi =
    c:
    c.systemd.services ? herdr-web-ui-serve
    || (c.home-manager.users.tom.systemd.user.services or { }) ? herdr-web-ui;
  waitsForNetmap =
    c:
    builtins.any (lib.hasInfix "tailscaled-set-wait-netmap") (
      lib.toList (c.systemd.services.tailscaled-set.serviceConfig.ExecStartPre or [ ])
    );
  targets = [
    "strix-coordinator"
    "strix-worker"
  ];
in
assert nas.myFleetTransport.enable;
assert nas.services.tailscale.useRoutingFeatures == "server";
assert builtins.elem "--advertise-exit-node" nas.services.tailscale.extraSetFlags;
assert builtins.elem "--advertise-routes=10.42.0.0/24" nas.services.tailscale.extraSetFlags;
assert !builtins.any (lib.hasPrefix "--exit-node=") nas.services.tailscale.extraSetFlags;
assert builtins.all (
  c:
  c.myFleetTransport.enable
  && c.services.tailscale.enable
  && c.services.tailscale.useRoutingFeatures == "client"
  # Every consumer clears any exit node and selects none.
  && builtins.elem "--exit-node=" (flags c)
  && !builtins.any (
    f:
    (lib.hasPrefix "--exit-node=" f && f != "--exit-node=")
    || lib.hasPrefix "--exit-node-allow-lan-access" f
  ) (flags c)
  && !builtins.any (lib.hasPrefix "--advertise-") (flags c)
) consumers;
# The roaming Zenbook: the NAS subnet route and MagicDNS, as Tailscale defaults.
assert builtins.elem "--accept-routes=true" (flags client);
assert builtins.elem "--accept-dns=true" (flags client);
# The recovery coordinator depends on nothing the NAS advertises.
assert
  flags coordinator == [
    "--hostname=strix-coordinator"
    "--accept-dns=false"
    "--ssh=false"
    "--accept-routes=false"
    "--exit-node="
  ];
# The worker is LAN-only: no daemon, no preference unit, no policy file.
assert !worker.myFleetTransport.enable;
assert !worker.services.tailscale.enable;
assert !(worker.systemd.services ? tailscaled-set);
assert !(worker.systemd.services ? tailscaled);
assert !(worker.environment.etc ? "fleet/transport.json");
# Every member's tailscaled-set waits (bounded) for a netmap with the NAS
# before `tailscale set`, so the set never races tailscaled's start.
assert builtins.all waitsForNetmap members;
assert builtins.all (
  c: c.systemd.services.tailscaled-set.serviceConfig.TimeoutStartSec == "180s"
) members;
assert builtins.all (
  c:
  c.services.tailscale.extraUpFlags == c.services.tailscale.extraSetFlags
  && c.services.tailscale.authKeyFile == null
  && builtins.elem "--ssh=false" (flags c)
  && !builtins.any (lib.hasPrefix "--login-server=") (flags c)
) members;
assert builtins.all (c: builtins.elem "--accept-dns=false" (flags c)) [
  nas
  coordinator
];
# The Herdr web UI follows Herdr to the NAS: only the NAS serves it, over
# private Tailscale HTTPS on :443 (https://nas.tail8dd1.ts.net/). The
# coordinator's old Serve (strix.tail8dd1.ts.net:8443) is not declared anywhere.
assert hasHerdrWebUi nas;
assert lib.hasInfix "serve --https=443 http://127.0.0.1:7317"
  nas.systemd.services.herdr-web-ui-serve.serviceConfig.ExecStart;
assert
  !builtins.any hasHerdrWebUi [
    client
    coordinator
    worker
  ];
assert builtins.all (
  c:
  !builtins.any (unit: lib.hasInfix "--https=8443" (toString (unit.serviceConfig.ExecStart or ""))) (
    builtins.attrValues c.systemd.services
  )
) (members ++ [ worker ]);
# Navidrome is served by the NAS; its scan helper dials it there, never the
# retired strix tailnet name.
assert lib.hasInfix "set url http://nas:4533" (
  builtins.readFile ../../home/dot_config/fish/functions/navidrome-scan.fish
);
assert builtins.all (path: !lib.hasInfix "strix.tail8dd1.ts.net" (builtins.readFile path)) [
  ../../home/dot_config/fish/functions/navidrome-scan.fish
  ../../hosts/strix-coordinator/nas-client.nix
  ../../hosts/client/default.nix
  ../../modules/fleet-transport.nix
];
assert builtins.all
  (port: builtins.elem port nas.networking.firewall.interfaces.tailscale0.allowedTCPPorts)
  [
    443
    2283
    4533
    32400
  ];
assert nas.nix.distributedBuilds && nas.nix.settings.max-jobs == 0;
assert nas.nix.settings.builders-use-substitutes;
assert map (b: b.hostName) nas.nix.buildMachines == targets;
assert builtins.all (
  b:
  b.protocol == "ssh-ng"
  && b.sshUser == "tom"
  && b.maxJobs == 2
  && b.sshKey == "/run/agenix/ssh-user-key"
) nas.nix.buildMachines;
assert lib.hasInfix "StrictHostKeyChecking yes" nas.programs.ssh.extraConfig;
assert lib.hasInfix "ForwardAgent no" nas.programs.ssh.extraConfig;
assert nas.services.utilityModel.enable;
assert nas.services.utilityModel.endpoint == "http://strix-coordinator:8731";
assert nas.services.utilityModel.modelId == "qwen3.8-flash-next";
assert nas.environment.variables.LOCAL_MODEL_ENDPOINT == nas.services.utilityModel.endpoint;
assert !(nas.systemd.services ? gufo-llm);
assert !builtins.any (p: lib.getName p == "fleet-exec") client.environment.systemPackages;
pkgs.runCommand "fleet-agent-transport" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  export PYTHONDONTWRITEBYTECODE=1
  python3 ${./test_transport.py} ${../../pkgs/fleet-exec/fleet_exec.py} ${../../pkgs/fleet-transport/check.py}
  touch "$out"
''
