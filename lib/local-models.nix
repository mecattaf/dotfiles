{ lib }:

let
  inherit (lib) mkOption types;

  backendKinds = import ./local-model-backends.nix;
  nullableString = types.nullOr types.str;

  mkSingleFileArtifact =
    {
      kind ? "model",
      maker,
      baseCheckpoint ? null,
      fineTune ? null,
      hfUrl,
      revision,
      path,
      bytes,
      oid,
      hash,
      notes ? "",
    }:
    {
      inherit
        kind
        maker
        baseCheckpoint
        fineTune
        notes
        ;
      source = {
        inherit hfUrl revision;
        primary = path;
        files = [
          {
            inherit
              path
              bytes
              oid
              hash
              ;
          }
        ];
      };
    };

  llamaCppCommit = "571d0d540df04f25298d0e159e520d9fc62ed121";
  llamaCppRuntime = args: {
    repository = "https://github.com/ggml-org/llama.cpp";
    commit = llamaCppCommit;
    inherit args;
  };
  commonLlamaArgs = [
    "--ctx-size"
    "32768"
    "--gpu-layers"
    "999"
    "--flash-attn"
    "on"
    "--no-mmap"
    "--jinja"
  ];

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
          "embedding"
          "uncensored"
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
        type = types.enum (backendKinds.local ++ backendKinds.peers);
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
          # This is a metadata roster. modules/strix.nix deliberately keeps
          # downloadAllModels=false, so none of these fixed-output artifacts is
          # fetched or rooted until Tom manually lifts that gate.
          artifacts = {
            qwen36-35b-a3b-mxfp4 = mkSingleFileArtifact {
              maker = "Qwen";
              baseCheckpoint = {
                url = "https://huggingface.co/Qwen/Qwen3.6-35B-A3B";
                revision = "995ad96eacd98c81ed38be0c5b274b04031597b0";
              };
              hfUrl = "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF";
              revision = "a483e9e6cbd595906af30beda3187c2663a1118c";
              path = "Qwen3.6-35B-A3B-MXFP4_MOE.gguf";
              bytes = 21706144736;
              oid = "2fdd20997c4d88ee25f70f500c61f8b999378d92ab055f9d450fc70d617158d3";
              hash = "sha256-L90gmXxNiO4l9w9QDGH4uZk3jZKrBV+dRQ/HDWFxWNM=";
              notes = "Exact artifact measured in the tesla_agent stable workhorse row.";
            };

            qwen3-coder-next-ud-q4-k-xl = mkSingleFileArtifact {
              maker = "Qwen";
              baseCheckpoint = {
                url = "https://huggingface.co/Qwen/Qwen3-Coder-Next";
                revision = "a7fbcb5c0e12d62a448eaa0e260346bf5dcc0feb";
              };
              hfUrl = "https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF";
              revision = "ce09c67b53bc8739eef83fe67b2f5d293c270632";
              path = "Qwen3-Coder-Next-UD-Q4_K_XL.gguf";
              bytes = 49608478720;
              oid = "4bb93f0a0221ef4ff963ca9094df629c8dfdfabc3b4fdd85c1a2e4c0624fce36";
              hash = "sha256-S7k/CgIh70/5Y8qQlN9inI39+rw7T92FwaLkwGJPzjY=";
            };

            qwopus36-27b-v2-q5-k-m = mkSingleFileArtifact {
              maker = "Jackrong";
              baseCheckpoint = {
                url = "https://huggingface.co/Qwen/Qwen3.6-27B";
                revision = "6a9e13bd6fc8f0983b9b99948120bc37f49c13e9";
              };
              fineTune = {
                url = "https://huggingface.co/Jackrong/Qwopus3.6-27B-v2";
                revision = "d0d82f4ccc9d41d4fe9595e96be4595327bb5de7";
              };
              hfUrl = "https://huggingface.co/Jackrong/Qwopus3.6-27B-v2-GGUF";
              revision = "ef90e98f127675cd5457c71fb30ff184f751e963";
              path = "Qwopus3.6-27B-v2-Q5_K_M.gguf";
              bytes = 19231097088;
              oid = "9ca652ecafef6f59ecc206ef399ac66179acd63268a66159381d18cc323473e7";
              hash = "sha256-nKZS7K/vb1nswgbvOZrGYXms1jJopmFZOB0YzDI0c+c=";
            };

            gemma4-26b-a4b-qat-q4-0 = mkSingleFileArtifact {
              maker = "Google";
              baseCheckpoint = {
                url = "https://huggingface.co/google/gemma-4-26B-A4B";
                revision = "24548b62aa021d562695c04aaf7758a1ea47990b";
              };
              fineTune = {
                url = "https://huggingface.co/google/gemma-4-26B-A4B-it-qat-q4_0-unquantized";
                revision = "f1e06dc520982d9b9edd76859fdb7ab209449949";
              };
              hfUrl = "https://huggingface.co/google/gemma-4-26B-A4B-it-qat-q4_0-gguf";
              revision = "d1c082be9cf3c8a514acf63b8761f4b41935842e";
              path = "gemma-4-26B_q4_0-it.gguf";
              bytes = 14439363584;
              oid = "3eca3b8f6d7baf218a7dd6bba5fb59a56ee25fe2d567b6f5f589b4f697eca51d";
              hash = "sha256-Pso7j217ryGKfda7pftZpW7iX+LVZ7b19Ym09pfspR0=";
              notes = "Corrected-vocabulary upstream revision from 2026-07-17; it supersedes the older bitstream used by the published Strix benchmark and needs a matched local recheck.";
            };

            gemma4-26b-a4b-qat-mtp-q4-0 = mkSingleFileArtifact {
              kind = "mtp-head";
              maker = "Google";
              baseCheckpoint = {
                url = "https://huggingface.co/google/gemma-4-26B-A4B-it-qat-q4_0-unquantized-assistant";
                revision = "9537141506fe8875b3ed45b264af13580cb29166";
              };
              hfUrl = "https://huggingface.co/unsloth/gemma-4-26B-A4B-it-qat-GGUF";
              revision = "7b92b5b28818151e8669af2e45e88d6086f490dd";
              path = "mtp-gemma-4-26B-A4B-it.gguf";
              bytes = 251939328;
              oid = "7272d97595f0d4c74bd7b623492b7dbdaafd8b7c72f329a8270ba4eca68f768a";
              hash = "sha256-cnLZdZXw1MdL17YjSSt9var9i3xy8ymoJwuk7KaPdoo=";
              notes = "QAT-matched MTP head; keep coupled to the corrected QAT model row.";
            };

            deepseek-v4-flash-q4-imatrix = mkSingleFileArtifact {
              maker = "DeepSeek";
              baseCheckpoint = {
                url = "https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash";
                revision = "60d8d70770c6776ff598c94bb586a859a38244f1";
              };
              hfUrl = "https://huggingface.co/antirez/deepseek-v4-gguf";
              revision = "a88c423b511666d7ff7a4dcaee651669312bea97";
              path = "DeepSeek-V4-Flash-Q4KExperts-F16HC-F16Compressor-F16Indexer-Q8Attn-Q8Shared-Q8Out-chat-v2-imatrix.gguf";
              bytes = 164633502592;
              oid = "a2a3b31eca06344b93d32b2095511c4d36f92739a68a599b22047b4b2335d859";
              hash = "sha256-oqOzHsoGNEuT0ysglVEcTTb5JzmmilmbIgR7SyM12Fk=";
            };

            deepseek-v4-flash-mtp = mkSingleFileArtifact {
              kind = "mtp-head";
              maker = "DeepSeek";
              baseCheckpoint = {
                url = "https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash";
                revision = "60d8d70770c6776ff598c94bb586a859a38244f1";
              };
              hfUrl = "https://huggingface.co/antirez/deepseek-v4-gguf";
              revision = "a88c423b511666d7ff7a4dcaee651669312bea97";
              path = "DeepSeek-V4-Flash-MTP-Q4K-Q8_0-F32.gguf";
              bytes = 3807602400;
              oid = "afd481ee689dce9037f70f39085fcdae5a5b096d521cdad43b19fa52bf8f4083";
              hash = "sha256-r9SB7midzpA39w85CF/NrlpbCW1SHNrUOxn6Ur+PQIM=";
            };

            qwen36-35b-a3b-abliterated-heretic-q4-k-m = mkSingleFileArtifact {
              maker = "Youssofal";
              baseCheckpoint = {
                url = "https://huggingface.co/Qwen/Qwen3.6-35B-A3B";
                revision = "995ad96eacd98c81ed38be0c5b274b04031597b0";
              };
              fineTune = {
                url = "https://huggingface.co/Youssofal/Qwen3.6-35B-A3B-Abliterated-Heretic-GGUF";
                revision = "4c22107061e656fb2a87a3ec2491bb61975eb581";
              };
              hfUrl = "https://huggingface.co/Youssofal/Qwen3.6-35B-A3B-Abliterated-Heretic-GGUF";
              revision = "4c22107061e656fb2a87a3ec2491bb61975eb581";
              path = "Qwen3.6-35B-A3B-Abliterated-Heretic-Q4_K_M/Qwen3.6-35B-A3B-Abliterated-Heretic-Q4_K_M.gguf";
              bytes = 21166758336;
              oid = "ae2fb73ac0da875640269f1e65e9c7fb415b066c6d544c3eef9adb0d03f04792";
              hash = "sha256-ri+3OsDah1ZAJp8eZenH+0FbBmxtVEw+75rbDQPwR5I=";
              notes = "Heretic MPOA/SOMA-style refusal-removal route; text-only deployment despite the base model's optional vision projector.";
            };

            supergemma4-26b-uncensored-q4-k-m = mkSingleFileArtifact {
              maker = "Jiunsong";
              baseCheckpoint = {
                url = "https://huggingface.co/google/gemma-4-26B-A4B-it";
                revision = "4d7ae4984b7db7de8f8457170b3f1a419ee76d52";
              };
              fineTune = {
                url = "https://huggingface.co/Jiunsong/supergemma4-26b-uncensored-gguf-v2";
                revision = "3ea8c452a2b136875c0c8b529612bed39c81e27a";
              };
              hfUrl = "https://huggingface.co/Jiunsong/supergemma4-26b-uncensored-gguf-v2";
              revision = "3ea8c452a2b136875c0c8b529612bed39c81e27a";
              path = "supergemma4-26b-uncensored-fast-v2-Q4_K_M.gguf";
              bytes = 16796015232;
              oid = "e773b0a209d48524f9d485bca0818247f75d7ddde7cce951367a7e441fb59137";
              hash = "sha256-53OwognUhST51IW8oIGCR/ddfd3nzOlRNnp+RB+1kTc=";
            };

            glm47-flash-uncensored-aggressive-q4-k-m = mkSingleFileArtifact {
              maker = "HauhauCS";
              baseCheckpoint = {
                url = "https://huggingface.co/zai-org/GLM-4.7-Flash";
                revision = "7dd20894a642a0aa287e9827cb1a1f7f91386b67";
              };
              fineTune = {
                url = "https://huggingface.co/HauhauCS/GLM-4.7-Flash-Uncensored-HauhauCS-Aggressive";
                revision = "4b2f44dc827d3f58ee162371cf1d915371c8270e";
              };
              hfUrl = "https://huggingface.co/tripolskypetr/GLM-4.7-Flash-Uncensored-Aggressive-GGUF";
              revision = "5ad26ddb3ea7d64bc56ba1dab20bc52e776439cd";
              path = "GLM-4.7-Flash-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf";
              bytes = 18132721216;
              oid = "cb4126a4c668091a89672ca02c63c86c24fd13b55abb119ad0533de5887395d0";
              hash = "sha256-y0EmpMZoCRqJZyygLGPIbCT9E7VauxGa0FM95YhzldA=";
              notes = "Aggressive refusal-removal route selected to diversify the pool beyond Heretic/abliteration.";
            };

            qwen3-vl-8b-instruct-q8-0 = mkSingleFileArtifact {
              maker = "Qwen";
              baseCheckpoint = {
                url = "https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct";
                revision = "0c351dd01ed87e9c1b53cbc748cba10e6187ff3b";
              };
              hfUrl = "https://huggingface.co/unsloth/Qwen3-VL-8B-Instruct-GGUF";
              revision = "b93a7ee713758252c555be4210c00540df954dc2";
              path = "Qwen3-VL-8B-Instruct-Q8_0.gguf";
              bytes = 8709520224;
              oid = "cb8616bf6ed228982d9e47d7b72b42195342efa26044b0ee1873e61d9e78d3d7";
              hash = "sha256-y4YWv27SKJgtnkfXtytCGVNC76JgRLDuGHPmHZ5409c=";
            };

            qwen3-vl-8b-mmproj-bf16 = mkSingleFileArtifact {
              kind = "mmproj";
              maker = "Qwen";
              baseCheckpoint = {
                url = "https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct";
                revision = "0c351dd01ed87e9c1b53cbc748cba10e6187ff3b";
              };
              hfUrl = "https://huggingface.co/unsloth/Qwen3-VL-8B-Instruct-GGUF";
              revision = "b93a7ee713758252c555be4210c00540df954dc2";
              path = "mmproj-BF16.gguf";
              bytes = 1162569280;
              oid = "6516bb64bae1503a0fcd7ec9fa39655f8c481580be0a0a066397941d9761c9f4";
              hash = "sha256-ZRa7ZLrhUDoPzX7J+jllX4xIFYC+CgoGY5eUHZdhyfQ=";
            };

            qwen3-vl-32b-instruct-q4-k-m = mkSingleFileArtifact {
              maker = "Qwen";
              baseCheckpoint = {
                url = "https://huggingface.co/Qwen/Qwen3-VL-32B-Instruct";
                revision = "0cfaf48183f594c314753d30a4c4974bc75f3ccb";
              };
              hfUrl = "https://huggingface.co/unsloth/Qwen3-VL-32B-Instruct-GGUF";
              revision = "b9262a359f54dead8e2609f6146e2fc3398fd0d9";
              path = "Qwen3-VL-32B-Instruct-Q4_K_M.gguf";
              bytes = 19762151200;
              oid = "92d605566f8661b296251c535ed028ecf81c32e14e06948a3d8bef829e96a804";
              hash = "sha256-ktYFVm+GYbKWJRxTXtAo7PgcMuFOBpSKPYvvgp6WqAQ=";
            };

            qwen3-vl-32b-mmproj-bf16 = mkSingleFileArtifact {
              kind = "mmproj";
              maker = "Qwen";
              baseCheckpoint = {
                url = "https://huggingface.co/Qwen/Qwen3-VL-32B-Instruct";
                revision = "0cfaf48183f594c314753d30a4c4974bc75f3ccb";
              };
              hfUrl = "https://huggingface.co/unsloth/Qwen3-VL-32B-Instruct-GGUF";
              revision = "b9262a359f54dead8e2609f6146e2fc3398fd0d9";
              path = "mmproj-BF16.gguf";
              bytes = 1200334496;
              oid = "f42400deb87085f1e76159a92aedd276050c665c72423597413d341c36c18c71";
              hash = "sha256-9CQA3rhwhfHnYVmpKu3SdgUMZlxyQjWXQT00HDbBjHE=";
            };

            qwen3-embedding-8b-q5-0 = mkSingleFileArtifact {
              maker = "Qwen";
              baseCheckpoint = {
                url = "https://huggingface.co/Qwen/Qwen3-Embedding-8B";
                revision = "1d8ad4ca9b3dd8059ad90a75d4983776a23d44af";
              };
              hfUrl = "https://huggingface.co/Qwen/Qwen3-Embedding-8B-GGUF";
              revision = "69d0e58a13e463cd99a9b83e3f5fee7c10265fab";
              path = "Qwen3-Embedding-8B-Q5_0.gguf";
              bytes = 5291991360;
              oid = "5de04c970746c64ddd21434a5eb21ff10a2ec247c9e78ef6d48e73a81c3672ce";
              hash = "sha256-XeBMlwdGxk3dIUNKXrIf8QouwkfJ54721I5zqBw2cs4=";
              notes = "Q5_0 is the executable academic-rag configuration; this resolves the stale q8_0 label found in older ledgers.";
            };
          };

          deployments = {
            flm-gemma4-it-e4b = {
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
              notes = "Small/fast utility lane. FastFlowLM owns these weights via runtime flm pull; callers still enter through llama-swap.";
            };

            qwen36-35b-a3b-mxfp4 = {
              model = "qwen3.6-35b-a3b";
              role = "general";
              status = "canonical";
              backend = "vulkan";
              hosts = [
                "coordinator"
                "worker"
              ];
              ramTierGb = 24;
              artifacts.model = "qwen36-35b-a3b-mxfp4";
              runtime = llamaCppRuntime commonLlamaArgs;
              benchmark = {
                sourceRepo = "https://github.com/boxwrench/tesla_agent";
                sourceCommit = "6b7881275e967982e4cd8268655f53de1c972bef";
                runId = "stable/2026-06-02:qwen36-35b-mxfp4";
                name = "CODE/general workhorse";
                score = "82/84; nonce gate 3/3";
                speed = "58.5 tok/s decode; 932.1 tok/s prefill";
                context = "Vulkan/RADV stable lane";
              };
              evidence = "upstream-measured";
              hardware = "Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
              notes = "Default daily text generator; exact HF bitstream matches the benchmark manifest.";
            };

            qwen3-coder-next-ud-q4-k-xl = {
              model = "qwen3-coder-next";
              role = "coding";
              status = "canonical";
              backend = "vulkan";
              hosts = [
                "coordinator"
                "worker"
              ];
              ramTierGb = 52;
              artifacts.model = "qwen3-coder-next-ud-q4-k-xl";
              runtime = llamaCppRuntime commonLlamaArgs;
              benchmark = {
                sourceRepo = "https://github.com/boxwrench/tesla_agent";
                sourceCommit = "6b7881275e967982e4cd8268655f53de1c972bef";
                runId = "stable/2026-06-02:qwen3-coder-next-vulkan";
                name = "orchestrated four-stage coding run";
                score = "all grader checks PASS; nonce gate 3/3";
                speed = "44.4 tok/s decode; 723.2 tok/s prefill";
                context = "reasoning off; Vulkan/RADV";
              };
              evidence = "upstream-measured";
              hardware = "Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
              notes = "Purpose-built first member of the coding-opinion pool.";
            };

            qwopus36-27b-v2-q5-k-m = {
              model = "qwopus3.6-27b-v2";
              role = "coding";
              status = "canonical";
              backend = "vulkan";
              hosts = [
                "coordinator"
                "worker"
              ];
              ramTierGb = 22;
              artifacts.model = "qwopus36-27b-v2-q5-k-m";
              runtime = llamaCppRuntime commonLlamaArgs;
              benchmark = {
                sourceRepo = "https://github.com/ciru-ai/benchmarks";
                sourceCommit = "202072d2227d2452e0c41f26f7b05d2491eab44e";
                runId = "20260527T065900Z-standard-coding-test-medium";
                name = "BigCodeBench-Hard instruct";
                score = "42/148 pass@1";
                context = "profile qwopus3.6-27b-v2-q5-k-m";
              };
              evidence = "upstream-measured";
              hardware = "Ciru Strix Halo benchmark host";
              notes = "Fine-tuned second coding opinion; preserve as a separate row from stock Qwen3.6 27B.";
            };

            gemma4-26b-a4b-qat-mtp = {
              model = "gemma4-26b-a4b-qat";
              role = "coding";
              status = "canonical";
              backend = "vulkan";
              hosts = [
                "coordinator"
                "worker"
              ];
              ramTierGb = 18;
              artifacts = {
                model = "gemma4-26b-a4b-qat-q4-0";
                mtpHead = "gemma4-26b-a4b-qat-mtp-q4-0";
              };
              runtime = llamaCppRuntime (
                commonLlamaArgs
                ++ [
                  "--spec-draft-model"
                  "@mtpHead@"
                  "--spec-type"
                  "draft-mtp"
                  "--spec-draft-n-max"
                  "4"
                ]
              );
              evidence = "unverified";
              hardware = "Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
              notes = "Cross-family coding-panel member. Google replaced the measured GGUF with a corrected-vocabulary bitstream; rerun the matched local quality/speed witness before lifting the gate.";
            };

            deepseek-v4-flash-q4-dual = {
              model = "deepseek-v4-flash";
              role = "quality";
              status = "canonical";
              backend = "ds4";
              hosts = [
                "coordinator"
                "worker"
              ];
              ramTierGb = 128;
              artifacts = {
                model = "deepseek-v4-flash-q4-imatrix";
                mtpHead = "deepseek-v4-flash-mtp";
              };
              runtime = {
                repository = "https://github.com/ejpir/ds4-hip";
                commit = "3490c2e46c91331323dc0f2bfb7d3018e227fdff";
                args = [
                  "--mtp"
                  "@mtpHead@"
                  "--mtp-draft"
                  "1"
                  "--ctx"
                  "131072"
                ];
              };
              benchmark = {
                sourceRepo = "https://github.com/mecattaf/dotfiles";
                sourceCommit = "96fba30a6465d411ec8fee7b4bf5d5cb0d82432f";
                runId = "legacy-ds4-dual-node-lessons";
                name = "matched dual-node completion";
                speed = "approximately 11 tok/s generation";
                context = "Q4 imatrix + MTP; coordinator 0:21, worker 22:output";
              };
              evidence = "matched-local";
              hardware = "two Ryzen AI MAX+ 395 nodes over point-to-point Thunderbolt";
              notes = "SOTA escalation lane. The artifact identity is final, but the current generic renderer does not yet encode coordinator/worker layer roles; downloadAllModels must remain false until fleet orchestration is added.";
            };

            qwen36-35b-abliterated-heretic = {
              model = "qwen3.6-35b-heretic";
              role = "uncensored";
              status = "canonical";
              backend = "vulkan";
              hosts = [ "worker" ];
              ramTierGb = 24;
              artifacts.model = "qwen36-35b-a3b-abliterated-heretic-q4-k-m";
              runtime = llamaCppRuntime commonLlamaArgs;
              evidence = "unverified";
              hardware = "worker Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
              notes = "Manual high-recall hypothesis generator only; never an arbiter and excluded from automatic routing.";
            };

            supergemma4-26b-uncensored = {
              model = "supergemma4-26b-uncensored";
              role = "uncensored";
              status = "canonical";
              backend = "vulkan";
              hosts = [ "worker" ];
              ramTierGb = 20;
              artifacts.model = "supergemma4-26b-uncensored-q4-k-m";
              runtime = llamaCppRuntime commonLlamaArgs;
              benchmark = {
                sourceRepo = "https://github.com/ciru-ai/benchmarks";
                sourceCommit = "202072d2227d2452e0c41f26f7b05d2491eab44e";
                runId = "20260413-143959-supergemma4-26b-uncensored-fast-v2-q4-km-p16384";
                name = "llama-bench tg128";
                speed = "66.07 tok/s decode";
                context = "Vulkan; F16 KV; 16K prompt companion row";
              };
              evidence = "upstream-measured";
              hardware = "Ciru Strix Halo benchmark host";
              notes = "Different model family and tuning path from the Heretic row; manual use only.";
            };

            glm47-flash-uncensored-aggressive = {
              model = "glm-4.7-flash-uncensored";
              role = "uncensored";
              status = "canonical";
              backend = "vulkan";
              hosts = [ "worker" ];
              ramTierGb = 22;
              artifacts.model = "glm47-flash-uncensored-aggressive-q4-k-m";
              runtime = llamaCppRuntime (
                commonLlamaArgs
                ++ [
                  "--temp"
                  "1.0"
                  "--top-p"
                  "0.95"
                  "--repeat-penalty"
                  "1.0"
                  "--min-p"
                  "0.01"
                ]
              );
              evidence = "unverified";
              hardware = "worker Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
              notes = "Non-Heretic aggressive refusal-removal route for method and training-family diversity; manual use only.";
            };

            qwen3-vl-8b-ocr = {
              model = "qwen3-vl-8b-ocr";
              role = "vision";
              status = "canonical";
              backend = "rocm";
              hosts = [ "worker" ];
              ramTierGb = 12;
              artifacts = {
                model = "qwen3-vl-8b-instruct-q8-0";
                mmproj = "qwen3-vl-8b-mmproj-bf16";
              };
              runtime = llamaCppRuntime [
                "--mmproj"
                "@mmproj@"
                "--ctx-size"
                "8192"
                "--gpu-layers"
                "999"
                "--flash-attn"
                "on"
                "--no-mmap"
              ];
              benchmark = {
                sourceRepo = "https://github.com/mecattaf/academic-rag";
                sourceCommit = "8a8b7be17182eace57ffa64de1e5ac6049e4fe37";
                runId = "eval-2026-06-22:qwen3vl-q8";
                name = "38-page OCR/VLM subset";
                score = "judge 9.0/10; jaccard 0.870";
                speed = "approximately 52 s/page";
                context = "llama.cpp ROCm; Q8_0 + BF16 projector";
              };
              evidence = "matched-local";
              hardware = "worker Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
              notes = "Primary academic-document drainer.";
            };

            qwen3-vl-32b-ocr-refine = {
              model = "qwen3-vl-32b-ocr";
              role = "vision";
              status = "canonical";
              backend = "rocm";
              hosts = [ "worker" ];
              ramTierGb = 24;
              artifacts = {
                model = "qwen3-vl-32b-instruct-q4-k-m";
                mmproj = "qwen3-vl-32b-mmproj-bf16";
              };
              runtime = llamaCppRuntime [
                "--mmproj"
                "@mmproj@"
                "--ctx-size"
                "8192"
                "--gpu-layers"
                "999"
                "--flash-attn"
                "on"
                "--no-mmap"
              ];
              benchmark = {
                sourceRepo = "https://github.com/mecattaf/academic-rag";
                sourceCommit = "8a8b7be17182eace57ffa64de1e5ac6049e4fe37";
                runId = "eval-2026-06-22:qwen3vl-32b";
                name = "table/math reconciliation pass";
                score = "selected table-fidelity winner";
                context = "llama.cpp ROCm; Q4_K_M + BF16 projector";
              };
              evidence = "matched-local";
              hardware = "worker Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
              notes = "Targeted second pass for table- and math-heavy pages, not the default drainer.";
            };

            qwen3-embedding-8b-q5-0 = {
              model = "qwen3-embedding-8b";
              role = "embedding";
              status = "canonical";
              backend = "rocm";
              hosts = [ "worker" ];
              ramTierGb = 8;
              artifacts.model = "qwen3-embedding-8b-q5-0";
              runtime = llamaCppRuntime [
                "--embeddings"
                "--pooling"
                "last"
                "--ctx-size"
                "8192"
                "--gpu-layers"
                "999"
                "--no-mmap"
              ];
              evidence = "matched-local";
              hardware = "worker Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
              notes = "Embedding companion for the OCR/RAG appliance; retain Q5_0 to match the executable pipeline configuration.";
            };
          };
        };
      }
    ];
  };
in
{
  inherit backendKinds;
  inherit (evaluated.config) artifacts deployments;
}
