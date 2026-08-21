{ lib }:

let
  inherit (lib) mkOption types;

  backendKinds = import ./local-model-backends.nix;
  mageArtifacts = import ./mage-models.nix;
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
      quantization ? null,
      notes ? "",
    }:
    {
      inherit
        kind
        maker
        baseCheckpoint
        fineTune
        quantization
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

  # One canonical application-facing utility slot.  Consumers name only
  # stableId; services.npu-llm owns the request-scoped rewrite to this
  # FastFlowLM deployment.
  utility = {
    stableId = "utility";
    deployment = "flm-qwen3-4b-utility";
    contextTokens = 32768;
  };

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
        type = types.ints.unsigned;
        description = "Exact byte size.";
      };
      oid = mkOption {
        type = types.str;
        description = "Exact content SHA-256 (the upstream LFS OID when present).";
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
          "draft"
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
        layout = mkOption {
          type = types.enum [
            "flat"
            "snapshot"
          ];
          default = "flat";
          description = ''
            Flat artifacts expose files by basename for single-file runtimes.
            Snapshot artifacts preserve the Hugging Face repository tree for
            Transformers and Diffusers loaders.
          '';
        };
        localName = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Optional upstream-compatible directory name exposed below
            /etc/local-models/snapshots for loaders that select sibling
            checkpoints by repository basename.
          '';
        };
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
      quantization = mkOption {
        type = nullableString;
        default = null;
        description = ''
          Declared weight precision for model and MTP GGUFs. Runtime-owned
          model snapshots and non-weight sidecars leave this null.
        '';
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
      # Separate small-model speculative drafter (a full GGUF, not an MTP
      # block), e.g. Gemma 4 E2B drafting for the 31B dense model.
      draft = mkOption {
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
        description = "Public model ID exposed by the selected runtime.";
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
      # Archive receipt: where the weights physically survive after retirement
      # (NAS archive path + date). A `retired` row without one fails eval —
      # asserted in modules/local-models.nix — so "I meant to archive it"
      # becomes a build failure, not a regret. Convention set 2026-08-20 after
      # exactly that regret; runbook: docs/nas/model-archive.md.
      archived = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      backend = mkOption {
        type = types.enum (backendKinds.local ++ backendKinds.appliances);
      };
      hosts = mkOption {
        # Widened beyond ["coordinator"] for the worker-node reintegration
        # (dotfiles#229). As of 2026-08-21 hosts/worker is back in the flake and
        # modules/strix.nix selects its rows, so worker-assigned entries are LIVE
        # rather than aspirational — a row named here is a row that materializes.
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
      ttl = mkOption {
        type = types.ints.unsigned;
        default = 600;
        description = ''
          Idle seconds before llama-swap unloads the model (per-model ttl,
          overriding the deliberate globalTTL = 0). The timer is
          last-request-based and never fires with a request in flight, so
          Tally-admitted batch jobs are only affected if they go quiet for
          longer than this window — and then pay one transparent cold reload,
          not an error (#149). 0 opts a deployment back into
          resident-until-restart.
        '';
      };
      artifacts = mkOption {
        type = artifactRefsType;
        default = { };
      };
      runtime = mkOption { type = runtimeType; };
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
          # This is a metadata roster. modules/strix.nix roots only its explicit
          # per-host allowlists, so catalog candidates never download merely by
          # existing here.
          artifacts = mageArtifacts // {
            qwen36-35b-a3b-mtp-ud-q8-k-xl = mkSingleFileArtifact {
              maker = "Qwen";
              baseCheckpoint = {
                url = "https://huggingface.co/Qwen/Qwen3.6-35B-A3B";
                revision = "995ad96eacd98c81ed38be0c5b274b04031597b0";
              };
              hfUrl = "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF";
              revision = "5bc3e238d916f48a861bac2f8a1990a0e9b7e98d";
              path = "Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf";
              bytes = 39099447584;
              oid = "6c6b816537abad90b250a0972b345466028d861ddfe316d5f0de31ca6440f781";
              hash = "sha256-bGuBZTerrZCyUKCXKzRUZgKNhh3f4xbV8N4xymRA94E=";
              quantization = "UD-Q8_K_XL";
              notes = "Operator-selected high-fidelity Q8 tier with a matched MTP block integrated in the same GGUF.";
            };

            qwen36-27b-mtp-ud-q8-k-xl = mkSingleFileArtifact {
              maker = "Qwen";
              baseCheckpoint = {
                url = "https://huggingface.co/Qwen/Qwen3.6-27B";
                revision = "6a9e13bd6fc8f0983b9b99948120bc37f49c13e9";
              };
              hfUrl = "https://huggingface.co/unsloth/Qwen3.6-27B-MTP-GGUF";
              revision = "5cb35eb3dcbf52dbce5f87dbc64df6aaffadcace";
              path = "Qwen3.6-27B-UD-Q8_K_XL.gguf";
              bytes = 35776484480;
              oid = "3d6ff16be3258f910eac4dcec7142edc7a7100d8400fe363035c8cfedc151164";
              hash = "sha256-PW/xa+Mlj5EOrE3OxxQu3HpxANhAD+NjA1yM/twVEWQ=";
              quantization = "UD-Q8_K_XL";
              notes = "Stock Qwen checkpoint, not a fine-tune; operator-selected high-fidelity Q8 tier with its matched MTP block integrated in the GGUF.";
            };

            qwen38-27b-q8-0 = mkSingleFileArtifact {
              maker = "Qwen";
              baseCheckpoint = {
                url = "https://huggingface.co/Qwen/Qwen3.8-27B";
                revision = "1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0";
              };
              hfUrl = "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF";
              revision = "27af057ecb382ddfea5d12837360a8980560e3ed";
              path = "Qwen3.8-27B-Q8_0.gguf";
              bytes = 29047086048;
              oid = "a680f44a06920e5d689774823782006aa3acc8db95750323373b24139b67e348";
              hash = "sha256-poD0SgaSDl1ol3SCN4IAaqOsyNuVdQMjNzskE5tn40g=";
              quantization = "Q8_0";
              notes = "Qwen MELS lane primary (#229). Q8-for-fidelity ruling; thinking is capped per-lane in the deployment because the model defaults to unbounded reasoning (evidence: 6-12K plateau, >12K pays up to 4.5x for nothing).";
            };

            qwen38-27b-mtp-q4-0 = mkSingleFileArtifact {
              kind = "mtp-head";
              maker = "Qwen / Unsloth";
              baseCheckpoint = {
                url = "https://huggingface.co/Qwen/Qwen3.8-27B";
                revision = "1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0";
              };
              hfUrl = "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF";
              revision = "27af057ecb382ddfea5d12837360a8980560e3ed";
              path = "MTP/mtp-Qwen3.8-27B-Q4_0.gguf";
              bytes = 1369590656;
              oid = "50d9ce5a6da381bbcfb31061cf73df94a90e6faf8efeddee379a9cb8f1501c6e";
              hash = "sha256-UNnOWm2jgbvPsxBhz3PflKkOb6+O/t3uN5qcuPFQHG4=";
              quantization = "Q4_0";
              notes = "Q4_0 is the only MTP asset the quantizer publishes for this model; the base stays Q8_0.";
            };

            qwen38-27b-dflash2 = {
              kind = "draft";
              maker = "Inco AI";
              baseCheckpoint = {
                url = "https://huggingface.co/Qwen/Qwen3.8-27B";
                revision = "1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0";
              };
              notes = "DFlash2 speculative drafter for Qwen 3.8 27B, safetensors as shipped (vLLM/SGLang mainline; llama.cpp needs a GGUF conversion or the draft-dflash path). Declared for the serving-path decision in ACTION-PLAN §8.2; not yet referenced by a deployment.";
              source = {
                layout = "snapshot";
                hfUrl = "https://huggingface.co/incoai/Qwen3.8-27B-DFlash2";
                revision = "dedf8df68adfb1afeaf7b7480c0a0243108177b4";
                primary = "model.safetensors";
                files = [
                  {
                    path = "config.json";
                    bytes = 1239;
                    oid = "873e3556509b0da06e29654ba00d4944888d4b5e8a33afde25f7eb27d321e980";
                    hash = "sha256-hz41VlCbDaBuKWVLoA1JRIiNS16KM6/eJffrJ9Mh6YA=";
                  }
                  {
                    path = "model.safetensors";
                    bytes = 3848817896;
                    oid = "67fc76d68dc5a9415511a4f394ef744d67510cd20e93b37cc2cc7d28e4bab65c";
                    hash = "sha256-Z/x21o3FqUFVEaTzlO90TWdRDNIOk7N8wsx9KOS6tlw=";
                  }
                ];
              };
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

            gemma4-26b-a4b-it-q8-0 = mkSingleFileArtifact {
              maker = "Google / Unsloth";
              baseCheckpoint = {
                url = "https://huggingface.co/google/gemma-4-26B-A4B-it";
                revision = "4d7ae4984b7db7de8f8457170b3f1a419ee76d52";
              };
              hfUrl = "https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF";
              revision = "c099eb48e663fd284577b04978a94ffccb261841";
              path = "gemma-4-26B-A4B-it-Q8_0.gguf";
              bytes = 26859861728;
              oid = "5f7cbd0f4564e84342fc34321a09acb54b1a3da9215124e5bf444baa6dda152c";
              hash = "sha256-X3y9D0Vk6ENC/DQyGgmstUsaPakhUSTlv0RLqm3aFSw=";
              quantization = "Q8_0";
              notes = "Non-QAT instruction checkpoint selected because Google's QAT release is Q4_0-only.";
            };

            gemma4-26b-a4b-it-mtp-q8-0 = mkSingleFileArtifact {
              kind = "mtp-head";
              maker = "Google / Unsloth";
              baseCheckpoint = {
                url = "https://huggingface.co/google/gemma-4-26B-A4B-it";
                revision = "4d7ae4984b7db7de8f8457170b3f1a419ee76d52";
              };
              hfUrl = "https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF";
              revision = "c099eb48e663fd284577b04978a94ffccb261841";
              path = "MTP/mtp-gemma-4-26B-A4B-it-Q8_0.gguf";
              bytes = 461766816;
              oid = "6326fb9f5e487aa8dcdd313a091e3c67724cb2a666ec3b7d2895b5b26d93ed1b";
              hash = "sha256-Yyb7n15Ieqjc3TE6CR48Z3JMsqZm7Dt9KJW1sm2T7Rs=";
              quantization = "Q8_0";
              notes = "Matched Q8 MTP head for the non-QAT Gemma 4 26B A4B instruction model.";
            };

            gemma4-31b-it-q8-0 = mkSingleFileArtifact {
              maker = "Google / Unsloth";
              baseCheckpoint = {
                url = "https://huggingface.co/google/gemma-4-31B-it";
                revision = "842da3794eaa0b77d5f08bae87a17459d91ff475";
              };
              hfUrl = "https://huggingface.co/unsloth/gemma-4-31B-it-GGUF";
              revision = "c1ac76e99d5513b141e8adde7288b85c3f9c32ec";
              path = "gemma-4-31B-it-Q8_0.gguf";
              bytes = 32635677632;
              oid = "d5808e5874e660a85ab45b2da00c9e3b4a003621249a333772232d1a703e4d67";
              hash = "sha256-1YCOWHTmYKhatFstoAyeO0oANiEkmjM3ciMtGnA+TWc=";
              quantization = "Q8_0";
              notes = "Google MELS lane heavy model, operator-pinned Q8_0 (Zetaphor benchmarked UD-Q8_K_XL — same weight class, numbers expected to transfer).";
            };

            gemma4-31b-it-mmproj-bf16 = mkSingleFileArtifact {
              kind = "mmproj";
              maker = "Google / Unsloth";
              baseCheckpoint = {
                url = "https://huggingface.co/google/gemma-4-31B-it";
                revision = "842da3794eaa0b77d5f08bae87a17459d91ff475";
              };
              hfUrl = "https://huggingface.co/unsloth/gemma-4-31B-it-GGUF";
              revision = "c1ac76e99d5513b141e8adde7288b85c3f9c32ec";
              path = "mmproj-BF16.gguf";
              bytes = 1200726496;
              oid = "7a4601b12ec680f706a7e0c7e1f78f579b1db64d485a9e352ee87d4b9daa45e4";
              hash = "sha256-ekYBsS7GgPcGp+DH4fePV5sdtk1IWp41Luh9S52qReQ=";
              notes = "Vision projector for the SEPARATE gemma4-31b-it-vl entry only: llama.cpp refuses speculative decoding with a projector loaded, so the spec-decode entry must never gain --mmproj.";
            };

            gemma4-e2b-it-draft-ud-q8-k-xl = mkSingleFileArtifact {
              kind = "draft";
              maker = "Google / Unsloth";
              baseCheckpoint = {
                url = "https://huggingface.co/google/gemma-4-E2B-it";
                revision = "3e22461f65e89153144f8adb70e3b8c2cc9845a7";
              };
              hfUrl = "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF";
              revision = "0314792d7f1f7e229411f620751375812bb9faf2";
              path = "gemma-4-E2B-it-UD-Q8_K_XL.gguf";
              bytes = 5282807904;
              oid = "ea689103802cf7edb3b3e7d606f96ee649d7e693d1bfb23a9ab507005dae4b8b";
              hash = "sha256-6miRA4As9+2zs+fWBvlu5knX5pPRv7I6mrUHAF2uS4s=";
              quantization = "UD-Q8_K_XL";
              notes = "Speculative drafter for gemma4-31b-it per the Zetaphor recipe (measured +103% avg / +139% code on this hardware class at draft-n-max 4).";
            };

            ornith-15-35b-q8-0 = mkSingleFileArtifact {
              maker = "Ornith AI";
              hfUrl = "https://huggingface.co/ornith-ai/Ornith-1.5-35B-A3B-GGUF";
              revision = "fbbaed45c2f0e200276ffa51701a24d45dc7f57e";
              path = "Ornith-1.5-35B-Q8_0.gguf";
              bytes = 37802149120;
              oid = "854cf83f80cd37a061ed86df1fa7201162e4e1fb820b91068cc12a11d2746c9e";
              hash = "sha256-hUz4P4DNN6Bh7YbfH6cgEWLk4fuCC5EGjMEqEdJ0bJ4=";
              quantization = "Q8_0";
              notes = "Cross-family finetune (Qwen 3.5 + Gemma 4 post-train, MIT); no single baseCheckpoint. Operator swapped in for Ornith 1.0 (2026-08-21 ruling) — 1.0's independently verified 72% pi-bench score does NOT transfer to 1.5. The repo also ships an mmproj (undeclared here, no ruling).";
            };

            muse-glimmer-30b-dflash2 = {
              kind = "draft";
              maker = "Inco AI";
              baseCheckpoint = {
                url = "https://huggingface.co/meta-models/Muse-Glimmer-30B";
                revision = "a4e59da52a7bc87ae7251dd5545c0dd437c44b68";
              };
              notes = "DFlash2 speculative drafter for Muse Glimmer 30B (Meta MELS lane). The BASE model is deliberately undeclared: no Q8 GGUF exists (verified 2026-08-20) and the quant envelope is Tom's open decision, ACTION-PLAN §8.1. The drafter ruling stands either way.";
              source = {
                layout = "snapshot";
                hfUrl = "https://huggingface.co/incoai/Muse-Glimmer-30B-DFlash2";
                revision = "8336acb8dc9b8bf9c25f12d7785ee6df26703119";
                primary = "model.safetensors";
                files = [
                  {
                    path = "config.json";
                    bytes = 1326;
                    oid = "cb684d6f688a22619a63ea1debe7d30c139c195bf3141fd86a763763ab34b5d9";
                    hash = "sha256-y2hNb2iKImGaY+od6+fTDBOcGVvzFB/YanY3Y6s0tdk=";
                  }
                  {
                    path = "model.safetensors";
                    bytes = 5544328424;
                    oid = "6613c1523c785a804f6bd6e9d523da8d198e3795fe35a935da380e6f01d0defa";
                    hash = "sha256-ZhPBUjx4WoBPa9bp1SPajRmON5X+Nak12jgObwHQ3vo=";
                  }
                ];
              };
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
              quantization = "Q8_0";
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

            fara15-9b-q8-0 = mkSingleFileArtifact {
              maker = "Microsoft / bartowski";
              baseCheckpoint = {
                url = "https://huggingface.co/microsoft/Fara1.5-9B";
                revision = "1a93677cd89d5601bc2ed759791e981f3a520032";
              };
              hfUrl = "https://huggingface.co/bartowski/Fara1.5-9B-GGUF";
              revision = "153cb27ac91d4a2b9391ecf278542e610d040178";
              path = "Fara1.5-9B-Q8_0.gguf";
              bytes = 9545983104;
              oid = "a2e30cca7aec006266308153ae781347505af16baa514bbd4e0e3f4a79ea3a22";
              hash = "sha256-ouMMynrsAGJmMIFTrngTR1Ba8WuqUUu9Tg4/SnnqOiI=";
              quantization = "Q8_0";
              notes = "Q8_0 is an explicit operator choice for the mid-tier browser-computer-use appliance; do not silently down-quantize it.";
            };

            fara15-9b-mmproj-bf16 = mkSingleFileArtifact {
              kind = "mmproj";
              maker = "Microsoft / bartowski";
              baseCheckpoint = {
                url = "https://huggingface.co/microsoft/Fara1.5-9B";
                revision = "1a93677cd89d5601bc2ed759791e981f3a520032";
              };
              hfUrl = "https://huggingface.co/bartowski/Fara1.5-9B-GGUF";
              revision = "153cb27ac91d4a2b9391ecf278542e610d040178";
              path = "mmproj-Fara1.5-9B-bf16.gguf";
              bytes = 921704992;
              oid = "42ff0ff38666cefc4b1594a05c1644fe9bfc49edfed587ec551e471e0dd8b61d";
              hash = "sha256-Qv8P84ZmzvxLFZSgXBZE/pv8Se3+1YfsVR5HHg3Yth0=";
              notes = "BF16 vision projector paired with the Q8_0 Fara-9B deployment.";
            };

            fara15-4b-q8-0 = mkSingleFileArtifact {
              maker = "Microsoft / bartowski";
              baseCheckpoint = {
                url = "https://huggingface.co/microsoft/Fara1.5-4B";
                revision = "776a33ae5b2ad503796a97ae20fdc66f61d2feea";
              };
              hfUrl = "https://huggingface.co/bartowski/Fara1.5-4B-GGUF";
              revision = "b97f335231e01efbbad37bb89b5310340fc10735";
              path = "Fara1.5-4B-Q8_0.gguf";
              bytes = 4493954144;
              oid = "943b76f8ff6893c465de5c841e5116941fe87c8863dbb759d386697faa723880";
              hash = "sha256-lDt2+P9ok8Rl3lyEHlEWlB/ofIhj27dZ04Zpf6pyOIA=";
              quantization = "Q8_0";
              notes = "Q8_0 is an explicit operator choice for the small browser-computer-use appliance; do not silently down-quantize it.";
            };

            fara15-4b-mmproj-bf16 = mkSingleFileArtifact {
              kind = "mmproj";
              maker = "Microsoft / bartowski";
              baseCheckpoint = {
                url = "https://huggingface.co/microsoft/Fara1.5-4B";
                revision = "776a33ae5b2ad503796a97ae20fdc66f61d2feea";
              };
              hfUrl = "https://huggingface.co/bartowski/Fara1.5-4B-GGUF";
              revision = "b97f335231e01efbbad37bb89b5310340fc10735";
              path = "mmproj-Fara1.5-4B-bf16.gguf";
              bytes = 675569312;
              oid = "703176d1c7afe714d5e323d5fbf5f62314e46c808de44d9cc99abb963039a60d";
              hash = "sha256-cDF20cev5xTV4yPV+/X2IxTkbICN5E2cyZq7ljA5pg0=";
              notes = "BF16 vision projector paired with the Q8_0 Fara-4B deployment.";
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

            deepseek-v4-flash-0731-bf16 = {
              kind = "model";
              maker = "DeepSeek";
              notes = "DeepSeek MELS judge lane: full BF16 checkpoint (~167G), REQUIRED IN FULL ON EACH BOX for the ds4-vllm-public TP=2 bring-up (ACTION-PLAN §5) — TP shards compute, not the on-disk checkpoint. Deliberately NOT in any services.local-models allow/artifacts list yet: materialization is gated on per-box disk rulings; download explicitly via nix build .#models.deepseek-v4-flash-0731-bf16. Served by vLLM/Ray as NixOS services, never as a llama-swap row. MIT.";
              source = {
                layout = "snapshot";
                localName = "DeepSeek-V4-Flash-0731";
                hfUrl = "https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash-0731";
                revision = "7872f01b1d1fe23eabc4c98b48bffcef5a386062";
                primary = "config.json";
                files = [
                  {
                    path = "config.json";
                    bytes = 1888;
                    oid = "6c8f3d2d3b48707541b88f32f22ef3f0f8a6b57d8523281e2b8d3cdb0ae9a023";
                    hash = "sha256-bI89LTtIcHVBuI8y8i7z8PimtX2FIygeK4082wrpoCM=";
                  }
                  {
                    path = "generation_config.json";
                    bytes = 170;
                    oid = "5fccff80f55a4d455bbe516bdd552edf3e9623df95e99fbf2a3c3389fdf91af0";
                    hash = "sha256-X8z/gPVaTUVbvlFr3VUu3z6WI9+V6Z+/Kjwzif35GvA=";
                  }
                  {
                    path = "model-00001-of-00048.safetensors";
                    bytes = 1059061856;
                    oid = "f3668ba4cccf1ca6a7eb84e888fb92c1cdc7204d472ba9db771e6fd3abf6b874";
                    hash = "sha256-82aLpMzPHKan64ToiPuSwc3HIE1HK6nbdx5v06v2uHQ=";
                  }
                  {
                    path = "model-00002-of-00048.safetensors";
                    bytes = 3566321192;
                    oid = "77b26c939a0e25b3113c8d6bb04e1901a748bd4a7d2589e3bfdaabdf1e9bba14";
                    hash = "sha256-d7Jsk5oOJbMRPI1rsE4ZAadIvUp9JYnjv9qr3x6buhQ=";
                  }
                  {
                    path = "model-00003-of-00048.safetensors";
                    bytes = 3566321192;
                    oid = "412abf4c906faadc221ef0cb50f90fe20bde8454a08ad4dc2364b6b79e7fda5c";
                    hash = "sha256-QSq/TJBvqtwiHvDLUPkP4gvehFSgitTcI2S2t55/2lw=";
                  }
                  {
                    path = "model-00004-of-00048.safetensors";
                    bytes = 3596229272;
                    oid = "9610f56bc587fb0ff9a8b68a60299482ee8c433fe5b5587e4257aca98add4a2e";
                    hash = "sha256-lhD1a8WH+w/5qLaKYCmUgu6MQz/ltVh+QlesqYrdSi4=";
                  }
                  {
                    path = "model-00005-of-00048.safetensors";
                    bytes = 3568768976;
                    oid = "f87a5ac7b8becc31f9c3169afd3a6f33fb82b4af9e21022e3755a10bc28f0180";
                    hash = "sha256-+Hpax7i+zDH5wxaa/TpvM/uCtK+eIQIuN1WhC8KPAYA=";
                  }
                  {
                    path = "model-00006-of-00048.safetensors";
                    bytes = 3590024776;
                    oid = "4a4f3764e3fc772b9fba67f0a44ef68e18f178b6f00faa80b75db549e51894cd";
                    hash = "sha256-Sk83ZOP8dyufumfwpE72jhjxeLbwD6qAt121SeUYlM0=";
                  }
                  {
                    path = "model-00007-of-00048.safetensors";
                    bytes = 3568768976;
                    oid = "df81bb80e27a689e01fa579eebd6499f86e0b6105f7fea18961aa5eebbbee9bc";
                    hash = "sha256-34G7gOJ6aJ4B+lee69ZJn4bgthBff+oYlhql7ru+6bw=";
                  }
                  {
                    path = "model-00008-of-00048.safetensors";
                    bytes = 3590024776;
                    oid = "224968d2b27f8669365ec08657a768dfec40da0585f85f302a31495931f6a526";
                    hash = "sha256-Iklo0rJ/hmk2XsCGV6do3+xA2gWF+F8wKjFJWTH2pSY=";
                  }
                  {
                    path = "model-00009-of-00048.safetensors";
                    bytes = 3568768976;
                    oid = "04d69ef1071fff8721c62968c200a5583122b59b015e9ef9b2978bfed271b2b7";
                    hash = "sha256-BNae8Qcf/4chxilowgClWDEitZsBXp75speL/tJxsrc=";
                  }
                  {
                    path = "model-00010-of-00048.safetensors";
                    bytes = 3590024776;
                    oid = "627145f4ebeb1cc3f5bdd03416b8cb7370b3c96974853cbeb8e5516ad5713e49";
                    hash = "sha256-YnFF9OvrHMP1vdA0FrjLc3CzyWl0hTy+uOVRatVxPkk=";
                  }
                  {
                    path = "model-00011-of-00048.safetensors";
                    bytes = 3568768976;
                    oid = "e4b8e601dcbebe902e0102e7b098b670a121cb8b9564dd719fc41d782c8416e0";
                    hash = "sha256-5LjmAdy+vpAuAQLnsJi2cKEhy4uVZN1xn8QdeCyEFuA=";
                  }
                  {
                    path = "model-00012-of-00048.safetensors";
                    bytes = 3590026352;
                    oid = "64ed4e5f6126ba029c462c9d5fca0fc907c5f855b4ba01194d79560f6db16e42";
                    hash = "sha256-ZO1OX2EmugKcRiydX8oPyQfF+FW0ugEZTXlWD22xbkI=";
                  }
                  {
                    path = "model-00013-of-00048.safetensors";
                    bytes = 3568770544;
                    oid = "8dfe199d07c07ddd141c2c0136a2237f1161250a1a03ebe8deaabac93440da1d";
                    hash = "sha256-jf4ZnQfAfd0UHCwBNqIjfxFhJQoaA+vo3qq6yTRA2h0=";
                  }
                  {
                    path = "model-00014-of-00048.safetensors";
                    bytes = 3590026352;
                    oid = "45db2f540f825f92453c50335e49aede58cca56bc578d1787c12a0fbca6593e5";
                    hash = "sha256-RdsvVA+CX5JFPFAzXkmu3ljMpWvFeNF4fBKg+8plk+U=";
                  }
                  {
                    path = "model-00015-of-00048.safetensors";
                    bytes = 3568770544;
                    oid = "5810381a0f05b7381c002d299ed6ac19e42eba8070dd17e2703546944d84f292";
                    hash = "sha256-WBA4Gg8FtzgcAC0pntasGeQuuoBw3RficDVGlE2E8pI=";
                  }
                  {
                    path = "model-00016-of-00048.safetensors";
                    bytes = 3590026352;
                    oid = "e0530b7024771b0ce2df9b40bcc2232578f3300178487ec216863b0b2835617b";
                    hash = "sha256-4FMLcCR3Gwzi35tAvMIjJXjzMAF4SH7CFoY7Cyg1YXs=";
                  }
                  {
                    path = "model-00017-of-00048.safetensors";
                    bytes = 3568770544;
                    oid = "ed11130247118b185ade893c0109bad896dd394cb1e066ce4fce044176261d94";
                    hash = "sha256-7RETAkcRixha3ok8AQm62JbdOUyx4GbOT84EQXYmHZQ=";
                  }
                  {
                    path = "model-00018-of-00048.safetensors";
                    bytes = 3590026352;
                    oid = "e393fea96da2a3414ef089354fc32e1c8891954de40958c84d2c2ecf80365b25";
                    hash = "sha256-45P+qW2io0FO8Ik1T8MuHIiRlU3kCVjITSwuz4A2WyU=";
                  }
                  {
                    path = "model-00019-of-00048.safetensors";
                    bytes = 3568770544;
                    oid = "a74ca4d3e8e82ce20c458bb8b1900110b753793ad4c58d08f38995f719c616f7";
                    hash = "sha256-p0yk0+joLOIMRYu4sZABELdTeTrUxY0I84mV9xnGFvc=";
                  }
                  {
                    path = "model-00020-of-00048.safetensors";
                    bytes = 3590026352;
                    oid = "9f556769926e60309e8defe45ab59fc8b26ae460d30c190cd746a3d78c11e2c2";
                    hash = "sha256-n1VnaZJuYDCeje/kWrWfyLJq5GDTDBkM10aj14wR4sI=";
                  }
                  {
                    path = "model-00021-of-00048.safetensors";
                    bytes = 3568770544;
                    oid = "1671cce7f90d781f796b5ca6bf32dd1aeb740abcb2735e41ffd28f62485ce005";
                    hash = "sha256-FnHM5/kNeB95a1ymvzLdGut0Cryyc15B/9KPYkhc4AU=";
                  }
                  {
                    path = "model-00022-of-00048.safetensors";
                    bytes = 3590026352;
                    oid = "decd67a4bd97a75fa36861d2ad3067afeefa6a04a20da997fe6c19f171e70132";
                    hash = "sha256-3s1npL2Xp1+jaGHSrTBnr+76agSiDamX/mwZ8XHnATI=";
                  }
                  {
                    path = "model-00023-of-00048.safetensors";
                    bytes = 3568770544;
                    oid = "c61a3e179cdbee19bfb8cbc4e111928ce2f1e1f0f4729d7c0cd5634354a4689d";
                    hash = "sha256-xho+F5zb7hm/uMvE4RGSjOLx4fD0cp18DNVjQ1SkaJ0=";
                  }
                  {
                    path = "model-00024-of-00048.safetensors";
                    bytes = 3590026352;
                    oid = "fc27aeb4233534f6f7781dcfe57127a3908ae10fc025c5d86dc0682057f8b2fe";
                    hash = "sha256-/CeutCM1NPb3eB3P5XEno5CK4Q/AJcXYbcBoIFf4sv4=";
                  }
                  {
                    path = "model-00025-of-00048.safetensors";
                    bytes = 3568770544;
                    oid = "a66b6b8d5821b68f5b511e4f91e12025cd07d0fa6d0b71e722d825a2d6d878ca";
                    hash = "sha256-pmtrjVghto9bUR5PkeEgJc0H0PptC3HnItglotbYeMo=";
                  }
                  {
                    path = "model-00026-of-00048.safetensors";
                    bytes = 3590026352;
                    oid = "657b89314fbaf6eee4acce24b3baf7e5fd2c5986a96ad85b08d90539cde869fe";
                    hash = "sha256-ZXuJMU+69u7krM4ks7r35f0sWYapathbCNkFOc3oaf4=";
                  }
                  {
                    path = "model-00027-of-00048.safetensors";
                    bytes = 3568770544;
                    oid = "fb01f21a0da0446b0bdf25a127ab19a6b06006acd8735f06a9ebfe34423fd7f5";
                    hash = "sha256-+wHyGg2gRGsL3yWhJ6sZprBgBqzYc18Gqev+NEI/1/U=";
                  }
                  {
                    path = "model-00028-of-00048.safetensors";
                    bytes = 3590026352;
                    oid = "b2fd5cbbb639f16e673bc484e5cca16b52a58bf2ab4bd62592e0c5408712ad7c";
                    hash = "sha256-sv1cu7Y58W5nO8SE5cyha1Kli/KrS9YlkuDFQIcSrXw=";
                  }
                  {
                    path = "model-00029-of-00048.safetensors";
                    bytes = 3568770544;
                    oid = "9ec2fdf900275daeac0980490c5c731cc7868b151ce1de5698f48418de4fa5f0";
                    hash = "sha256-nsL9+QAnXa6sCYBJDFxzHMeGixUc4d5WmPSEGN5PpfA=";
                  }
                  {
                    path = "model-00030-of-00048.safetensors";
                    bytes = 3590026352;
                    oid = "9ed3c317bf967d32133ad3a068ee4c56aae9784bc8b7da694482437f37dc1782";
                    hash = "sha256-ntPDF7+WfTITOtOgaO5MVqrpeEvIt9ppRIJDfzfcF4I=";
                  }
                  {
                    path = "model-00031-of-00048.safetensors";
                    bytes = 3568770544;
                    oid = "d5078c3fca3e6370043606ead7856e0b8fe67a9aab52c415769f29934c4d7f5d";
                    hash = "sha256-1QeMP8o+Y3AENgbq14VuC4/mepqrUsQVdp8pk0xNf10=";
                  }
                  {
                    path = "model-00032-of-00048.safetensors";
                    bytes = 3590026352;
                    oid = "163653848f002718d3deaa6ce48885483fc1f2e12e50e44a47477c73ccd91393";
                    hash = "sha256-FjZThI8AJxjT3qps5IiFSD/B8uEuUORKR0d8c8zZE5M=";
                  }
                  {
                    path = "model-00033-of-00048.safetensors";
                    bytes = 3568770544;
                    oid = "f2cffd43f2a5f491f4691f8694e6bc08239158e143ae7063dc04f0eb0259214a";
                    hash = "sha256-8s/9Q/Kl9JH0aR+GlOa8CCORWOFDrnBj3ATw6wJZIUo=";
                  }
                  {
                    path = "model-00034-of-00048.safetensors";
                    bytes = 3590026352;
                    oid = "0f94945121474cfdb6a9ab175914d3811ffbf08e6cc54082e14e473c755d18d8";
                    hash = "sha256-D5SUUSFHTP22qasXWRTTgR/78I5sxUCC4U5HPHVdGNg=";
                  }
                  {
                    path = "model-00035-of-00048.safetensors";
                    bytes = 3568770544;
                    oid = "9cb6a316989f7c7385e3ec2bd42ffe766ee126c70ef3466742849982ee1b0f0f";
                    hash = "sha256-nLajFpiffHOF4+wr1C/+dm7hJscO80ZnQoSZgu4bDw8=";
                  }
                  {
                    path = "model-00036-of-00048.safetensors";
                    bytes = 3590026352;
                    oid = "7e6761421fe944c2143eb897b983085891b421c148c6c17fb5cd8eaa9bdaa497";
                    hash = "sha256-fmdhQh/pRMIUPriXuYMIWJG0IcFIxsF/tc2OqpvapJc=";
                  }
                  {
                    path = "model-00037-of-00048.safetensors";
                    bytes = 3568770544;
                    oid = "a59d662f1143596d56c452a1230b717ce43edf678207398c573a2503b0f72c91";
                    hash = "sha256-pZ1mLxFDWW1WxFKhIwtxfOQ+32eCBzmMVzolA7D3LJE=";
                  }
                  {
                    path = "model-00038-of-00048.safetensors";
                    bytes = 3590026352;
                    oid = "137fa617a74ba8e73fd76bb1010c7a85d791aaa150006cb66faa04a83e9e730f";
                    hash = "sha256-E3+mF6dLqOc/12uxAQx6hdeRqqFQAGy2b6oEqD6ecw8=";
                  }
                  {
                    path = "model-00039-of-00048.safetensors";
                    bytes = 3568770544;
                    oid = "a29af1aa519d7ce726235ea2c2b38146d756290cda7a82d90c4d4438155b53e4";
                    hash = "sha256-oprxqlGdfOcmI16iwrOBRtdWKQzaeoLZDE1EOBVbU+Q=";
                  }
                  {
                    path = "model-00040-of-00048.safetensors";
                    bytes = 3590026352;
                    oid = "8bc93d8a7d1987dc86b14e22b1d8f42ec31da92c56edd9f312daf43f33a6a206";
                    hash = "sha256-i8k9in0Zh9yGsU4isdj0LsMdqSxW7dnzEtr0PzOmogY=";
                  }
                  {
                    path = "model-00041-of-00048.safetensors";
                    bytes = 3568770544;
                    oid = "fd312e7fdd6cb5796df356a7f0314f124851dc149991e9fb02c5bed45cc4ba05";
                    hash = "sha256-/TEuf91stXlt81an8DFPEkhR3BSZken7AsW+1FzEugU=";
                  }
                  {
                    path = "model-00042-of-00048.safetensors";
                    bytes = 3590026352;
                    oid = "4d19bf368083c9a183cb0849f316ec17b62f859ca824c0586e779657efb6e6a6";
                    hash = "sha256-TRm/NoCDyaGDywhJ8xbsF7YvhZyoJMBYbneWV++25qY=";
                  }
                  {
                    path = "model-00043-of-00048.safetensors";
                    bytes = 3568770544;
                    oid = "b7103842ceb70848f9804f55c193d6a57f43174a587cba42b61b5c1bc4e1303d";
                    hash = "sha256-txA4Qs63CEj5gE9VwZPWpX9DF0pYfLpCthtcG8ThMD0=";
                  }
                  {
                    path = "model-00044-of-00048.safetensors";
                    bytes = 3590026352;
                    oid = "422d3889fa20c238b7f97464c14df0bcf3328f189c294f41a3a334421dc560c7";
                    hash = "sha256-Qi04ifogwji3+XRkwU3wvPMyjxicKU9Bo6M0Qh3FYMc=";
                  }
                  {
                    path = "model-00045-of-00048.safetensors";
                    bytes = 1059332516;
                    oid = "a5be6aed7b84fc87ec42b5d24ba0b0d67f253a3906fcd99c13f4f7be5958fc00";
                    hash = "sha256-pb5q7XuE/IfsQrXSS6Cw1n8lOjkG/NmcE/T3vllY/AA=";
                  }
                  {
                    path = "model-00046-of-00048.safetensors";
                    bytes = 3610455184;
                    oid = "5db924ca907e0d93acd975bd5079c3662717f9ac709f23d079bd8f816d29d9dd";
                    hash = "sha256-XbkkypB+DZOs2XW9UHnDZicX+axwnyPQeb2PgW0p2d0=";
                  }
                  {
                    path = "model-00047-of-00048.safetensors";
                    bytes = 3560111960;
                    oid = "62816173f9f6e136b20b48e3b6f16613ac9ea02b5603f636928b253244a548bd";
                    hash = "sha256-YoFhc/n24TayC0jjtvFmE6yeoCtWA/Y2koslMkSlSL0=";
                  }
                  {
                    path = "model-00048-of-00048.safetensors";
                    bytes = 3692775244;
                    oid = "cc43742bd24ae6bcdea343a91442f6f66aed2cfebcc6b235470204851ce2f8a9";
                    hash = "sha256-zEN0K9JK5rzeo0OpFEL29mrtLP68xrI1RwIEhRzi+Kk=";
                  }
                  {
                    path = "model.safetensors.index.json";
                    bytes = 5602871;
                    oid = "98efab455cf08dfbbbaaba6f570e1bf10bf927d2b4c3c453a59c2f6f0e3be92b";
                    hash = "sha256-mO+rRVzwjfu7qrpvVw4b8Qv5J9K0w8RTpZwvbw476Ss=";
                  }
                  {
                    path = "tokenizer.json";
                    bytes = 6367146;
                    oid = "8f9f37ca37fdc4f5fd36d5cf4d3b0e8392edb4e894fd10cc0d70b4957c8633cf";
                    hash = "sha256-j583yjf9xPX9NtXPTTsOg5LttOiU/RDMDXC0lXyGM88=";
                  }
                  {
                    path = "tokenizer_config.json";
                    bytes = 801;
                    oid = "6ac8c8dc065ed118161d02dd532749ae3f52c243deac27872134fae2f50d8547";
                    hash = "sha256-asjI3AZe0RgWHQLdUydJrj9SwkPerCeHITT64vUNhUc=";
                  }
                ];
              };
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
              quantization = "Q8_0";
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

            qwen3-vl-32b-instruct-q8-0 = mkSingleFileArtifact {
              maker = "Qwen";
              baseCheckpoint = {
                url = "https://huggingface.co/Qwen/Qwen3-VL-32B-Instruct";
                revision = "0cfaf48183f594c314753d30a4c4974bc75f3ccb";
              };
              hfUrl = "https://huggingface.co/unsloth/Qwen3-VL-32B-Instruct-GGUF";
              revision = "b9262a359f54dead8e2609f6146e2fc3398fd0d9";
              path = "Qwen3-VL-32B-Instruct-Q8_0.gguf";
              bytes = 34817721120;
              oid = "968ac869a67c8fde33a2f5fd497c5fb03223bbdc3afc113e0a8f322e581b52e7";
              hash = "sha256-lorIaaZ8j94zovX9SXxfsDIju9w6/BE+Co8yLlgbUuc=";
              quantization = "Q8_0";
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

            qwen3-embedding-8b-q8-0 = mkSingleFileArtifact {
              maker = "Qwen";
              baseCheckpoint = {
                url = "https://huggingface.co/Qwen/Qwen3-Embedding-8B";
                revision = "1d8ad4ca9b3dd8059ad90a75d4983776a23d44af";
              };
              hfUrl = "https://huggingface.co/Qwen/Qwen3-Embedding-8B-GGUF";
              revision = "69d0e58a13e463cd99a9b83e3f5fee7c10265fab";
              path = "Qwen3-Embedding-8B-Q8_0.gguf";
              bytes = 8047105824;
              oid = "d20ddc71e8a5c4344f2343481e242233a997dc5eaff442427a945836c97b4deb";
              hash = "sha256-0g3cceilxDRPI0NIHiQiM6mX3F6v9EJCepRYNsl7Tes=";
              quantization = "Q8_0";
              notes = "High-fidelity embedding companion selected for the 128 GiB coordinator.";
            };

            qwen3-vl-embedding-8b-q8-0 = mkSingleFileArtifact {
              maker = "Qwen / mradermacher";
              baseCheckpoint = {
                url = "https://huggingface.co/Qwen/Qwen3-VL-Embedding-8B";
                revision = "2c4565515e0f265c6511776e7193b22c0968ddc7";
              };
              hfUrl = "https://huggingface.co/mradermacher/Qwen3-VL-Embedding-8B-GGUF";
              revision = "ffa49879fdb91ed1a436fbc84f37b123f714bb13";
              path = "Qwen3-VL-Embedding-8B.Q8_0.gguf";
              bytes = 8048295168;
              oid = "c77299abab613f121ff918f17d085704952b21e986c73a71ec6cdc8a6e43e34b";
              hash = "sha256-x3KZq6thPxIf+RjxfQhXBJUrIemGxzpx7Gzcim5D40s=";
              quantization = "Q8_0";
              notes = "Q8_0 multimodal embedder selected for text, image, screenshot, and video retrieval on the coordinator.";
            };

            qwen3-vl-embedding-8b-mmproj-f16 = mkSingleFileArtifact {
              kind = "mmproj";
              maker = "Qwen / mradermacher";
              baseCheckpoint = {
                url = "https://huggingface.co/Qwen/Qwen3-VL-Embedding-8B";
                revision = "2c4565515e0f265c6511776e7193b22c0968ddc7";
              };
              hfUrl = "https://huggingface.co/mradermacher/Qwen3-VL-Embedding-8B-GGUF";
              revision = "ffa49879fdb91ed1a436fbc84f37b123f714bb13";
              path = "Qwen3-VL-Embedding-8B.mmproj-f16.gguf";
              bytes = 1159030304;
              oid = "c507828405f645670c829be93fa57fb890af5b7abbe2583435f4a8042d1f8ba8";
              hash = "sha256-xQeChAX2RWcMgpvpP6V/uJCvW3q74lg0NfSoBC0fi6g=";
              notes = "F16 vision projector paired with the Q8_0 multimodal embedding model.";
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
            flm-qwen3-4b-utility = {
              model = "qwen3:4b";
              role = "utility";
              status = "canonical";
              backend = "npu";
              hosts = [ "coordinator" ];
              runtime = {
                repository = "https://github.com/FastFlowLM/FastFlowLM";
                commit = "fd371409897d7c0abb4de4dbc5098b9b43c094ff";
              };
              evidence = "api-only";
              hardware = "coordinator Strix Halo XDNA2 NPU; amdxdna/XRT from nix-amd-ai";
              notes = "Canonical utility slot. A request-scoped owner rewrites `utility` to `qwen3:4b`, starts and stops FastFlowLM around the request, and never registers an FLM peer in llama-swap.";
            };

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
              evidence = "matched-local";
              hardware = "Strix Halo XDNA2 NPU; amdxdna/XRT from nix-amd-ai";
              notes = "Ad-hoc multimodal utility model on coordinator. FastFlowLM owns these weights; `flm run gemma4-it:e4b` loads them only for the interactive command.";
            };

            flm-gpt-oss-20b = {
              model = "gpt-oss:20b";
              role = "utility";
              # Retired 2026-08-20 (dotfiles#229): old and outdated; the NPU
              # reasoning slot moves to flm-qwen36-35b-a3b-npu2.
              status = "retired";
              archived = "/mnt/nas/models/weights/flm/GPT-OSS-20B-NPU2 (2026-08-20, cp -a of the runtime-owned tree; no store hash exists for FLM weights)";
              backend = "npu";
              hosts = [ "coordinator" ];
              runtime = {
                repository = "https://huggingface.co/FastFlowLM/GPT-OSS-20B-NPU2";
                commit = "12ce92d2bfa031761ab876b3b845a7dabeab1d98";
              };
              evidence = "api-only";
              hardware = "Strix Halo XDNA2 NPU; amdxdna/XRT from nix-amd-ai";
              notes = "Ad-hoc NPU reasoning model on coordinator; `flm run gpt-oss:20b` loads the Q4_1 NPU2 snapshot only for the interactive command.";
            };

            flm-qwen36-35b-a3b-npu2 = {
              model = "qwen3.6-moe:35b-a3b";
              role = "vision";
              status = "canonical";
              backend = "npu";
              hosts = [
                "coordinator"
                "worker"
              ];
              runtime = {
                repository = "https://huggingface.co/FastFlowLM/Qwen3.6-35B-A3B-NPU2";
                commit = "0cad6285baf6f37adf2c4e9696372c0140078fe0";
              };
              evidence = "unverified";
              hardware = "Strix Halo XDNA2 NPU; amdxdna/XRT from nix-amd-ai";
              notes = "The drain's next OCR engine (#229): model.q4nx 23.2G + vision_weight.q4nx 1.0G, runtime-owned via `flm pull qwen3.6-moe:35b-a3b`. Must be validated on OCR BEFORE qwen3-vl-8b-ocr leaves the coordinator allow list, the worker drain is re-pointed, and the GPU qwen36-35b copy retires from both boxes.";
            };

            qwen36-35b-a3b-mtp-ud-q8-k-xl = {
              model = "qwen3.6-35b-a3b";
              role = "general";
              status = "canonical";
              backend = "vulkan";
              hosts = [ "coordinator" ];
              ramTierGb = 44;
              artifacts.model = "qwen36-35b-a3b-mtp-ud-q8-k-xl";
              runtime = llamaCppRuntime (
                commonLlamaArgs
                ++ [
                  "--spec-type"
                  "draft-mtp"
                  "--spec-draft-n-max"
                  "2"
                  "--parallel"
                  "1"
                ]
              );
              benchmark = {
                sourceRepo = "https://github.com/kyuz0/amd-strix-halo-toolboxes";
                sourceCommit = "5aa1e8155d9a1ce339b94fea9b00e3abecad8939";
                runId = "benchmark/results/Qwen3.6-35B-A3B-UD-Q8_K_XL__vulkan_radv__fa1.log";
                name = "llama-bench pp512/tg128";
                speed = "46.33 tok/s decode; 1045 tok/s prefill";
                context = "Radeon 8060S Vulkan/RADV; flash attention";
              };
              evidence = "upstream-measured";
              hardware = "Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
              notes = "Default daily text generator. The Q8 GGUF contains its matched MTP block; llama.cpp self-speculation is enabled without a separate draft file.";
            };

            qwen36-27b-mtp-ud-q8-k-xl = {
              model = "qwen3.6-27b";
              role = "coding";
              status = "canonical";
              backend = "vulkan";
              hosts = [ "coordinator" ];
              ramTierGb = 40;
              artifacts.model = "qwen36-27b-mtp-ud-q8-k-xl";
              runtime = llamaCppRuntime (
                commonLlamaArgs
                ++ [
                  "--spec-type"
                  "draft-mtp"
                  "--spec-draft-n-max"
                  "2"
                  "--parallel"
                  "1"
                ]
              );
              evidence = "matched-local";
              hardware = "Ryzen AI MAX+ 395 / Radeon 8060S gfx1151 / 128 GB unified memory; Vulkan/RADV";
              notes = "Stock dense Qwen 3.6 coding and agent model, locally matched through Pi and llama-swap on coordinator. The Q8 GGUF contains its matched MTP block; 32K context and a single parallel slot bound memory use. This route is text-only because the pinned quantizer's MTP guidance does not support combining MTP with mmproj.";
            };

            qwen38-27b-mtp-q8-0 = {
              model = "qwen3.8-27b";
              role = "general";
              status = "canonical";
              backend = "vulkan";
              hosts = [ "coordinator" ];
              ramTierGb = 40;
              artifacts = {
                model = "qwen38-27b-q8-0";
                mtpHead = "qwen38-27b-mtp-q4-0";
              };
              runtime = llamaCppRuntime (
                commonLlamaArgs
                ++ [
                  "--spec-draft-model"
                  "@mtpHead@"
                  "--spec-type"
                  "draft-mtp"
                  "--spec-draft-n-max"
                  "2"
                  "--parallel"
                  "1"
                  "--cache-type-k"
                  "q8_0"
                  "--cache-type-v"
                  "q8_0"
                  # The model defaults to unbounded thinking; evidence puts the
                  # useful plateau at 6-12K tokens (>12K costs up to 4.5x for
                  # nothing, <5K breaks output). Single-source evidence —
                  # treat 8192 as directional and revisit after local use.
                  "--reasoning-budget"
                  "8192"
                ]
              );
              evidence = "unverified";
              hardware = "Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
              supersedes = "qwen36-27b-mtp-ud-q8-k-xl";
              notes = "Qwen MELS lane primary (#229). MTP head is a separate Q4_0 file (the only published MTP asset); KV q8_0 both sides per the measured 4-6% free gain, and -np stays 1 because parallel slots silently divide the context.";
            };

            qwen3-coder-next-ud-q4-k-xl = {
              model = "qwen3-coder-next";
              role = "coding";
              status = "candidate";
              backend = "vulkan";
              hosts = [ "coordinator" ];
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

            gemma4-26b-a4b-it-mtp-q8-0 = {
              model = "gemma4-26b-a4b-it";
              role = "coding";
              status = "canonical";
              backend = "vulkan";
              hosts = [ "coordinator" ];
              ramTierGb = 32;
              artifacts = {
                model = "gemma4-26b-a4b-it-q8-0";
                mtpHead = "gemma4-26b-a4b-it-mtp-q8-0";
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
              notes = "Cross-family coding model. The former QAT identity was dropped because Google's QAT checkpoint is Q4_0-only; this is the ordinary instruction checkpoint with a matched Q8 MTP head.";
            };

            gemma4-31b-it-q8-0 = {
              model = "gemma4-31b-it";
              role = "general";
              status = "canonical";
              backend = "vulkan";
              hosts = [ "worker" ];
              ramTierGb = 44;
              artifacts = {
                model = "gemma4-31b-it-q8-0";
                draft = "gemma4-e2b-it-draft-ud-q8-k-xl";
              };
              runtime = llamaCppRuntime (
                commonLlamaArgs
                ++ [
                  # Zetaphor recipe, measured on this exact hardware class:
                  # +103% avg / +139% code at identical output quality. n-max 4,
                  # NOT the discrete-GPU 8 — unified memory peaks at 4 then
                  # regresses. NO --mmproj here ever: llama.cpp blocks spec
                  # decode with vision loaded (gemma4-31b-it-vl is the
                  # multimodal entry).
                  "--spec-draft-model"
                  "@draft@"
                  "--spec-type"
                  "draft-simple"
                  "--spec-draft-n-max"
                  "4"
                  "--spec-draft-n-min"
                  "1"
                  "--gpu-layers-draft"
                  "999"
                  "--parallel"
                  "1"
                  "--cache-type-k"
                  "q8_0"
                  "--cache-type-v"
                  "q8_0"
                ]
              );
              evidence = "upstream-measured";
              hardware = "worker Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory; Vulkan/RADV";
              notes = "Google MELS lane heavy model on the worker. Q8_0 pinned by operator; the benchmark ran UD-Q8_K_XL (same weight class). LIVE since 2026-08-21: hosts/worker returned and modules/strix.nix selects this row (#229 §C).";
            };

            gemma4-31b-it-vl = {
              model = "gemma4-31b-it-vl";
              role = "vision";
              status = "canonical";
              backend = "vulkan";
              hosts = [ "worker" ];
              ramTierGb = 40;
              artifacts = {
                model = "gemma4-31b-it-q8-0";
                mmproj = "gemma4-31b-it-mmproj-bf16";
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
                "--parallel"
                "1"
              ];
              evidence = "unverified";
              hardware = "worker Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory; Vulkan/RADV";
              notes = "The multimodal twin of gemma4-31b-it: same Q8_0 weights plus the BF16 projector, no speculative decoding (llama.cpp forbids the combination). LIVE since 2026-08-21 with the worker's return; shares the model artifact with gemma4-31b-it-q8-0, so the pair costs one weight set.";
            };

            ornith-15-35b-q8-0 = {
              model = "ornith-1.5-35b";
              role = "general";
              status = "canonical";
              backend = "vulkan";
              hosts = [ "coordinator" ];
              ramTierGb = 46;
              artifacts.model = "ornith-15-35b-q8-0";
              runtime = llamaCppRuntime (
                commonLlamaArgs
                ++ [
                  "--parallel"
                  "1"
                  "--cache-type-k"
                  "q8_0"
                  "--cache-type-v"
                  "q8_0"
                ]
              );
              evidence = "unverified";
              hardware = "Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
              notes = "Wildcard fast daily-driver companion (cross-family Qwen 3.5 + Gemma 4 post-train, MIT) — not a clean single-provider MELS lane member. Swapped from Ornith 1.0 to 1.5 by operator ruling 2026-08-21; 1.0's independently verified 72% pi-bench score does not transfer.";
            };

            fara15-27b-q8-0 = {
              model = "fara1.5-27b";
              role = "vision";
              status = "canonical";
              backend = "rocm";
              hosts = [ "coordinator" ];
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
              notes = "Browser-computer-use VLM on coordinator. Q8_0 is an explicit quality decision; the BF16 projector is mandatory.";
            };

            fara15-9b-q8-0 = {
              model = "fara1.5-9b";
              role = "vision";
              status = "canonical";
              backend = "rocm";
              hosts = [ "coordinator" ];
              ramTierGb = 16;
              artifacts = {
                model = "fara15-9b-q8-0";
                mmproj = "fara15-9b-mmproj-bf16";
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
              notes = "Mid-tier browser-computer-use VLM on coordinator, same family and serving shape as fara1.5-27b at lower latency/RAM cost. Q8_0 is an explicit quality decision; the BF16 projector is mandatory.";
            };

            fara15-4b-q8-0 = {
              model = "fara1.5-4b";
              role = "vision";
              status = "canonical";
              backend = "rocm";
              hosts = [ "coordinator" ];
              ramTierGb = 8;
              artifacts = {
                model = "fara15-4b-q8-0";
                mmproj = "fara15-4b-mmproj-bf16";
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
              notes = "Smallest browser-computer-use VLM on coordinator, same family and serving shape as fara1.5-27b/9b at the lowest latency/RAM cost. Q8_0 is an explicit quality decision; the BF16 projector is mandatory.";
            };

            qwen36-35b-abliterated-heretic = {
              model = "qwen3.6-35b-heretic";
              role = "uncensored";
              status = "candidate";
              backend = "vulkan";
              hosts = [ "coordinator" ];
              ramTierGb = 24;
              artifacts.model = "qwen36-35b-a3b-abliterated-heretic-q4-k-m";
              runtime = llamaCppRuntime commonLlamaArgs;
              evidence = "unverified";
              hardware = "coordinator Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
              notes = "Coordinator catalog candidate only: manual high-recall hypothesis generator, never an arbiter and excluded from the active allowlist and automatic routing.";
            };

            supergemma4-26b-uncensored = {
              model = "supergemma4-26b-uncensored";
              role = "uncensored";
              status = "candidate";
              backend = "vulkan";
              hosts = [ "coordinator" ];
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
              notes = "Coordinator catalog candidate only. Different model family and tuning path from the Heretic row; excluded from the active allowlist and manual use only.";
            };

            glm47-flash-uncensored-aggressive = {
              model = "glm-4.7-flash-uncensored";
              role = "uncensored";
              status = "candidate";
              backend = "vulkan";
              hosts = [ "coordinator" ];
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
              hardware = "coordinator Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
              notes = "Coordinator catalog candidate only. Non-Heretic aggressive refusal-removal route for method and training-family diversity; excluded from the active allowlist and manual use only.";
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
                model = "qwen3-vl-32b-instruct-q8-0";
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
                context = "llama.cpp ROCm; Q8_0 + BF16 projector";
              };
              evidence = "matched-local";
              hardware = "coordinator Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
              notes = "Targeted second pass for table- and math-heavy pages, not the default drainer.";
            };

            qwen3-embedding-8b-q8-0 = {
              model = "qwen3-embedding-8b";
              role = "embedding";
              status = "canonical";
              backend = "rocm";
              hosts = [ "coordinator" ];
              ramTierGb = 12;
              artifacts.model = "qwen3-embedding-8b-q8-0";
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
              notes = "High-fidelity Q8 embedding companion for the OCR/RAG appliance; re-embed any persisted vectors before comparing with the retired Q5 pipeline.";
            };

            qwen3-vl-embedding-8b-q8-0 = {
              model = "qwen3-vl-embedding-8b";
              role = "embedding";
              status = "canonical";
              backend = "rocm";
              hosts = [ "coordinator" ];
              ramTierGb = 12;
              artifacts = {
                model = "qwen3-vl-embedding-8b-q8-0";
                mmproj = "qwen3-vl-embedding-8b-mmproj-f16";
              };
              runtime = llamaCppRuntime [
                "--mmproj"
                "@mmproj@"
                "--embeddings"
                "--pooling"
                "last"
                "--embd-normalize"
                "2"
                "--ctx-size"
                "32768"
                "--gpu-layers"
                "999"
                "--no-mmap"
              ];
              evidence = "matched-local";
              hardware = "coordinator Ryzen AI MAX+ 395 / gfx1151 / 128 GB unified memory";
              notes = "Coordinator-only multimodal retrieval route. Verified locally on 2026-07-26 through llama-swap with both text and image inputs: each returned one normalized 4096-dimensional embedding; the image request consumed 64 prompt/media tokens.";
            };
          };
        };
      }
    ];
  };
in
{
  inherit backendKinds utility;
  inherit (evaluated.config) artifacts deployments;
}
