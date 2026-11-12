# Regression policy for the canceled second Strix (#698). Evaluation must
# prove retirement without constructing a Donnerkeule driver or TP2 binary.
{ pkgs, lib, self, inputs }:
let
  c = self.nixosConfigurations.strix-coordinator.config;
  w = self.nixosConfigurations.strix-worker.config;
  retired = host:
    !(host.hardware ? thunderbolt-ibverbs)
    && !(host.services.gufo ? tp2)
    && !(host.systemd.services ? thunderbolt-ibverbs-check)
    && !(host.systemd.services ? gufo-tp2)
    && !(host.systemd.services ? gufo-tp2-latency)
    && !(host.networking.networkmanager.ensureProfiles.profiles ? tbv0)
    && !(host.age.secrets ? gufo-tp2-control-token)
    && !(builtins.elem "thunderbolt_net" host.boot.blacklistedKernelModules)
    && !(builtins.elem "thunderbolt_stream" host.boot.blacklistedKernelModules)
    && !(builtins.elem "thunderbolt_ibverbs" host.boot.kernelModules)
    && !(lib.hasInfix "18515" host.networking.firewall.extraInputRules)
    && !(lib.hasInfix "18516" host.networking.firewall.extraInputRules)
    && !(builtins.elem "qwen38-flash-next-q8-gguf" host.services.local-models.artifacts)
    && !(host.environment.etc ? "gufo/tp2-q8-wanted.json");
  catalog = import ../../lib/local-models.nix { inherit lib; };
  # Kept from the removed tests/ds4 (2026-11-13, #536): local DeepSeek stays
  # retired from every catalog, remote/API DeepSeek routes stay.
  dsh = self.nixosConfigurations.nas.pkgs.dsh;
  localModel = import ../../lib/local-model.nix;
  retiredDeepseek = [
    "deepseek-v41-flash-1017-q2-gguf"
    "deepseek-v41-flash-vision-gguf"
    "deepseek-v41-flash-dspark-gguf"
  ];
in
assert retired c && retired w;
assert !(catalog.artifacts ? qwen38-flash-next-q8-gguf);
assert !(self.nixosConfigurations.strix-coordinator.options.services ? ds4) && !(c.systemd.services ? ds4);
assert !(lib.hasInfix "9911" c.networking.firewall.extraInputRules);
assert builtins.all (id: !(catalog.artifacts ? ${id})) retiredDeepseek;
assert builtins.all (host:
  !(host.environment.etc ? "ds4/wanted.json")
  && builtins.all (id: !(builtins.elem id host.services.local-models.artifacts)) retiredDeepseek
) [ c w ];
assert !(localModel ? ds4);
assert !(dsh.localProviders ? ds4);
assert dsh.localProviders ? gufo;
assert dsh.routes.nvidia-deepseek.provider == "nvidia";
assert dsh.routes.cloudflare-deepseek.provider == "cloudflare-workers-ai";
assert dsh.routes.zen-deepseek.provider == dsh.zenProvider;
assert builtins.any (model: model.id == "deepseek-ai/DeepSeek-V4.1-Flash") dsh.cloudProviders.huggingface.models;
assert c.services.gufo.enable && c.services.llama-swap.enable;
assert c.services.gufo.package == inputs.gufo.packages.x86_64-linux.default;
assert c.services.gufo.lanInterface == "enp191s0";
assert c.networking.networkmanager.ensureProfiles.profiles.lan.ipv4.address1 == "10.42.0.2/24";
assert c.services.tailscale.enable;
assert c.myStrixCompute.immichMl.enable;
assert c.services.utilityModel.enable;
assert c.services.qwen-tts.enable;
assert c.services.d3-decision.enable;
assert !(c.myFleet.active "strix-worker");
pkgs.writeText "single-strix-retirement-policy" "Donnerkeule and TP2 retired; single-host services retained.\n"
