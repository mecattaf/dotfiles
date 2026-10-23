{
  pkgs,
  lib,
  self,
}:
let
  configs = self.nixosConfigurations;
  variant =
    roles:
    (configs.strix.extendModules {
      modules = [
        {
          networking.hostName = lib.mkForce "strix-coordinator";
          myFleet.roles = lib.mkForce roles;
        }
      ];
    }).config;
  renamed = variant [
    "brain"
    "compute"
  ];
  compute = variant [ "compute" ];
  home = cfg: cfg.home-manager.users.tom;
  agents = cfg: (home cfg).systemd.user.services;
in
assert
  configs.strix.config.myFleet.roles == [
    "brain"
    "compute"
  ];
assert configs.nas.config.myFleet.roles == [ "router" ];
assert configs.client.config.myFleet.roles == [ "seat" ];
# Placement survives the upcoming rename, including both system and HM units.
assert agents renamed ? herdr;
assert agents renamed ? claude-transcript-mirror;
assert agents renamed ? paper-daemon;
assert (home renamed).home.activation ? aiMemoryJournal;
assert renamed.age.secrets ? codex-auth;
assert renamed.systemd.user.services ? substrate-puller;
assert renamed.services.atuin.enable;
# A compute-only host keeps its model loans and speech, without the agent tier.
assert !(agents compute ? herdr);
assert !(agents compute ? claude-transcript-mirror);
assert !(agents compute ? paper-daemon);
assert !((home compute).home.activation ? aiMemoryJournal);
assert !(compute.age.secrets ? codex-auth);
assert !(compute.systemd.user.services ? substrate-puller);
assert !compute.services.atuin.enable;
assert lib.elem "vibevoice-asr-streaming-7b-bf16" compute.services.local-models.artifacts;
assert compute.services.qwen-tts.enable;
assert compute.systemd.user.services ? qwen-tts;
assert !(compute.environment.etc ? "fleet-status/hosts.json");
assert renamed.environment.etc ? "fleet-status/hosts.json";
pkgs.runCommand "fleet-roles" { } ''touch "$out"''
