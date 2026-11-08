{
  pkgs,
  lib,
  self,
  inputs,
}:
let
  c = self.nixosConfigurations.strix-coordinator.config;
  w = self.nixosConfigurations.strix-worker.config;
  # single-ssd streams experts from disk, so DSpark must be refused there.
  wDspark =
    (self.nixosConfigurations.strix-worker.extendModules {
      modules = [ { services.ds4.dspark = lib.mkForce true; } ];
    }).config;
  localModel = import ../../lib/local-model.nix;
  has = host: needle: lib.hasInfix needle host.systemd.services.ds4.serviceConfig.ExecStart;
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
    # TCP is the only TP transport the pinned image has (no usb4_rdma provider).
    && (host.services.ds4.mode != "tp2" || lib.hasInfix "--transport tcp" unit.serviceConfig.ExecStart)
    && !(lib.hasInfix "/dev/infiniband" unit.serviceConfig.ExecStart)
    && builtins.elem "gufo-tp2.service" unit.conflicts;
  ds4Ids = [
    "deepseek-v41-flash-1017-q2-gguf"
    "deepseek-v41-flash-vision-gguf"
    "deepseek-v41-flash-dspark-gguf"
  ];
  wantedDs4 =
    host: builtins.filter (id: builtins.elem id ds4Ids) host.services.local-models.artifacts;
in
assert !c.services.ds4.enable && !(c.systemd.services ? ds4);
assert check w;
# The host that runs ds4 wants exactly the files it loads (the Q2; vision and
# DSpark are off), so prune keeps them and a default borrow restores them. The
# coordinator's TP2 rank cannot hold the 340.6 GiB Q2 (D-A) and wants none.
assert w.services.ds4.wanted && wantedDs4 w == [ "deepseek-v41-flash-1017-q2-gguf" ];
assert !c.services.ds4.wanted && wantedDs4 c == [ ];
assert c.services.ds4.role == "coordinator" && w.services.ds4.role == "worker";
assert c.services.ds4.image == w.services.ds4.image;
# Tom 2026-10-25: DeepSeek V4.1 serves from the worker alone (SSD expert
# streaming, no DSpark) until both disks hold the Q2; the coordinator keeps the
# TP2 rank shape.
assert c.services.ds4.mode == "tp2" && w.services.ds4.mode == "single-ssd";
assert !(lib.hasInfix "tcp dport 9911" c.networking.firewall.extraInputRules);
assert has w "ds4-server --rocm -m /models/";
assert has w "--ssd-streaming --ssd-streaming-cache-experts 76GB --batched-session 1";
assert has w "--host 10.42.0.5 --port 8732";
assert lib.all (flag: !(has w flag)) [
  "--tensor-parallel"
  "--role"
  "--transport"
  "--mtp-model"
  "--dspark"
  "--vision"
];
assert lib.hasInfix "ip saddr 10.42.0.1 tcp dport 8732 accept" w.networking.firewall.extraInputRules;
assert !(lib.hasInfix "tcp dport 9911" w.networking.firewall.extraInputRules);
assert lib.any (
  entry: lib.hasPrefix "ds4 single-ssd" entry.message && !entry.assertion
) wDspark.assertions;
# The dsh ds4 route (pkgs/dsh/config.nix) names exactly what the worker serves.
assert
  localModel.ds4.endpoint == "http://${w.services.ds4.apiAddress}:${toString w.services.ds4.port}";
assert localModel.ds4.contextWindow == w.services.ds4.context;
assert c.services.gufo.package == inputs.gufo.packages.x86_64-linux.default;
assert !c.services.gufo.tp2.enable;
assert !(catalog.artifacts ? qwen38-flash-next-q8-gguf);
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
    shellcheck ${w.systemd.services.ds4.serviceConfig.ExecStartPre}
    python3 ${./test_models.py} ${../../lib/gufo-models.json} ${../../lib/ds4-models.json}
    touch "$out"
  ''
