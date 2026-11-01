{
  pkgs,
  lib,
  self,
}:
let
  c = self.nixosConfigurations.strix-coordinator.config;
  cfg = c.services.d3-decision;
  unit = c.systemd.services.d3-decision;
  route = c.services.llama-swap.settings.models.${cfg.servedModelName};
in
assert cfg.enable && cfg.demand.enable;
assert route.cmd == cfg.deploymentCommand;
assert route.checkEndpoint == "/health" && route.ttl == 600;
assert !(route ? capabilities);
assert unit.wantedBy == [ ];
assert lib.elem "llama-swap.service" unit.conflicts;
assert !(lib.elem "llama-swap.service" cfg.exclusiveServices);
assert !(lib.elem cfg.port c.networking.firewall.allowedTCPPorts);
assert lib.elem cfg.artifact c.services.local-models.artifacts;
assert c.systemd.services.llama-swap.serviceConfig.MemoryDenyWriteExecute == false;
assert unit.serviceConfig.MemorySwapMax == "0";
assert cfg.package.upstreamRevision == "62c4f39e35aa2dfe929eb18223a7509ebeff6563";
pkgs.runCommand "d3-decision-policy"
  {
    nativeBuildInputs = [
      pkgs.shellcheck
      pkgs.python3
    ];
  }
  ''
    shellcheck ${unit.serviceConfig.ExecStart} ${unit.serviceConfig.ExecStartPost}
    # The launcher must use local loans and the offline native engine, with a
    # dynamically assigned proxy port and the same host-memory guard as direct mode.
    ${pkgs.gnugrep}/bin/grep -q -- /var/lib/local-models/d3-ultra-bf16 ${unit.serviceConfig.ExecStart}
    ${pkgs.gnugrep}/bin/grep -q -- --offline ${unit.serviceConfig.ExecStart}
    ${pkgs.gnugrep}/bin/grep -q -- MemAvailable ${unit.serviceConfig.ExecStart}
    LLAMA_SWAP=${lib.getExe c.services.llama-swap.package} python3 ${./test_proxy.py} -v
    touch "$out"
  ''
