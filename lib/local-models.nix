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

            fara15-27b-q8-0 = mkSingleFileArtifact {
              maker = "Microsoft / bartowski";
              baseCheckpoint = {
                url = "https://huggingface.co/microsoft/Fara1.5-27B";
                revision = "448c9aed38954323b05042783e43f1a15979b3c3";
              };
              hfUrl = "https://huggingface.co/bartowski/Fara1.5-27B-GGUF";
              revision = "dd7cba968d1a9c8feab0c2b85d93b117e6cc16fe";
              path = "Fara1.5-27B-Q8_0.gguf";
              bytes = 28665067328;
              oid = "77578ded07b855c90b154abbb3c1c7f4669b29fa19afc27412a2940a51cf634d";
              hash = "sha256-d1eN7Qe4VckLFUq7s8HH9GabKfoZr8J0EqKUClHPY00=";
              notes = "Q8_0 is an explicit operator choice for the browser-computer-use appliance; do not silently down-quantize it.";
            };

            fara15-27b-mmproj-bf16 = mkSingleFileArtifact {
              kind = "mmproj";
              maker = "Microsoft / bartowski";
              baseCheckpoint = {
                url = "https://huggingface.co/microsoft/Fara1.5-27B";
                revision = "448c9aed38954323b05042783e43f1a15979b3c3";
              };
              hfUrl = "https://huggingface.co/bartowski/Fara1.5-27B-GGUF";
              revision = "dd7cba968d1a9c8feab0c2b85d93b117e6cc16fe";
              path = "mmproj-Fara1.5-27B-bf16.gguf";
              bytes = 931146400;
              oid = "20f332c2723575797d9ba07cf09a2ca019c89409e4ee250f91305279b19b2bea";
              hash = "sha256-IPMywnI1dXl9m6B88JosoBnIlAnk7iUPkTBSebGbK+o=";
              notes = "BF16 vision projector paired with the Q8_0 Fara deployment.";
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

            vibevoice-qwen25-7b-tokenizer = {
              kind = "tokenizer";
              maker = "Qwen";
              notes = "Pinned tokenizer payload required by both VibeVoice appliances; the ASR integration derives its extra audio-token metadata from these files.";
              source = {
                hfUrl = "https://huggingface.co/Qwen/Qwen2.5-7B";
                revision = "d149729398750b98c0af14eb82c78cfe92750796";
                primary = "tokenizer.json";
                files = [
                  {
                    path = "merges.txt";
                    bytes = 1671839;
                    oid = "599bab54075088774b1733fde865d5bd747cbcc7a547c5bc12610e874e26f5e3";
                    hash = "sha256-WZurVAdQiHdLFzP96GXVvXR8vMelR8W8EmEOh04m9eM=";
                  }
                  {
                    path = "tokenizer.json";
                    bytes = 7031645;
                    oid = "c0382117ea329cdf097041132f6d735924b697924d6f6fc3945713e96ce87539";
                    hash = "sha256-wDghF+oynN8JcEETL21zWSS2l5JNb2/DlFcT6WzodTk=";
                  }
                  {
                    path = "tokenizer_config.json";
                    bytes = 7228;
                    oid = "c91efca15ceff6e9ee9424db58a6f59cd41294e550a86cbd07e3c1fb500b34f9";
                    hash = "sha256-yR78oVzv9unulCTbWKb1nNQSlOVQqGy9B+PB+1ALNPk=";
                  }
                  {
                    path = "vocab.json";
                    bytes = 2776833;
                    oid = "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910";
                    hash = "sha256-yhDX6fs+0YV13R4neiV5wW0QjjLydDloSvoOELFECRA=";
                  }
                ];
              };
            };

            vibevoice-asr-bf16 = {
              kind = "model";
              maker = "Microsoft";
              notes = "Full BF16 long-form ASR, timestamping, and diarization snapshot; coordinator-only appliance artifact.";
              source = {
                hfUrl = "https://huggingface.co/microsoft/VibeVoice-ASR";
                revision = "d0c9efdb8d614685062c04425d91e01b6f37d944";
                primary = "config.json";
                files = [
                  {
                    path = "config.json";
                    bytes = 3520;
                    oid = "1798906d016a625ffa0100182cad152e055bfee53fb228a45ffe25d8179b9b24";
                    hash = "sha256-F5iQbQFqYl/6AQAYLK0VLgVb/uU/siikX/4l2BebmyQ=";
                  }
                  {
                    path = "model.safetensors.index.json";
                    bytes = 120151;
                    oid = "1468c7b7c74fe27831d8db57871fbf15efd270c747f3f99caf689119ace658ba";
                    hash = "sha256-FGjHt8dP4ngx2NtXhx+/Fe/ScMdH8/mcr2iRGazmWLo=";
                  }
                  {
                    path = "model-00001-of-00008.safetensors";
                    bytes = 2488346272;
                    oid = "5548c67885d423ba184bc8c33f2e9f81b582a6d119cef79907e19a274b916637";
                    hash = "sha256-VUjGeIXUI7oYS8jDPy6fgbWCptEZzveZB+GaJ0uRZjc=";
                  }
                  {
                    path = "model-00002-of-00008.safetensors";
                    bytes = 2389315976;
                    oid = "163023c61a3fb047745cbaf53ed41c1e27e515e9786a376e122bfac2ea6e687e";
                    hash = "sha256-FjAjxho/sEd0XLr1PtQcHiflFel4ajduEiv6wupuaH4=";
                  }
                  {
                    path = "model-00003-of-00008.safetensors";
                    bytes = 2466376368;
                    oid = "4e021702dfac2c52e8fdd6688de82c118be7bb7ad9b5c7988725ec63c44a64fb";
                    hash = "sha256-TgIXAt+sLFLo/dZojegsEYvnu3rZtceYhyXsY8RKZPs=";
                  }
                  {
                    path = "model-00004-of-00008.safetensors";
                    bytes = 2466376400;
                    oid = "b17657bb151daa117a5a4671374ac1b248acb696691a2a67ac227a1115925e30";
                    hash = "sha256-sXZXuxUdqhF6WkZxN0rBskistpZpGipnrCJ6ERWSXjA=";
                  }
                  {
                    path = "model-00005-of-00008.safetensors";
                    bytes = 2499431136;
                    oid = "0ed4e457268f7b02dda5cffe16b3a32614ccc2ccfe5de2db39bdd79700836406";
                    hash = "sha256-DtTkVyaPewLdpc/+FrOjJhTMwsz+XeLbOb3XlwCDZAY=";
                  }
                  {
                    path = "model-00006-of-00008.safetensors";
                    bytes = 2483469928;
                    oid = "6de8246bb042fd853b57d40995efd289ea44e4d1b611cec2e122570b8d2122bd";
                    hash = "sha256-begka7BC/YU7V9QJle/SiepE5NG2Ec7C4SJXC40hIr0=";
                  }
                  {
                    path = "model-00007-of-00008.safetensors";
                    bytes = 1464887482;
                    oid = "a2ba6960d994dc7598efc6796f85ab097da7708f4dd56095f7fccf4df8dc00e5";
                    hash = "sha256-orppYNmU3HWY78Z5b4WrCX2ncI9N1WCV9/zPTfjcAOU=";
                  }
                  {
                    path = "model-00008-of-00008.safetensors";
                    bytes = 1089994848;
                    oid = "1b9d9b328f85a25b4efca712d31513c6eed9e178152cc8cf4a6f0c2cd2bb623f";
                    hash = "sha256-G52bMo+FoltO/KcS0xUTxu7Z4XgVLMjPSm8MLNK7Yj8=";
                  }
                ];
              };
            };

            vibevoice-large-bf16 = {
              kind = "model";
              maker = "Microsoft / aoi-ot mirror";
              notes = "Full BF16 long-form multi-speaker TTS snapshot; coordinator-only with the mirror provenance warning retained.";
              source = {
                hfUrl = "https://huggingface.co/aoi-ot/VibeVoice-Large";
                revision = "1b81fecc784a076dcd935678db551871f4598ebf";
                primary = "config.json";
                files = [
                  {
                    path = "config.json";
                    bytes = 2785;
                    oid = "695598158e43b44227bc7aa6fd851e410f7ce30b21a5ea5c3fe22983961e500a";
                    hash = "sha256-aVWYFY5DtEInvHqm/YUeQQ984wshpepcP+Ipg5YeUAo=";
                  }
                  {
                    path = "configuration.json";
                    bytes = 72;
                    oid = "30458d769bcf25aa4e8fd30bbde901f817e382a49f7c7da8c4380dd97b616876";
                    hash = "sha256-MEWNdpvPJapOj9MLvekB+BfjgqSffH2oxDgN2XthaHY=";
                  }
                  {
                    path = "preprocessor_config.json";
                    bytes = 349;
                    oid = "5a26081a18cd60f48d7ed36b904e68c24271ba9711d6328b53f7ad3eed446cce";
                    hash = "sha256-WiYIGhjNYPSNftNrkE5owkJxupcR1jKLU/etPu1EbM4=";
                  }
                  {
                    path = "model.safetensors.index.json";
                    bytes = 122675;
                    oid = "dbcfc6e307494bc87684471872f3d8b785cb68b3589b6b306c43fde629b88ebd";
                    hash = "sha256-28/G4wdJS8h2hEcYcvPYt4XLaLNYm2swbEP95im4jr0=";
                  }
                  {
                    path = "model-00001-of-00010.safetensors";
                    bytes = 1886424044;
                    oid = "ae28d5c8f3587b518c7e371e96ebb69f74d854a854119acf433952bbc1926325";
                    hash = "sha256-rijVyPNYe1GMfjceluu2n3TYVKhUEZrPQzlSu8GSYyU=";
                  }
                  {
                    path = "model-00002-of-00010.safetensors";
                    bytes = 1864468520;
                    oid = "c56b1ca707e31e435ded8b03baa4938d88275bf0ba7033935a16d8173a99ff85";
                    hash = "sha256-xWscpwfjHkNd7YsDuqSTjYgnW/C6cDOTWhbYFzqZ/4U=";
                  }
                  {
                    path = "model-00003-of-00010.safetensors";
                    bytes = 1864468520;
                    oid = "48bfb4af453d45e488050e90d3f39da0189f1c10a77d75223c2c2ced8b035baa";
                    hash = "sha256-SL+0r0U9ReSIBQ6Q0/OdoBifHBCnfXUiPCws7YsDW6o=";
                  }
                  {
                    path = "model-00004-of-00010.safetensors";
                    bytes = 1864468544;
                    oid = "b4893be477be68e53b8a9616422b99065f3d1431cce9efe0a1653495e9cf4df6";
                    hash = "sha256-tIk75He+aOU7ipYWQiuZBl89FDHM6e/goWU0lenPTfY=";
                  }
                  {
                    path = "model-00005-of-00010.safetensors";
                    bytes = 1864468568;
                    oid = "471690e9846e791def400fefa3d2103c9839dc8a3e987b175f6539c7412422d6";
                    hash = "sha256-RxaQ6YRueR3vQA/vo9IQPJg53Io+mHsXX2U5x0EkItY=";
                  }
                  {
                    path = "model-00006-of-00010.safetensors";
                    bytes = 1864468568;
                    oid = "a7918d400ba895b15a1126fde242028e5d05b37bab0c0427944de81df80f901f";
                    hash = "sha256-p5GNQAuolbFaESb94kICjl0Fs3urDAQnlE3oHfgPkB8=";
                  }
                  {
                    path = "model-00007-of-00010.safetensors";
                    bytes = 1864468568;
                    oid = "b4f00ebea5a9f76eea891b3457621955433149ae603d921afa1498e46683ba37";
                    hash = "sha256-tPAOvqWp927qiRs0V2IZVUMxSa5gPZIa+hSY5GaDujc=";
                  }
                  {
                    path = "model-00008-of-00010.safetensors";
                    bytes = 1972552744;
                    oid = "cc4b6fce97b76e847c742b59ab9463fd04b6d9fa69fc33e747ff722c2ab8cc28";
                    hash = "sha256-zEtvzpe3boR8dCtZq5Rj/QS22fpp/DPnR/9yLCq4zCg=";
                  }
                  {
                    path = "model-00009-of-00010.safetensors";
                    bytes = 1959739938;
                    oid = "824db8970518950117f0d6ed859740d973b9436718c24f29bc78854c4587a4b2";
                    hash = "sha256-gk24lwUYlQEX8NbthZdA2XO5Q2cYwk8pvHiFTEWHpLI=";
                  }
                  {
                    path = "model-00010-of-00010.safetensors";
                    bytes = 1681341960;
                    oid = "bc76bba7a46a0a748cc169efb6ccfb7617881e0fc3b533f67887d5957e1836e3";
                    hash = "sha256-vHa7p6RqCnSMwWnvtsz7dheIHg/DtTP2eIfVlX4YNuM=";
                  }
                ];
              };
            };
          };

          deployments = {
            flm-gemma4-it-e4b = {
              model = "gemma4-it:e4b";
              role = "utility";
              status = "canonical";
              backend = "npu";
              hosts = [
                "coordinator"
                "worker"
              ];
              runtime = {
                repository = "https://github.com/FastFlowLM/FastFlowLM";
                commit = "fd371409897d7c0abb4de4dbc5098b9b43c094ff";
              };
              peer = {
                name = "flm-gemma4";
                proxy = "http://127.0.0.1:52625";
                systemdUnit = "flm-serve-gemma4-it-e4b.service";
              };
              evidence = "matched-local";
              hardware = "Strix Halo XDNA2 NPU; amdxdna/XRT from nix-amd-ai";
              notes = "Multimodal utility lane on both Strix hosts. FastFlowLM owns these weights via runtime flm pull; callers still enter through llama-swap.";
            };

            flm-gpt-oss-20b = {
              model = "gpt-oss:20b";
              role = "utility";
              status = "canonical";
              backend = "npu";
              hosts = [
                "coordinator"
                "worker"
              ];
              runtime = {
                repository = "https://huggingface.co/FastFlowLM/GPT-OSS-20B-NPU2";
                commit = "12ce92d2bfa031761ab876b3b845a7dabeab1d98";
              };
              peer = {
                name = "flm-gpt-oss";
                proxy = "http://127.0.0.1:52626";
                systemdUnit = "flm-serve-gpt-oss-20b.service";
              };
              evidence = "api-only";
              hardware = "Strix Halo XDNA2 NPU; amdxdna/XRT from nix-amd-ai";
              notes = "Second NPU reasoning lane on both Strix hosts; FastFlowLM tag gpt-oss:20b, Q4_1 NPU2 snapshot.";
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

            fara15-27b-q8-0 = {
              model = "fara1.5-27b";
              role = "vision";
              status = "canonical";
              backend = "rocm";
              hosts = [
                "coordinator"
                "worker"
              ];
              ramTierGb = 32;
              artifacts = {
                model = "fara15-27b-q8-0";
                mmproj = "fara15-27b-mmproj-bf16";
              };
              runtime = llamaCppRuntime [
                "--mmproj"
                "@mmproj@"
                "--ctx-size"
                "32768"
                "--gpu-layers"
                "999"
                "--flash-attn"
                "on"
                "--no-mmap"
                "--jinja"
              ];
              evidence = "unverified";
              hardware = "Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
              notes = "Browser-computer-use VLM on both Strix hosts. Q8_0 is an explicit quality decision; the BF16 projector is mandatory.";
            };

            deepseek-v4-flash-q4-dual = {
              model = "deepseek-v4-flash";
              role = "quality";
              status = "retired";
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
              notes = "Retired with the physical dual-node topology on 2026-07-26. Historical artifact, runtime, and benchmark evidence remain reproducible, but this row is no longer projected to either host, so its roughly 157 GiB of weights are not materialized even if downloadAllModels is later enabled. The DS4 runtime package remains installed.";
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
              hosts = [ "coordinator" ];
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
              hardware = "coordinator Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
              notes = "Primary academic-document drainer.";
            };

            qwen3-vl-32b-ocr-refine = {
              model = "qwen3-vl-32b-ocr";
              role = "vision";
              status = "canonical";
              backend = "rocm";
              hosts = [ "coordinator" ];
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
              hardware = "coordinator Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
              notes = "Targeted second pass for table- and math-heavy pages, not the default drainer.";
            };

            qwen3-embedding-8b-q5-0 = {
              model = "qwen3-embedding-8b";
              role = "embedding";
              status = "canonical";
              backend = "rocm";
              hosts = [ "coordinator" ];
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
              hardware = "coordinator Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
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
