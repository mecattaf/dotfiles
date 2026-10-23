{
  pkgs,
  lib,
  self,
}:
let
  configs = self.nixosConfigurations;
  computeHosts = map (name: configs.${name}.config) [
    "strix-coordinator"
    "strix-worker"
  ];
  clean =
    cfg:
    let
      home = cfg.home-manager.users.tom;
    in
    cfg.myFleet.roles == [ "compute" ]
    && !cfg.mySecrets.enable
    && lib.all (name: name == "gufo-tp2-control-token") (builtins.attrNames cfg.age.secrets)
    && !(home.systemd.user.services ? herdr)
    && !(home.systemd.user.services ? paper-daemon)
    && !(home.systemd.user.services ? claude-transcript-mirror)
    && !(home.home.activation ? aiMemoryJournal)
    && !(home.home.activation ? claudeSettings)
    && !(home.home.file ? ".claude/skills")
    && !(home.home.file ? ".pi/agent/models.json")
    && !(cfg.systemd.user.services ? substrate-puller)
    && !(cfg.systemd.user.services ? substrate-pusher)
    && !(cfg.systemd.services ? journal-archive)
    && !cfg.services.atuin.enable
    && !(cfg.environment.etc ? "fleet-status/hosts.json")
    && cfg.services.gufo.enable
    && cfg.services.qwen-tts.enable
    && cfg.microvm.host.enable
    && lib.elem "vibevoice-asr-streaming-7b-bf16" cfg.services.local-models.artifacts;
in
assert lib.all clean computeHosts;
assert configs.nas.config.myFleet.roles == [ "router" ];
assert configs.client.config.myFleet.roles == [ "seat" ];
pkgs.runCommand "fleet-roles" { } ''touch "$out"''
