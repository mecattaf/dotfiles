{ lib }:

let
  inherit (lib) mkOption types;

  nullableString = types.nullOr types.str;

  checkpointType = types.submodule {
    options = {
      url = mkOption {
        type = types.str;
        description = "Canonical model/checkpoint URL.";
      };
      revision = mkOption {
        type = types.str;
        description = "Immutable source revision.";
      };
    };
  };

  fileType = types.submodule {
    options = {
      path = mkOption {
        type = types.str;
        description = "Path below the pinned Hugging Face revision.";
      };
      bytes = mkOption {
        type = types.ints.positive;
        description = "Exact byte size.";
      };
      oid = mkOption {
        type = types.str;
        description = "Upstream LFS object ID.";
      };
      hash = mkOption {
        type = types.str;
        description = "Nix SRI content hash.";
      };
    };
  };

  artifactType = types.submodule {
    options = {
      kind = mkOption {
        type = types.enum [
          "model"
          "mtp-head"
          "mmproj"
          "tokenizer"
          "template"
        ];
        description = "Artifact's role in a deployment.";
      };
      maker = mkOption {
        type = types.str;
        description = "Organization or person that trained the artifact.";
      };
      baseCheckpoint = mkOption {
        type = types.nullOr checkpointType;
        default = null;
      };
      fineTune = mkOption {
        type = types.nullOr checkpointType;
        default = null;
      };
      source = {
        hfUrl = mkOption {
          type = types.str;
          description = "Canonical Hugging Face repository URL.";
        };
        revision = mkOption {
          type = types.str;
          description = "Pinned Hugging Face commit.";
        };
        primary = mkOption {
          type = types.str;
          description = "Primary file path; the first part for split GGUFs.";
        };
        files = mkOption {
          type = types.nonEmptyListOf fileType;
          description = "One file or every part of a split artifact.";
        };
      };
      notes = mkOption {
        type = types.str;
        default = "";
      };
    };
  };

  artifactRefsType = types.submodule {
    options = {
      model = mkOption {
        type = nullableString;
        default = null;
      };
      mtpHead = mkOption {
        type = nullableString;
        default = null;
      };
      mmproj = mkOption {
        type = nullableString;
        default = null;
      };
      tokenizer = mkOption {
        type = nullableString;
        default = null;
      };
      template = mkOption {
        type = nullableString;
        default = null;
      };
    };
  };

  runtimeType = types.submodule {
    options = {
      repository = mkOption {
        type = types.str;
        description = "Runtime source repository.";
      };
      commit = mkOption {
        type = types.str;
        description = "Exact runtime commit.";
      };
      args = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          Backend arguments. @model@, @mtpHead@, @mmproj@, @tokenizer@, and
          @template@ resolve to immutable store paths.
        '';
      };
    };
  };

  peerType = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "llama-swap peer ID.";
      };
      proxy = mkOption {
        type = types.str;
        description = "OpenAI-compatible upstream base URL.";
      };
      systemdUnit = mkOption {
        type = nullableString;
        default = null;
        description = "Optional local backend unit ordered before llama-swap.";
      };
    };
  };

  benchmarkType = types.submodule {
    options = {
      sourceRepo = mkOption { type = types.str; };
      sourceCommit = mkOption { type = types.str; };
      runId = mkOption { type = types.str; };
      name = mkOption { type = types.str; };
      score = mkOption {
        type = nullableString;
        default = null;
      };
      speed = mkOption {
        type = nullableString;
        default = null;
      };
      context = mkOption {
        type = nullableString;
        default = null;
      };
    };
  };

  deploymentType = types.submodule {
    options = {
      model = mkOption {
        type = types.str;
        description = "Model ID presented through llama-swap.";
      };
      role = mkOption {
        type = types.enum [
          "utility"
          "coding"
          "general"
          "quality"
          "vision"
          "draft"
        ];
      };
      status = mkOption {
        type = types.enum [
          "canonical"
          "candidate"
          "experimental"
          "negative"
          "retired"
        ];
      };
      backend = mkOption {
        type = types.enum [
          "rocm"
          "vulkan"
          "ds4"
          "vllm"
          "mlx"
          "sd-rocm"
          "npu"
        ];
      };
      hosts = mkOption {
        type = types.nonEmptyListOf (
          types.enum [
            "coordinator"
            "worker"
          ]
        );
        description = "Hosts on which this canonical deployment is installed.";
      };
      ramTierGb = mkOption {
        type = types.ints.unsigned;
        default = 0;
      };
      artifacts = mkOption {
        type = artifactRefsType;
        default = { };
      };
      runtime = mkOption { type = runtimeType; };
      peer = mkOption {
        type = types.nullOr peerType;
        default = null;
      };
      benchmark = mkOption {
        type = types.nullOr benchmarkType;
        default = null;
      };
      evidence = mkOption {
        type = types.enum [
          "matched-local"
          "upstream-measured"
          "api-only"
          "unverified"
        ];
      };
      hardware = mkOption {
        type = types.str;
        default = "";
      };
      supersedes = mkOption {
        type = nullableString;
        default = null;
      };
      supersededBy = mkOption {
        type = nullableString;
        default = null;
      };
      notes = mkOption {
        type = types.str;
        default = "";
      };
    };
  };

  evaluated = lib.evalModules {
    modules = [
      {
        options = {
          artifacts = mkOption {
            type = types.attrsOf artifactType;
            default = { };
          };
          deployments = mkOption {
            type = types.attrsOf deploymentType;
            default = { };
          };
        };

        config = {
          # No GGUF is promoted during this storage-constrained bootstrap.
          artifacts = { };

          deployments.flm-gemma4-it-e4b = {
            model = "gemma4-it:e4b";
            role = "utility";
            status = "canonical";
            backend = "npu";
            hosts = [ "coordinator" ];
            runtime = {
              repository = "https://github.com/FastFlowLM/FastFlowLM";
              commit = "fd371409897d7c0abb4de4dbc5098b9b43c094ff";
            };
            peer = {
              name = "flm";
              proxy = "http://127.0.0.1:52625";
              systemdUnit = "flm-serve.service";
            };
            evidence = "matched-local";
            hardware = "coordinator XDNA2 NPU; amdxdna/XRT from nix-amd-ai";
            notes = "FastFlowLM owns these weights via runtime flm pull; callers still enter through llama-swap.";
          };
        };
      }
    ];
  };
in
{
  inherit (evaluated.config) artifacts deployments;
}
