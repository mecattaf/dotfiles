{
  pkgs,
  lib,
  self,
  inputs,
}:
let
  c = self.nixosConfigurations.strix-coordinator.config;
  q8 =
    (self.nixosConfigurations.strix-coordinator.extendModules {
      modules = [ { services.gufo.tp2.model.artifact = "qwen38-flash-next-q8-gguf"; } ];
    }).config;
  w = self.nixosConfigurations.strix-worker.config;
  catalog = import ../../lib/local-models.nix { inherit lib; };
  all = builtins.fromJSON (builtins.readFile ../../lib/ds4-models.json);
  check =
    host:
    let
      unit = host.systemd.services.ds4;
    in
    host.services.ds4.enable
    && unit.wantedBy == [ ]
    && lib.hasInfix "--pull=never" unit.serviceConfig.ExecStart
    && lib.hasInfix "--transport tcp" unit.serviceConfig.ExecStart
    && !(lib.hasInfix "/dev/infiniband" unit.serviceConfig.ExecStart)
    && !(builtins.elem "deepseek-v41-flash-1017-q2-gguf" host.services.local-models.artifacts)
    && builtins.elem "gufo-tp2.service" unit.conflicts;
in
assert check c && check w;
assert c.services.ds4.role == "coordinator" && w.services.ds4.role == "worker";
assert c.services.ds4.image == w.services.ds4.image;
assert inputs.gufo.rev == "7b1bf049a0a3600345676fdf0a544152ac7ce6a1";
assert lib.strings.trim (builtins.readFile (inputs.gufo + "/version.txt")) == "0.22.0";
assert c.services.gufo.tp2.model.artifact == "qwen38-flash-next-gguf";
assert q8.services.gufo.llm.artifact == "qwen38-flash-next-gguf";
assert q8.services.gufo.tp2.model.artifact == "qwen38-flash-next-q8-gguf";
assert lib.all (entry: entry.assertion) q8.assertions;
assert catalog.artifacts.qwen38-flash-next-q8-gguf.quantization == "Q8_0";
assert builtins.length catalog.artifacts.qwen38-flash-next-q8-gguf.source.files == 8;
assert
  all.deepseek-v41-flash-1017-q2-gguf.source.revision == "20408f699619df7071aa7cda6034e9cef5bf804b";
assert all.deepseek-v41-flash-1017-q2-gguf.source.files != [ ];
# Tom 2026-10-25: the fleet's DeepSeek is kyuz0's 1017 set. Target, vision and
# DSpark come from one repo revision, so ds4 never pairs a 1017 language model
# with the original-release vision encoder (it dies at load).
assert lib.all (
  row:
  row.source.hfUrl == "https://huggingface.co/kyuz0/deepseek-v4.1-flash-gguf"
  && row.source.revision == all.deepseek-v41-flash-1017-q2-gguf.source.revision
) (builtins.attrValues all);
pkgs.runCommand "ds4-fleet-policy"
  {
    nativeBuildInputs = [
      pkgs.shellcheck
      pkgs.python3
    ];
  }
  ''
    shellcheck ${c.systemd.services.ds4.serviceConfig.ExecStartPre} ${w.systemd.services.ds4.serviceConfig.ExecStartPre}
    python3 ${./test_models.py} ${../../lib/gufo-models.json} ${../../lib/ds4-models.json}
    touch "$out"
  ''
