# Regression policy for the canceled second Strix (#698). Evaluation must
# prove retirement without constructing a Donnerkeule driver or TP2 binary.
{ pkgs, lib, self, inputs }:
let
  c = self.nixosConfigurations.strix-coordinator.config;
  w = self.nixosConfigurations.strix-worker.config;
  retired = host:
    !host.hardware.thunderbolt-ibverbs.enable
    && !host.services.gufo.tp2.enable
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
  watches = builtins.fromJSON (builtins.readFile ../../lib/update-watch.json);
in
assert retired c && retired w;
assert !(catalog.artifacts ? qwen38-flash-next-q8-gguf);
assert builtins.all (watch: !(builtins.elem watch.name [ "gufo-rdma" "donnerkeule" ])) watches.inputs;
assert !c.services.ds4.enable && !(c.systemd.services ? ds4);
assert !(lib.hasInfix "9911" c.networking.firewall.extraInputRules);
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
