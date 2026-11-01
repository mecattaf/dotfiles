{
  pkgs,
  lib,
  self,
}:
let
  production = self.nixosConfigurations.strix-coordinator.config;
  experiment =
    (self.nixosConfigurations.strix-coordinator.extendModules {
      modules = [ { services.d3-vllm-experiment.enable = true; } ];
    }).config;
  cfg = experiment.services.d3-vllm-experiment;
  unit = experiment.systemd.services.d3-vllm-experiment;
  proxy = c: c.systemd.services.llama-swap.serviceConfig;
in
assert !production.services.d3-vllm-experiment.enable;
assert !(production.systemd.services ? d3-vllm-experiment);
assert production.services.d3-decision.enable;
assert production.services.llama-swap.settings.models ? d3-ultra;
assert unit.wantedBy == [ ] && unit.conflicts == [ ];
assert cfg.artifact == "d3-ultra-bf16" && !cfg.libstrix;
assert cfg.maxModelLen == 4096 && cfg.port == 8734;
assert !(lib.elem cfg.port experiment.networking.firewall.allowedTCPPorts);
assert
  unit.serviceConfig.RestrictNamespaces == [
    "user"
    "pid"
    "ipc"
    "uts"
    "mnt"
  ];
assert unit.serviceConfig.MemoryDenyWriteExecute == false;
assert unit.serviceConfig.ExecPaths == [ "/var/cache/d3-vllm-experiment" ];
assert (proxy production).RestrictNamespaces == (proxy experiment).RestrictNamespaces;
assert (proxy production).SystemCallFilter == (proxy experiment).SystemCallFilter;
assert
  production.services.llama-swap.settings.models == experiment.services.llama-swap.settings.models;
pkgs.runCommand "d3-vllm-experiment-policy" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
  shellcheck ${lib.getExe cfg.launcher} ${unit.serviceConfig.ExecStartPost}
  # Help must remain useful without touching weights, services or the GPU.
  ${lib.getExe cfg.launcher} --help
  touch "$out"
''
