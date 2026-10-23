{
  config,
  lib,
  pkgs,
  ...
}:
let
  registry = import ./mesh-registry.nix;
  localModel = import ../lib/local-model.nix;
  # The old spelling permits this stacked branch to evaluate before #608.
  coordinator = registry.strix-coordinator or registry.strix;
  worker = registry.strix-worker or { hostKey = ""; };
  key = config.age.secrets.ssh-user-key.path;
  builders = {
    strix-coordinator = {
      address = "10.42.0.2";
      inherit (coordinator) hostKey;
    };
    strix-worker = {
      address = "10.42.0.5";
      inherit (worker) hostKey;
    };
  };
in
{
  imports = [ ./utility-model.nix ];
  assertions = [
    {
      assertion = config.myFleet.has "brain" && config.networking.hostName == "nas";
      message = "The NAS agent offload profile belongs on the NAS brain.";
    }
  ];
  nix.distributedBuilds = true;
  nix.settings = {
    max-jobs = lib.mkForce 0;
    builders-use-substitutes = true;
  };
  nix.buildMachines = lib.mapAttrsToList (hostName: _: {
    inherit hostName;
    protocol = "ssh-ng";
    sshUser = "tom";
    sshKey = key;
    systems = [ "x86_64-linux" ];
    maxJobs = 2;
    speedFactor = if hostName == "strix-coordinator" then 2 else 1;
    supportedFeatures = [
      "nixos-test"
      "benchmark"
      "big-parallel"
      "kvm"
    ];
  }) builders;

  # Both root's Nix daemon and tom's harness commands must authenticate the
  # compute host. An unrecorded worker key fails closed, without a TOFU prompt.
  programs.ssh.knownHosts = lib.mapAttrs' (
    name: target:
    lib.nameValuePair "fleet-builder-${name}" {
      hostNames = [
        name
        target.address
      ];
      publicKey = target.hostKey;
    }
  ) (lib.filterAttrs (_: target: target.hostKey != "") builders);
  programs.ssh.extraConfig =
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: target: ''
        Host ${name}
          HostName ${target.address}
          User tom
          IdentityFile ${key}
          IdentitiesOnly yes
          BatchMode yes
          StrictHostKeyChecking yes
          ForwardAgent no
          ConnectTimeout 10
      '') builders
    )
    + "\nHost *\n";
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "fleet-exec";
      runtimeInputs = [
        pkgs.python3
        pkgs.openssh
      ];
      text = ''exec python3 ${../pkgs/fleet-exec/fleet_exec.py} "$@"'';
    })
  ];
  services.utilityModel.enable = true;
  environment.variables.LOCAL_MODEL_ENDPOINT = lib.mkDefault localModel.endpoint;
  systemd.globalEnvironment.LOCAL_MODEL_ENDPOINT = lib.mkDefault localModel.endpoint;
  environment.etc."local-model.json".text = lib.mkDefault (builtins.toJSON localModel);
}
