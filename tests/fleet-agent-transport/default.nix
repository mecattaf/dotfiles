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
  consumers = [
    client
    coordinator
    worker
  ];
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
  && builtins.elem "--exit-node=nas" c.services.tailscale.extraSetFlags
  && builtins.elem "--exit-node-allow-lan-access=true" c.services.tailscale.extraSetFlags
  && builtins.elem "--accept-routes=true" c.services.tailscale.extraSetFlags
) consumers;
assert builtins.all (
  c:
  c.services.tailscale.extraUpFlags == c.services.tailscale.extraSetFlags
  && c.services.tailscale.authKeyFile == null
  && builtins.elem "--accept-dns=false" c.services.tailscale.extraSetFlags
  && builtins.elem "--ssh=false" c.services.tailscale.extraSetFlags
  && !builtins.any (lib.hasPrefix "--login-server=") c.services.tailscale.extraSetFlags
) ([ nas ] ++ consumers);
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
