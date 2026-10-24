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
  exports = lib.filter (line: line != "") (
    lib.splitString "\n" configs.nas.config.services.nfs.server.exports
  );
  exportFor = path: lib.filter (line: lib.hasPrefix "${path} " line) exports;
  onlyExport = path: expected: exportFor path == [ expected ];
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
assert
  configs.nas.config.myFleet.roles == [
    "router"
    "brain"
  ];
assert configs.client.config.myFleet.roles == [ "seat" ];
# Operator state on services/backups/.snapshots must not cross a Btrfs
# export boundary. Pin the complete evaluated export set, not source text.
assert builtins.length exports == 6;
assert lib.all (line: !(lib.hasInfix "no_root_squash" line)) exports;
assert exportFor "/mnt/nas/services" == [ ];
assert exportFor "/mnt/nas/backups" == [ ];
assert exportFor "/mnt/nas/.snapshots" == [ ];
assert onlyExport "/mnt/nas"
  "/mnt/nas 10.42.0.2(ro,sync,fsid=0,no_subtree_check,root_squash) 10.42.0.5(ro,sync,fsid=0,no_subtree_check,root_squash)";
assert lib.all
  (
    entry:
    onlyExport "/mnt/nas/${entry.name}" "/mnt/nas/${entry.name} 10.42.0.2(ro,sync,fsid=${entry.fsid},no_subtree_check,root_squash)"
  )
  [
    {
      name = "photos";
      fsid = "1";
    }
    {
      name = "music";
      fsid = "2";
    }
    {
      name = "videos";
      fsid = "5";
    }
  ];
assert onlyExport "/mnt/nas/documents"
  "/mnt/nas/documents 10.42.0.2(rw,sync,fsid=3,no_subtree_check,root_squash) 10.42.0.5(ro,sync,fsid=3,no_subtree_check,root_squash)";
assert onlyExport "/mnt/nas/models"
  "/mnt/nas/models 10.42.0.2(ro,sync,fsid=6,no_subtree_check,root_squash) 10.42.0.5(ro,sync,fsid=6,no_subtree_check,root_squash)";
pkgs.runCommand "fleet-roles" { } ''touch "$out"''
