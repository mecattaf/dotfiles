{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.d3-decision;
  catalog = import ../lib/local-models.nix { inherit lib; };
  modelStore = import ../lib/model-store.nix { inherit catalog lib; };
  model = modelStore.materialized.${cfg.artifact};
  bundleCheck = import ../lib/model-bundle-check.nix { inherit lib pkgs modelStore; };
  args = [
    (lib.getExe cfg.package)
    "serve"
    model.directory
    "--offline"
    "--device"
    "rocm:0"
    "--engine"
    "native"
    "--family"
    "decision3"
    "--served-model-name"
    cfg.servedModelName
    "--host"
    cfg.host
    "--memory-budget"
    (toString cfg.memoryBudgetGiB)
    "--max-num-seqs"
    (toString cfg.maxNumSeqs)
    "--max-num-batched-tokens"
    (toString cfg.maxNumBatchedTokens)
    "--max-queue"
    "8"
    "--max-queued-tokens"
    (toString (cfg.maxNumBatchedTokens * 8))
    "--result-cache-entries"
    "0"
    "--media-workers"
    "0"
    "--load-attempts"
    "1"
  ];
  preflight = pkgs.writeShellScript "d3-decision-preflight" ''
    set -eu
    # llama-swap releases its previous child before invoking this launcher.
    # Standalone diagnostic services must also have released the GPU.
    ${lib.concatMapStringsSep "\n" (unit: ''
      if ${pkgs.systemd}/bin/systemctl is-active --quiet ${lib.escapeShellArg unit}; then
        echo "d3-decision: ${unit} is active; explicitly release the GPU before starting D3" >&2
        exit 1
      fi
    '') cfg.exclusiveServices}
    available="$(${pkgs.gawk}/bin/awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
    if [ "$available" -lt ${toString (cfg.minimumAvailableGiB * 1024 * 1024)} ]; then
      echo "d3-decision: needs at least ${toString cfg.minimumAvailableGiB} GiB MemAvailable before loading; available: $available KiB" >&2
      exit 1
    fi
  '';
  # Unified GPU allocations also consume system RAM. An in-process memory
  # budget is an estimate; this guard ends only this service if host RAM falls
  # below the reserve. systemd cleans the service's whole cgroup afterwards.
  start = pkgs.writeShellScript "d3-decision-start" ''
    set -eu
    port="''${1:-${toString cfg.port}}"
    case "$port" in
      ""|*[!0-9]*) echo "d3-decision: port must be an integer" >&2; exit 2 ;;
    esac
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
      echo "d3-decision: port must be between 1 and 65535" >&2
      exit 2
    fi
    ${bundleCheck [ cfg.artifact ]}
    ${preflight}
    # The demand child uses llama-swap's own writable cache; direct mode uses
    # its private CacheDirectory. Neither can access a user's Hub credentials.
    cache="''${D3_CACHE_ROOT:-''${LLAMA_CACHE:-/var/cache/d3-decision}/d3-decision}"
    export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
    export HF_HOME="$cache/huggingface" XDG_CACHE_HOME="$cache"
    export TORCHINDUCTOR_CACHE_DIR="$cache/torchinductor" TRITON_CACHE_DIR="$cache/triton"
    ${lib.escapeShellArgs args} --port "$port" --autotune-cache "$cache/autotune" &
    server=$!
    (
      while kill -0 "$server" 2>/dev/null; do
        available="$(${pkgs.gawk}/bin/awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
        if [ "$available" -lt ${toString (cfg.reserveGiB * 1024 * 1024)} ]; then
          echo "d3-decision: stopping after host MemAvailable fell below ${toString cfg.reserveGiB} GiB" >&2
          kill -TERM "$server"
          exit 1
        fi
        ${pkgs.coreutils}/bin/sleep 2
      done
    ) &
    guard=$!
    trap 'kill -TERM "$server" "$guard" 2>/dev/null || true' EXIT
    trap 'exit 143' TERM
    trap 'exit 130' INT
    wait "$server"
  '';
  ready = pkgs.writeShellScript "d3-decision-ready" ''
    until ${pkgs.curl}/bin/curl --fail --silent --output /dev/null http://127.0.0.1:${toString cfg.port}/health; do
      ${pkgs.coreutils}/bin/sleep 2
    done
  '';
in
{
  options.services.d3-decision = {
    enable = lib.mkEnableOption "the offline D3 decision-model worker";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../pkgs/vllm-srun {
        torchRocm = inputs.nix-strix-halo.packages.${pkgs.stdenv.hostPlatform.system}.torch-rocm;
      };
      description = "Pinned native vLLM Semantic Router runtime with gfx1151 PyTorch.";
    };
    artifact = lib.mkOption {
      type = lib.types.str;
      default = "d3-ultra-bf16";
      description = "Snapshot artifact in the NAS Library/local-models catalog; no Hub name is passed to the server.";
    };
    wanted = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Include this model in the host's explicit borrow set; activation still moves no bytes.";
    };
    servedModelName = lib.mkOption {
      type = lib.types.str;
      default = "d3-ultra";
    };
    demand.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.services.llama-swap.enable;
      description = "Register D3 in the existing llama-swap supervisor, under its native /upstream/<model>/v1/systemone endpoint.";
    };
    demand.idleSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 600;
    };
    deploymentCommand = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${start} \${PORT}";
      description = "Offline, guarded native worker command; llama-swap assigns its private port.";
    };
    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "API bind address; loopback by default, with no firewall opening.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8733;
    };
    maxNumSeqs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
    };
    maxNumBatchedTokens = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4096;
    };
    memoryBudgetGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 90;
    };
    minimumAvailableGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 80;
    };
    reserveGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 12;
    };
    exclusiveServices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "gufo-llm.service"
        "gufo-tp2.service"
        "gufo-image.service"
        "ds4.service"
        "qwen-tts.service"
      ]
      ++ lib.optionals (config.services.gufo.enable or false) (
        map (name: "gufo-llm-${name}.service") (builtins.attrNames config.services.gufo.alternates)
      );
      description = "Refuse startup while any named GPU owner is active; never stop it implicitly.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.hasAttr cfg.artifact catalog.artifacts;
        message = "d3-decision.artifact must exist in the local model catalog.";
      }
      {
        assertion = catalog.artifacts.${cfg.artifact}.source.layout == "snapshot";
        message = "d3-decision needs a complete snapshot artifact, including the manifest and readout.";
      }
      {
        assertion = cfg.minimumAvailableGiB > cfg.reserveGiB;
        message = "d3-decision.minimumAvailableGiB must exceed reserveGiB.";
      }
    ];
    services.local-models.requirements.d3-decision = lib.mkIf (cfg.wanted || cfg.demand.enable) [
      cfg.artifact
    ];
    services.llama-swap.settings.models = lib.mkIf cfg.demand.enable {
      ${cfg.servedModelName} = {
        cmd = cfg.deploymentCommand;
        checkEndpoint = "/health";
        ttl = cfg.demand.idleSeconds;
        useModelName = cfg.servedModelName;
        timeouts.responseHeader = 1200;
      };
    };
    # PyTorch/Triton JIT code needs executable mappings. The proxy otherwise
    # keeps its existing dynamic user, read-only model paths and GPU groups.
    systemd.services.llama-swap.serviceConfig = lib.mkIf cfg.demand.enable {
      MemoryDenyWriteExecute = lib.mkForce false;
    };
    systemd.services.d3-decision = {
      description = "D3 Ultra System One decisions (manual, native ROCm worker)";
      # No wantedBy/socket/path/timer: rebuilding never starts a GPU workload.
      after = [ "network.target" ];
      conflicts = [ "llama-swap.service" ];
      environment.D3_CACHE_ROOT = "/var/cache/d3-decision";
      serviceConfig = {
        Type = "exec";
        ExecStart = start;
        ExecStartPost = ready;
        DynamicUser = true;
        SupplementaryGroups = [
          "render"
          "video"
        ];
        CacheDirectory = "d3-decision";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadOnlyPaths = [ modelStore.runtimeRoot ];
        LimitMEMLOCK = "infinity";
        MemoryHigh = "92G";
        MemoryMax = "96G";
        MemorySwapMax = "0";
        OOMPolicy = "stop";
        KillMode = "control-group";
        TimeoutStartSec = "20min";
        TimeoutStopSec = "30s";
        Restart = "no";
      };
    };
  };
}
