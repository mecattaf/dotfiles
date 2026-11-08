# Local DeepSeek retirement must not reacquire the user-evicted Library bytes.
{ pkgs, lib, self, inputs }:
let
  dsh = self.nixosConfigurations.nas.pkgs.dsh;
  localModel = import ../../lib/local-model.nix;
  catalog = import ../../lib/local-models.nix { inherit lib; };
  retired = [
    "deepseek-v41-flash-1017-q2-gguf"
    "deepseek-v41-flash-vision-gguf"
    "deepseek-v41-flash-dspark-gguf"
  ];
  hosts = map (name: self.nixosConfigurations.${name}.config) [
    "strix-coordinator"
    "strix-worker"
  ];
in
assert builtins.all (id: !(builtins.hasAttr id catalog.artifacts)) retired;
assert builtins.all (host:
  !host.services.ds4.enable
  && !(host.systemd.services ? ds4)
  && !(host.environment.etc ? "ds4/wanted.json")
  && builtins.all (id: !(builtins.elem id host.services.local-models.artifacts)) retired
  && !(lib.hasInfix "9911" host.networking.firewall.extraInputRules)
) hosts;
assert self.nixosConfigurations.strix-coordinator.config.services.gufo.enable;
# Retirement includes the selectable client catalog, not just the server.
assert !(localModel ? ds4);
assert !(dsh.localProviders ? ds4);
assert dsh.localProviders ? gufo;
assert dsh.routes.nvidia-deepseek.provider == "nvidia";
assert dsh.routes.cloudflare-deepseek.provider == "cloudflare-workers-ai";
assert dsh.routes.zen-deepseek.provider == dsh.zenProvider;
assert builtins.any (model: model.id == "deepseek-ai/DeepSeek-V4.1-Flash") dsh.cloudProviders.huggingface.models;
pkgs.writeText "local-deepseek-retirement-policy" "Local DeepSeek acquisition and loans retired; provider API routes unchanged.\n"
