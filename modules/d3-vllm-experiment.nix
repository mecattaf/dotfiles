{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.d3-vllm-experiment;
  catalog = import ../lib/local-models.nix { inherit lib; };
  modelStore = import ../lib/model-store.nix { inherit catalog lib; };
  model = modelStore.materialized.${cfg.artifact};
  bundleCheck = import ../lib/model-bundle-check.nix { inherit lib pkgs modelStore; };
  owners = [
    "llama-swap.service"
    "d3-decision.service"
    "gufo-llm.service"
    "gufo-tp2.service"
    "gufo-image.service"
    "gufo-tts.service"
    "gufo-asr.service"
    "qwen-tts.service"
    "ds4.service"
  ]
  ++ lib.optionals (config.services.gufo.enable or false) (
    map (name: "gufo-llm-${name}.service") (builtins.attrNames config.services.gufo.alternates)
  );
  launcher = pkgs.writeShellApplication {
    name = "d3-vllm-experiment";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.systemd
    ];
    text = ''
      case "''${1:-}" in
        baseline) mode=baseline; export D3_VLLM_LIBSTRIX=0 ;;
        libstrix) mode=libstrix; export D3_VLLM_LIBSTRIX=1 ;;
        --help|-h)
          echo "usage: d3-vllm-experiment baseline|libstrix [vllm serve options]"
          echo "Manually release other GPU owners first; serves /v1/systemone on loopback."
          exit 0 ;;
        *) echo "usage: d3-vllm-experiment baseline|libstrix [vllm serve options]" >&2; exit 2 ;;
      esac
      shift
      ${bundleCheck [ cfg.artifact ]}
      ${lib.concatMapStringsSep "\n" (unit: ''
        if systemctl is-active --quiet ${lib.escapeShellArg unit}; then
          echo "d3-vllm-experiment: ${unit} is active; explicitly release the GPU first" >&2
          exit 1
        fi
      '') owners}
      available=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
      if [ "$available" -lt ${toString (cfg.minimumAvailableGiB * 1024 * 1024)} ]; then
        echo "d3-vllm-experiment: needs ${toString cfg.minimumAvailableGiB} GiB MemAvailable; available $available KiB" >&2
        exit 1
      fi
      cache_base="''${D3_CACHE_ROOT:-''${XDG_CACHE_HOME:-$HOME/.cache}/d3-vllm-experiment}"
      export D3_CACHE_ROOT="$cache_base/$mode"
      ${lib.getExe cfg.package} serve ${lib.escapeShellArg model.directory} \
        --served-model-name ${lib.escapeShellArg cfg.servedModelName} \
        --port ${toString cfg.port} \
        --dtype bfloat16 --enforce-eager \
        --max-model-len ${toString cfg.maxModelLen} \
        --max-num-seqs 1 --max-num-batched-tokens ${toString cfg.maxModelLen} \
        --gpu-memory-utilization ${toString cfg.gpuMemoryUtilization} \
        "$@" --host 127.0.0.1 &
      server=$!
      (
        while kill -0 "$server" 2>/dev/null; do
          available=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
          if [ "$available" -lt ${toString (cfg.reserveGiB * 1024 * 1024)} ]; then
            echo "d3-vllm-experiment: MemAvailable crossed the ${toString cfg.reserveGiB} GiB reserve; stopping this experiment" >&2
            kill -TERM "$server"
            exit 1
          fi
          sleep 2
        done
      ) &
      guard=$!
      cleanup() {
        kill -TERM "$server" "$guard" 2>/dev/null || true
        wait "$server" 2>/dev/null || true
        wait "$guard" 2>/dev/null || true
      }
      trap cleanup EXIT
      trap 'exit 143' TERM
      trap 'exit 130' INT
      wait "$server"
    '';
  };
  ready = pkgs.writeShellScript "d3-vllm-experiment-ready" ''
    until ${lib.getExe pkgs.curl} --fail --silent --output /dev/null http://127.0.0.1:${toString cfg.port}/health; do
      ${pkgs.coreutils}/bin/sleep 2
    done
  '';
in
{
  options.services.d3-vllm-experiment = {
    enable = lib.mkEnableOption "the manual patched vLLM/libstrix D3 comparison appliance";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../pkgs/vllm-d3 { };
    };
    artifact = lib.mkOption {
      type = lib.types.str;
      default = "d3-ultra-bf16";
      description = "Existing NAS Library artifact loan; startup never fetches it.";
    };
    servedModelName = lib.mkOption {
      type = lib.types.str;
      default = "d3-ultra";
    };
    libstrix = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use libstrix GDN/linear swaps in the manual unit; causal attention swaps stay disabled.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8734;
    };
    maxModelLen = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4096;
    };
    gpuMemoryUtilization = lib.mkOption {
      type = lib.types.float;
      default = 0.65;
    };
    minimumAvailableGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 80;
    };
    reserveGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 12;
    };
    launcher = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = launcher;
      description = "Explicit baseline/libstrix CLI, also usable inside runtime-test --allow-gpu.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          builtins.hasAttr cfg.artifact catalog.artifacts
          && catalog.artifacts.${cfg.artifact}.source.layout == "snapshot";
        message = "d3-vllm-experiment requires a complete snapshot from the local model catalog.";
      }
      {
        assertion =
          cfg.minimumAvailableGiB > cfg.reserveGiB
          && cfg.gpuMemoryUtilization > 0.0
          && cfg.gpuMemoryUtilization < 0.85;
        message = "d3-vllm-experiment must leave host RAM and GPU allocation headroom.";
      }
      {
        assertion = !(lib.elem cfg.port config.networking.firewall.allowedTCPPorts);
        message = "d3-vllm-experiment is a loopback-only manual worker.";
      }
    ];
    services.local-models.requirements.d3-vllm-experiment = [ cfg.artifact ];
    environment.systemPackages = [ launcher ];
    system.build.d3-vllm-experiment = launcher;
    systemd.services.d3-vllm-experiment = {
      description = "D3 Ultra patched vLLM experiment (manual, loopback, BF16)";
      # No wantedBy/socket/timer, no implicit GPU-owner stop and no changes to
      # llama-swap hardening or its production native D3 route.
      after = [ "network.target" ];
      environment.D3_CACHE_ROOT = "/var/cache/d3-vllm-experiment";
      serviceConfig = {
        Type = "exec";
        ExecStart = "${lib.getExe launcher} ${if cfg.libstrix then "libstrix" else "baseline"}";
        ExecStartPost = ready;
        DynamicUser = true;
        SupplementaryGroups = [
          "render"
          "video"
        ];
        CacheDirectory = "d3-vllm-experiment";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        # Only this explicitly enabled experimental service may create the
        # namespaces bubblewrap needs. The production proxy stays untouched.
        RestrictNamespaces = [
          "user"
          "pid"
          "ipc"
          "uts"
          "mnt"
        ];
        MemoryDenyWriteExecute = false;
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
