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
  # stableId; modules/local-models.nix owns the request-scoped rewrite to the
  # deployment named here and installs the `utility-model` wrapper on whichever
  # host serves it.
  #
  # 2026-08-29 — MIGRATED TO THE GPU ROSTER, chosen by Tom.  This slot used to
  # name flm-qwen3-4b-utility, a FastFlowLM row on the XDNA2 NPU.  That NPU is
  # decommissioned permanently and its row stays retired (with its archive
  # receipt), but the SEAM is not: it moves to the GPU twin of the model Tom had
  # earmarked as the drain's next engine, qwen36-35b-a3b-mtp-ud-q8-k-xl, which
  # llama-swap already serves as `qwen3.6-35b-a3b` on the coordinator.  The
  # wrapper forwards one request to that endpoint instead of owning an FLM
  # child; llama-swap serializes loads and TTL-unloads, so nothing takes a lock.
  #
  # contextTokens tracks the row's own --ctx-size (commonLlamaArgs, 32768).
  utility = {
    stableId = "utility";
    deployment = "qwen36-35b-a3b-mtp-ud-q8-k-xl";
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
        # local engines plus the retired-only values (today just "npu", legal
        # solely on status = "retired" archive rows — see
        # lib/local-model-backends.nix and the assertion in
        # modules/local-models.nix that pins that restriction).
        type = types.enum (backendKinds.local ++ backendKinds.retired);
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

            flashnext-fp8 = {
              kind = "model";
              maker = "Qwen";
              notes = "flashnext TP=2 lane: the vendor FP8 release (125B trunk + 51.2B hash-lookup embedding, 6B active, 262144 context), 185.6 GB REQUIRED IN FULL ON EACH TWIN — tensor-parallel shards compute, not the on-disk checkpoint. Declared as an artifact, not a deployment: vLLM serves it through the flashnext pair service (github.com/mecattaf/flashnext, host/fn-cluster-up.sh), never as a llama-swap row. THIS ROW IS THE ANTI-PRUNE: without it local-models-sync rm -rf's /var/lib/local-models/flashnext-fp8 on every boot, rebuild, and sync start — it did exactly that on both twins on 2026-08-29, costing a 185.6 GB per-node re-stage. Apache-2.0 weights, governed by the upstream model license.";
              quantization = "FP8-block-experts";
              source = {
                layout = "snapshot";
                localName = "Qwen3.8-Flash-Next-FP8";
                hfUrl = "https://huggingface.co/Qwen/Qwen3.8-Flash-Next-FP8";
                revision = "970c569adaca6b35532111fd6b27351b2baefe50";
                primary = "config.json";
                files = [
                  {
                    path = "chat_template.jinja";
                    bytes = 8952;
                    oid = "c3cf9e34abf4f9e36c2d72165aa9c132d3e2a725b6c2586aaa3a8af9d7a81041";
                    hash = "sha256-w8+eNKv0+eNsLXIWWqnBMtPipyW2wlhqqjqK+deoEEE=";
                  }
                  {
                    path = "config.json";
                    bytes = 72423;
                    oid = "99c11efba4012d0f760f4e4831a8d6cafd845044e21d0aa9e6d9e70a15a90a8d";
                    hash = "sha256-mcEe+6QBLQ92D05IMajWyv2EUETiHQqp5tnnChWpCo0=";
                  }
                  {
                    path = "generation_config.json";
                    bytes = 202;
                    oid = "e70c136c1b78ddc1fb0905bac8e733a4dc448d4f852a5dd75143fffc70be550e";
                    hash = "sha256-5wwTbBt43cH7CQW6yOczpNxEjU+FKl3XUUP//HC+VQ4=";
                  }
                  {
                    path = "merges.txt";
                    bytes = 3353259;
                    oid = "a9d356d7bdf1ef4949e3e748e95b8e10ad9d4e2e838eddc38a0a7b6b94d1db8d";
                    hash = "sha256-qdNW173x70lJ4+dI6VuOEK2dTi6Djt3Digp7a5TR240=";
                  }
                  {
                    path = "model-00001-of-00131.safetensors";
                    bytes = 1040155912;
                    oid = "774f0ceeadb40d165f2b3ff397d5f3840e6ca8fcb8f3d39d8acb4fea9e52c941";
                    hash = "sha256-d08M7q20DRZfKz/zl9XzhA5sqPy489OdistP6p5SyUE=";
                  }
                  {
                    path = "model-00002-of-00131.safetensors";
                    bytes = 1678209208;
                    oid = "6841fe21fa8a8a7a693c585efe65cd2732889095b696da88bda0cb287366910b";
                    hash = "sha256-aEH+IfqKinppPFhe/mXNJzKIkJW2ltqIvaDLKHNmkQs=";
                  }
                  {
                    path = "model-00003-of-00131.safetensors";
                    bytes = 993901136;
                    oid = "974a2a2ab551f8f1405a4955ab32a8721c68c73dd85b382491d9f0e6a34ee752";
                    hash = "sha256-l0oqKrVR+PFAWklVqzKochxoxz3YWzgkkdnw5qNO51I=";
                  }
                  {
                    path = "model-00004-of-00131.safetensors";
                    bytes = 1678209208;
                    oid = "591f488ab5cd5f0bd4fe28266099523761b9b9339137800734c34ffd84595538";
                    hash = "sha256-WR9IirXNXwvU/igmYJlSN2G5uTORN4AHNMNP/YRZVTg=";
                  }
                  {
                    path = "model-00005-of-00131.safetensors";
                    bytes = 1717267690;
                    oid = "c50bf465a4a0129f1a1196c0e75d881048238f7107b356fc734007eac0d3b123";
                    hash = "sha256-xQv0ZaSgEp8aEZbA512IEEgjj3EHs1b8c0AH6sDTsSM=";
                  }
                  {
                    path = "model-00006-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "57f103367fe36c9dc355c648d521d026caabb4ce5ba51038c78bd935f6593736";
                    hash = "sha256-V/EDNn/jbJ3DVcZI1SHQJsqrtM5bpRA4x4vZNfZZNzY=";
                  }
                  {
                    path = "model-00007-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "cde2a12854770c706a74a5c7b85ffc140e3d4dba93dd4bee1cd7aa07cc348c90";
                    hash = "sha256-zeKhKFR3DHBqdKXHuF/8FA49TbqT3UvuHNeqB8w0jJA=";
                  }
                  {
                    path = "model-00008-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "98ae323b5a61abdcf58a0dc9db7eb1a5a748cebc1ef1932804a1411500c09d84";
                    hash = "sha256-mK4yO1phq9z1ig3J236xpadIzrwe8ZMoBKFBFQDAnYQ=";
                  }
                  {
                    path = "model-00009-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "70f4b66bca5c4c0b441cf4284d4ab311670e182bfc5ec51c7294a4054baeb20f";
                    hash = "sha256-cPS2a8pcTAtEHPQoTUqzEWcOGCv8XsUccpSkBUuusg8=";
                  }
                  {
                    path = "model-00010-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "6d5dfa1dfa9a6c482f100f6e75c1f5e8ac02391c62e844e53f4a53996baf2206";
                    hash = "sha256-bV36HfqabEgvEA9udcH16KwCORxi6ETlP0pTmWuvIgY=";
                  }
                  {
                    path = "model-00011-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "de085adb563e530e7ad157220cd1a219be189a1db0fcc3f2507886a2d78bd4e1";
                    hash = "sha256-3gha21Y+Uw560VciDNGiGb4Ymh2w/MPyUHiGoteL1OE=";
                  }
                  {
                    path = "model-00012-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "97dac7c366ba19858d78c01364054136449ccb3cf60768587461cbf0bb582c90";
                    hash = "sha256-l9rHw2a6GYWNeMATZAVBNkScyzz2B2hYdGHL8LtYLJA=";
                  }
                  {
                    path = "model-00013-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "467be10b473d25e0581f8fb1bc986916c8b9301272f72e7a05762484ffc080a9";
                    hash = "sha256-RnvhC0c9JeBYH4+xvJhpFsi5MBJy9y56BXYkhP/AgKk=";
                  }
                  {
                    path = "model-00014-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "38def6e9bbe6f242c2f92858c3e9a2b356d74d0180e323677158016dbee32ae7";
                    hash = "sha256-ON726bvm8kLC+ShYw+mis1bXTQGA4yNncVgBbb7jKuc=";
                  }
                  {
                    path = "model-00015-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "90c6c665f1f819bc6350714652c8fb77064fec57832ef51b878a0cdf9f602236";
                    hash = "sha256-kMbGZfH4GbxjUHFGUsj7dwZP7FeDLvUbh4oM359gIjY=";
                  }
                  {
                    path = "model-00016-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "88185c2530641b37dcad80d37b505c5257035e87ad29fa86640aae4814903e4f";
                    hash = "sha256-iBhcJTBkGzfcrYDTe1BcUlcDXoetKfqGZAquSBSQPk8=";
                  }
                  {
                    path = "model-00017-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "42e3b96359116d7471a74cb7de08f6a4e9e173830d562f1f74ff09d1d253ad38";
                    hash = "sha256-QuO5Y1kRbXRxp0y33gj2pOnhc4MNVi8fdP8J0dJTrTg=";
                  }
                  {
                    path = "model-00018-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "040adc7270efca6498c6f6a07dd7da14925d20217fe6de67223d6856fb4f2ad7";
                    hash = "sha256-BArccnDvymSYxvagfdfaFJJdICF/5t5nIj1oVvtPKtc=";
                  }
                  {
                    path = "model-00019-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "b8a831992deb1a694439e37b7136ff2e181457a8683bff65f1f4b99772cabe58";
                    hash = "sha256-uKgxmS3rGmlEOeN7cTb/LhgUV6hoO/9l8fS5l3LKvlg=";
                  }
                  {
                    path = "model-00020-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "9426112fbd49ef4f5e9dd38dc2f93b046602e6d92cff732d33b96413ff1b40dc";
                    hash = "sha256-lCYRL71J709endONwvk7BGYC5tks/3MtM7lkE/8bQNw=";
                  }
                  {
                    path = "model-00021-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "fce8426665f749ef38c4fad33b612f892b728c0f74fe60cab0e43ece785b4e77";
                    hash = "sha256-/OhCZmX3Se84xPrTO2EviStyjA90/mDKsOQ+znhbTnc=";
                  }
                  {
                    path = "model-00022-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "a20dd415f280774321538e6b9e78fba9f8e218a9090eae52ea7172b85b9c5a6d";
                    hash = "sha256-og3UFfKAd0MhU45rnnj7qfjiGKkJDq5S6nFyuFucWm0=";
                  }
                  {
                    path = "model-00023-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "4100591839471a8721d9cedb251554dcef5ebc1dfd96ea7dce8912dd1e9921b2";
                    hash = "sha256-QQBZGDlHGoch2c7bJRVU3O9evB39lup9zokS3R6ZIbI=";
                  }
                  {
                    path = "model-00024-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "bbd6d7a4b54b6a6032e15b7c2fc9d6526377f89992d61da8837ad059f3210b45";
                    hash = "sha256-u9bXpLVLamAy4Vt8L8nWUmN3+JmS1h2og3rQWfMhC0U=";
                  }
                  {
                    path = "model-00025-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "f9fa7b04de155dd2be74b5693d5b36e5463dabf956b9be36f67d4aae6b8dd304";
                    hash = "sha256-+fp7BN4VXdK+dLVpPVs25UY9q/lWub429n1KrmuN0wQ=";
                  }
                  {
                    path = "model-00026-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "193c6b9da2c6b69c34d8a14b65234871db272761e712c2e56bac3f13c2d0cbf7";
                    hash = "sha256-GTxrnaLGtpw02KFLZSNIcdsnJ2HnEsLla6w/E8LQy/c=";
                  }
                  {
                    path = "model-00027-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "d7efa372552c07ee8783e27c4b8ebd12fc75333f92553861bec8c7c0155a03fe";
                    hash = "sha256-1++jclUsB+6Hg+J8S469Evx1Mz+SVThhvsjHwBVaA/4=";
                  }
                  {
                    path = "model-00028-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "5fc13d084d62c06b928dfb388a1b36f5c27cd25bd3cbb68a0b21e1c4cfc68e6e";
                    hash = "sha256-X8E9CE1iwGuSjfs4ihs29cJ80lvTy7aKCyHhxM/Gjm4=";
                  }
                  {
                    path = "model-00029-of-00131.safetensors";
                    bytes = 1600008328;
                    oid = "a11f5a6360b349159575871db5c553c40c37be68382b82551a2c2372f15f2811";
                    hash = "sha256-oR9aY2CzSRWVdYcdtcVTxAw3vmg4K4JVGiwjcvFfKBE=";
                  }
                  {
                    path = "model-00030-of-00131.safetensors";
                    bytes = 1600008336;
                    oid = "cac780a675f87fc699435a5207cbecb30a887271b5514b60b7e45d9bebe0e1ec";
                    hash = "sha256-yseApnX4f8aZQ1pSB8vsswqIcnG1UUtgt+Rdm+vg4ew=";
                  }
                  {
                    path = "model-00031-of-00131.safetensors";
                    bytes = 1600008336;
                    oid = "d390a872eb3928b9d7c0a720ced792cc111613812a163d9fd6c97fd35d633897";
                    hash = "sha256-05Cocus5KLnXwKcgzteSzBEWE4EqFj2f1sl/011jOJc=";
                  }
                  {
                    path = "model-00032-of-00131.safetensors";
                    bytes = 1600008336;
                    oid = "3b36fe4e7215a12cdc6c7499aafde51cfbce51266785184b99d3838a6b37b2c8";
                    hash = "sha256-Ozb+TnIVoSzcbHSZqv3lHPvOUSZnhRhLmdODims3ssg=";
                  }
                  {
                    path = "model-00033-of-00131.safetensors";
                    bytes = 1600008336;
                    oid = "3fb0504f406c0c71ee40e9e158492973c5c35337889c81b974892b407620c64c";
                    hash = "sha256-P7BQT0BsDHHuQOnhWEkpc8XDUzeInIG5dIkrQHYgxkw=";
                  }
                  {
                    path = "model-00034-of-00131.safetensors";
                    bytes = 1600008336;
                    oid = "6d989a812a8d8d9330c8c4d21d7be98a0114705ca3bd7834d43bb268bad6be08";
                    hash = "sha256-bZiagSqNjZMwyMTSHXvpigEUcFyjvXg01DuyaLrWvgg=";
                  }
                  {
                    path = "model-00035-of-00131.safetensors";
                    bytes = 1600008336;
                    oid = "8e56ba0a714198bd07a2d8fe9d91fbf5c72601c1b98edf09b289a2538445cb75";
                    hash = "sha256-jla6CnFBmL0Hotj+nZH79ccmAcG5jt8JsomiU4RFy3U=";
                  }
                  {
                    path = "model-00036-of-00131.safetensors";
                    bytes = 1600008336;
                    oid = "c23fd6f6cfa9acfa961ba26e7c9c0dd7b05782c5bbf8f55e2526119b5c516fd4";
                    hash = "sha256-wj/W9s+prPqWG6JufJwN17BXgsW7+PVeJSYRm1xRb9Q=";
                  }
                  {
                    path = "model-00037-of-00131.safetensors";
                    bytes = 942343240;
                    oid = "b824a11bf460bd78c068e3d301e914a0bec2f243a6eea4679be7200d179248e7";
                    hash = "sha256-uCShG/RgvXjAaOPTAekUoL7C8kOm7qRnm+cgDReSSOc=";
                  }
                  {
                    path = "model-00038-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "716eda81a763ffdefd1ac5306b4c80eef123c4dee24ed3a565a22438497581cb";
                    hash = "sha256-cW7agadj/979GsUwa0yA7vEjxN7iTtOlZaIkOEl1gcs=";
                  }
                  {
                    path = "model-00039-of-00131.safetensors";
                    bytes = 877983696;
                    oid = "b91e3bfbcd765ce704db85b78f69055da59456ae733df635e3973ff2f966a148";
                    hash = "sha256-uR47+812XOcE24W3j2kFXaWUVq5zPfY145c/8vlmoUg=";
                  }
                  {
                    path = "model-00040-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "3311ed7821b68bddb1542f06ca349feec72e68288113fe4899b08a3b8156343f";
                    hash = "sha256-MxHteCG2i92xVC8GyjSf7scuaCiBE/5ImbCKO4FWND8=";
                  }
                  {
                    path = "model-00041-of-00131.safetensors";
                    bytes = 1103350296;
                    oid = "1d79949b61730a0fa1f6cd1af149fa50fedc051566cdea48283de8c7a32d972c";
                    hash = "sha256-HXmUm2FzCg+h9s0a8Un6UP7cBRVmzepIKD3ox6Mtlyw=";
                  }
                  {
                    path = "model-00042-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "3f61684338e203cb2ccff6e451eda5705e10043d386b7ed55d4732d23eb5c77b";
                    hash = "sha256-P2FoQzjiA8ssz/bkUe2lcF4QBD04a37VXUcy0j61x3s=";
                  }
                  {
                    path = "model-00043-of-00131.safetensors";
                    bytes = 1000455912;
                    oid = "bab92cfefbb811ee63c4e32595024117c7df3537f5359606eb1de23fe4f115b2";
                    hash = "sha256-urks/vu4Ee5jxOMllQJBF8ffNTf1NZYG6x3iP+TxFbI=";
                  }
                  {
                    path = "model-00044-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "1d05f138848edca4138c3d1c6be4a432a0817eb29fa65f12d8611ecc7685c493";
                    hash = "sha256-HQXxOISO3KQTjD0ca+SkMqCBfrKfpl8S2GEezHaFxJM=";
                  }
                  {
                    path = "model-00045-of-00131.safetensors";
                    bytes = 993902176;
                    oid = "4610384e28f7a91b8bf2a1527178c82cbe7d50ecd9a33b61ee878fa8e8bced85";
                    hash = "sha256-RhA4Tij3qRuL8qFScXjILL59UOzZozth7oePqOi87YU=";
                  }
                  {
                    path = "model-00046-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "5ee9b0e45810300cbd4fd6f2acfe85080e7032a9ce5d77038b86f357b6700c23";
                    hash = "sha256-Xumw5FgQMAy9T9byrP6FCA5wMqnOXXcDi4bzV7ZwDCM=";
                  }
                  {
                    path = "model-00047-of-00131.safetensors";
                    bytes = 878065752;
                    oid = "efa6c0cc0e527486dc5955b00fa75665151d99997b722d8e56bd32da575e414c";
                    hash = "sha256-76bAzA5SdIbcWVWwD6dWZRUdmZl7ci2OVr0y2ldeQUw=";
                  }
                  {
                    path = "model-00048-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "57b148a266c55a896f171b5c98b350092bf394c1fb836658c58c589a0a317ccf";
                    hash = "sha256-V7FIombFWolvFxtcmLNQCSvzlMH7g2ZYxYxYmgoxfM8=";
                  }
                  {
                    path = "model-00049-of-00131.safetensors";
                    bytes = 1096817160;
                    oid = "801dd3b475b43413ade810f4e8d3ace69d6ef5ee4bac5cb98d15e369343a5569";
                    hash = "sha256-gB3TtHW0NBOt6BD06NOs5p1u9e5LrFy5jRXjaTQ6VWk=";
                  }
                  {
                    path = "model-00050-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "b4d00aca34ba7a9f8427983fd0829408fb5e15b2bb7268199e4010bf0c460a04";
                    hash = "sha256-tNAKyjS6ep+EJ5g/0IKUCPteFbK7cmgZnkAQvwxGCgQ=";
                  }
                  {
                    path = "model-00051-of-00131.safetensors";
                    bytes = 993902176;
                    oid = "f430125e9ac92c2de15bbb74bcd3c91bc5374eef389a1be1bc4a592f3a082f0c";
                    hash = "sha256-9DASXprJLC3hW7t0vNPJG8U3Tu84mhvhvEpZLzoILww=";
                  }
                  {
                    path = "model-00052-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "06c3d64136b097919b7e5a1715a70a60b8c2302fc4e80a33235607bb99d00f35";
                    hash = "sha256-BsPWQTawl5GbfloXFacKYLjCMC/E6AozI1YHu5nQDzU=";
                  }
                  {
                    path = "model-00053-of-00131.safetensors";
                    bytes = 1000455920;
                    oid = "147d38f786512f1a8f570a00100b46a3faab1bd649b3445ca0a50c00aa2e99a3";
                    hash = "sha256-FH0494ZRLxqPVwoAEAtGo/qrG9ZJs0RcoKUMAKoumaM=";
                  }
                  {
                    path = "model-00054-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "31c08218039a246c333bfe0b068b8027fd92dddd542e581997af546eb104dd4d";
                    hash = "sha256-McCCGAOaJGwzO/4LBouAJ/2S3d1ULlgZl69UbrEE3U0=";
                  }
                  {
                    path = "model-00055-of-00131.safetensors";
                    bytes = 877983696;
                    oid = "971cd69c8d955bef6d557ebab3f170807a599517f7c69e9d8a6ba375214137f4";
                    hash = "sha256-lxzWnI2VW+9tVX66s/FwgHpZlRf3xp6dimujdSFBN/Q=";
                  }
                  {
                    path = "model-00056-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "a6a975ac346aa3bd1176cb816d8bbd31a4d7542aa3de9306ca5899bea44bd159";
                    hash = "sha256-pql1rDRqo70RdsuBbYu9MaTXVCqj3pMGyliZvqRL0Vk=";
                  }
                  {
                    path = "model-00057-of-00131.safetensors";
                    bytes = 1103350288;
                    oid = "d6acae1622abfa1e0253ae548bc1bdd4bc38cd9b096082acd455b6be592f4a54";
                    hash = "sha256-1qyuFiKr+h4CU65Ui8G91Lw4zZsJYIKs1FW2vlkvSlQ=";
                  }
                  {
                    path = "model-00058-of-00131.safetensors";
                    bytes = 1678209208;
                    oid = "f02b6bd8f5cbd742e8bac3ba9537aa14a64c5a8f3fc75495227a14e1a5cec4ec";
                    hash = "sha256-8Ctr2PXL10LousO6lTeqFKZMWo8/x1SVInoU4aXOxOw=";
                  }
                  {
                    path = "model-00059-of-00131.safetensors";
                    bytes = 877982872;
                    oid = "f3e2c94b8157a021b27e1efdb659333a8d1db330da5cd72ab9012fa0e5351506";
                    hash = "sha256-8+LJS4FXoCGyfh79tlkzOo0dszDaXNcquQEvoOU1FQY=";
                  }
                  {
                    path = "model-00060-of-00131.safetensors";
                    bytes = 1794100080;
                    oid = "908cce7f5fe8dc34f4cca1fc8a676569ab6ce08bad536bd0091c4d75e7b65a05";
                    hash = "sha256-kIzOf1/o3DT0zKH8imdlaats4IutU2vQCRxNdee2WgU=";
                  }
                  {
                    path = "model-00061-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "718532c88f4b7a4f402a50e4f1b6efc3cf71484c9e5a083ee30e96d5094a1bb3";
                    hash = "sha256-cYUyyI9Lek9AKlDk8bbvw89xSEyeWgg+4w6W1QlKG7M=";
                  }
                  {
                    path = "model-00062-of-00131.safetensors";
                    bytes = 1832994688;
                    oid = "3c21b895a5a4f0dc03b669c730f8d8d9ce9a29cbc7628a25894a16ffda6f0a7a";
                    hash = "sha256-PCG4laWk8NwDtmnHMPjY2c6aKcvHYooliUoW/9pvCno=";
                  }
                  {
                    path = "model-00063-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "91d215e2135b2f5db5bc5a9541e5f6bf761205d67c6e7b8955ac73c815198f58";
                    hash = "sha256-kdIV4hNbL121vFqVQeX2v3YSBdZ8bnuJVaxzyBUZj1g=";
                  }
                  {
                    path = "model-00064-of-00131.safetensors";
                    bytes = 993902176;
                    oid = "03a11cad2c283fb9752c6ac01c8f1d8b3127dcda963c5a8225b78f567239d872";
                    hash = "sha256-A6EcrSwoP7l1LGrAHI8dizEn3NqWPFqCJbePVnI52HI=";
                  }
                  {
                    path = "model-00065-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "0f2f96331120779ce1ebd3f957882092d3c733aa9a6073ca87fc86c6eb4e9465";
                    hash = "sha256-Dy+WMxEgd5zh69P5V4ggktPHM6qaYHPKh/yGxutOlGU=";
                  }
                  {
                    path = "model-00066-of-00131.safetensors";
                    bytes = 880605240;
                    oid = "5dbe501e4e0cb9e3f37cc43da46673b4157fdffba09c065ca0b12d75092a79f2";
                    hash = "sha256-Xb5QHk4MuePzfMQ9pGZztBV/3/ugnAZcoLEtdQkqefI=";
                  }
                  {
                    path = "model-00067-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "3ece325d2ca53eddf7b1782d5bbc4c376bc75c6d3da67813e110fd0af67cd09b";
                    hash = "sha256-Ps4yXSylPt33sXgtW7xMN2vHXG09pngT4RD9CvZ80Js=";
                  }
                  {
                    path = "model-00068-of-00131.safetensors";
                    bytes = 1096796552;
                    oid = "0c5ef706afd6b3058af5bf8fdc1e0938cb6e29d0a526c771893c9dcb8e702463";
                    hash = "sha256-DF73Bq/WswWK9b+P3B4JOMtuKdClJsdxiTydy45wJGM=";
                  }
                  {
                    path = "model-00069-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "84999b24e3c55d2eae3ca187219a2e1a1872436ae9bafc91cc3e301180f36cfd";
                    hash = "sha256-hJmbJOPFXS6uPKGHIZouGhhyQ2rpuvyRzD4wEYDzbP0=";
                  }
                  {
                    path = "model-00070-of-00131.safetensors";
                    bytes = 993907416;
                    oid = "eac7940317ee401859caf38089b2b924274ab81a3e5fbd87c42d89923361aad8";
                    hash = "sha256-6seUAxfuQBhZyvOAibK5JCdKuBo+X72HxC2JkjNhqtg=";
                  }
                  {
                    path = "model-00071-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "5ac60e474ccdab21257245630ed8240d75bc7115b3adb27ca65e39eb9ea8f20e";
                    hash = "sha256-WsYOR0zNqyElckVjDtgkDXW8cRWzrbJ8pl45656o8g4=";
                  }
                  {
                    path = "model-00072-of-00131.safetensors";
                    bytes = 1000456024;
                    oid = "b50a05c4c426fb00635d513a733a290da1007a89b8785f1ec02aad8e4d93d955";
                    hash = "sha256-tQoFxMQm+wBjXVE6czopDaEAeom4eF8ewCqtjk2T2VU=";
                  }
                  {
                    path = "model-00073-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "9e0594d389debdfb26d22259725831ff34280edeef4144e683d70205050919d9";
                    hash = "sha256-ngWU04nevfsm0iJZclgx/zQoDt7vQUTmg9cCBQUJGdk=";
                  }
                  {
                    path = "model-00074-of-00131.safetensors";
                    bytes = 877983696;
                    oid = "1b1a0294f8df2a431885783185cdb185106228c9567e67224fe2c3c6a2467f5a";
                    hash = "sha256-GxoClPjfKkMYhXgxhc2xhRBiKMlWfmciT+LDxqJGf1o=";
                  }
                  {
                    path = "model-00075-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "7dba189804ef7a8f9d926b27e1ddbe73767f1213cb7bb3cc582ab15fffec1792";
                    hash = "sha256-fboYmATveo+dkmsn4d2+c3Z/EhPLe7PMWCqxX//sF5I=";
                  }
                  {
                    path = "model-00076-of-00131.safetensors";
                    bytes = 1100073480;
                    oid = "d95ebacb144b4220f2df60cce85a2c86e87cb8291b836d1bd04f9902fcbb9297";
                    hash = "sha256-2V66yxRLQiDy32DM6Foshuh8uCkbg20b0E+ZAvy7kpc=";
                  }
                  {
                    path = "model-00077-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "26046977983e025defdf0f84cf5fc5f4ddfeabbd27e7abc43ff2b413265ab062";
                    hash = "sha256-JgRpd5g+Al3v3w+Ez1/F9N3+q70n56vEP/K0EyZasGI=";
                  }
                  {
                    path = "model-00078-of-00131.safetensors";
                    bytes = 993984232;
                    oid = "6fd46a95777392265b2afa66bf71d488856dafb7b76ff0337a0fe4ac857e961c";
                    hash = "sha256-b9RqlXdzkiZbKvpmv3HUiIVtr7e3b/Azeg/krIV+lhw=";
                  }
                  {
                    path = "model-00079-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "77398002634ce852917c59cd642bec7dd3903381239da68912bf69743631e54e";
                    hash = "sha256-dzmAAmNM6FKRfFnNZCvsfdOQM4EjnaaJEr9pdDYx5U4=";
                  }
                  {
                    path = "model-00080-of-00131.safetensors";
                    bytes = 877983688;
                    oid = "f44aad95d36c443995b965aeef844c8e3a30ed172647dc57fcc0c5476c18d024";
                    hash = "sha256-9EqtldNsRDmVuWWu74RMjjow7RcmR9xX/MDFR2wY0CQ=";
                  }
                  {
                    path = "model-00081-of-00131.safetensors";
                    bytes = 1678209208;
                    oid = "b295a48088573654d1b4754e861ec329956504cb6687e9e2a8eb652b35eaf988";
                    hash = "sha256-spWkgIhXNlTRtHVOhh7DKZVlBMtmh+niqOtlKzXq+Yg=";
                  }
                  {
                    path = "model-00082-of-00131.safetensors";
                    bytes = 1096816112;
                    oid = "83e0e171116c22eb8fdddfa3c387bebb9017eb0586410fd704ce70e7b3d23d68";
                    hash = "sha256-g+DhcRFsIuuP3d+jw4e+u5AX6wWGQQ/XBM5w57PSPWg=";
                  }
                  {
                    path = "model-00083-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "7e1021cde06c970e4b1d9eb3d02f66f29786c59a0da8a3f8879de1a4e3fbf6c0";
                    hash = "sha256-fhAhzeBslw5LHZ6z0C9m8peGxZoNqKP4h53hpOP79sA=";
                  }
                  {
                    path = "model-00084-of-00131.safetensors";
                    bytes = 877983696;
                    oid = "8938fd3c7f88d61fd5b5306eb0ab253d3e42e7f64baf3c3e494d315c8ad5ab55";
                    hash = "sha256-iTj9PH+I1h/VtTBusKslPT5C5/ZLrzw+SU0xXIrVq1U=";
                  }
                  {
                    path = "model-00085-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "cd5875a29d28d52578ae699fdd8891f605a0953cd64516bd88dc45dab50c383a";
                    hash = "sha256-zVh1op0o1SV4rmmf3YiR9gWglTzWRRa9iNxF2rUMODo=";
                  }
                  {
                    path = "model-00086-of-00131.safetensors";
                    bytes = 1103350296;
                    oid = "885e570a662aaf266fd9af9562c65116998df5710b2a27d1bf6aa0c8708b3b74";
                    hash = "sha256-iF5XCmYqryZv2a+VYsZRFpmN9XELKifRv2qgyHCLO3Q=";
                  }
                  {
                    path = "model-00087-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "1472604826f0a0c2bbf7cd0f4a0c5b29f3012e4b3a4424d024d1ec17a3c9d0ea";
                    hash = "sha256-FHJgSCbwoMK7980PSgxbKfMBLks6RCTQJNHsF6PJ0Oo=";
                  }
                  {
                    path = "model-00088-of-00131.safetensors";
                    bytes = 1000455920;
                    oid = "e7273f5435571e761429330ece81732e8fb3f8b5f0087bf80db693630cf702a1";
                    hash = "sha256-5yc/VDVXHnYUKTMOzoFzLo+z+LXwCHv4DbaTYwz3AqE=";
                  }
                  {
                    path = "model-00089-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "eb349562d23e330bbbd0a5f5ba90ac25ed0baa660dff230538a0fcaaf4c8b875";
                    hash = "sha256-6zSVYtI+Mwu70KX1upCsJe0LqmYN/yMFOKD8qvTIuHU=";
                  }
                  {
                    path = "model-00090-of-00131.safetensors";
                    bytes = 997179104;
                    oid = "532915eebd4e231a240e185ba838a95a00ee14277e28fb04ad21508da5ff50aa";
                    hash = "sha256-UykV7r1OIxokDhhbqDipWgDuFCd+KPsErSFQjaX/UKo=";
                  }
                  {
                    path = "model-00091-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "68d8f46ffcd0ff46f4e73c848525cc6fd6af15eebbb9311ce9b4eb14638f5660";
                    hash = "sha256-aNj0b/zQ/0b05zyEhSXMb9avFe67uTEc6bTrFGOPVmA=";
                  }
                  {
                    path = "model-00092-of-00131.safetensors";
                    bytes = 877983696;
                    oid = "91abc087cd244ae62b8469576e209c8e25bc7726bc4fc020b687378059f5b5bd";
                    hash = "sha256-kavAh80kSuYrhGlXbiCcjiW8dya8T8Agtoc3gFn1tb0=";
                  }
                  {
                    path = "model-00093-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "dacd0f2e5215fbf18fb7c6803f61963333e6243f404de83fcd5dfd38f43fe0d1";
                    hash = "sha256-2s0PLlIV+/GPt8aAP2GWMzPmJD9ATeg/zV39OPQ/4NE=";
                  }
                  {
                    path = "model-00094-of-00131.safetensors";
                    bytes = 1096796928;
                    oid = "cac515a778e89fb37e9f38fde6c8fdfa01ebf9d8944a2d6ff35c51ecf4bc875f";
                    hash = "sha256-ysUVp3jon7N+nzj95sj9+gHr+diUSi1v81xR7PS8h18=";
                  }
                  {
                    path = "model-00095-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "a35975c2d21f18d58f21cb59e4eaf34a4bce11440e5112948e7fa6923658f8c4";
                    hash = "sha256-o1l1wtIfGNWPIctZ5OrzSkvOEUQOURKUjn+mkjZY+MQ=";
                  }
                  {
                    path = "model-00096-of-00131.safetensors";
                    bytes = 993902176;
                    oid = "03fd77f9d35024bba9e894c811300ef8aaf5b5ff99ebc2c89c9d9f87685adfe8";
                    hash = "sha256-A/13+dNQJLup6JTIETAO+Kr1tf+Z68LInJ2fh2ha3+g=";
                  }
                  {
                    path = "model-00097-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "f7b81ae09d97b8e2bb96a1916ede51da92209ec8481a31c56fb446acd691b8a8";
                    hash = "sha256-97ga4J2XuOK7lqGRbt5R2pIgnshIGjHFb7RGrNaRuKg=";
                  }
                  {
                    path = "model-00098-of-00131.safetensors";
                    bytes = 993902176;
                    oid = "70f208f47d99c25d5413cd32e0553cce22524cd3863c7797e2cfa37c2d526319";
                    hash = "sha256-cPII9H2Zwl1UE80y4FU8ziJSTNOGPHeX4s+jfC1SYxk=";
                  }
                  {
                    path = "model-00099-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "de5c33dd717495657496067ea715442356fd9f7b64384d1a4c10c9f8fe6f9b7d";
                    hash = "sha256-3lwz3XF0lWV0lgZ+pxVEI1b9n3tkOE0aTBDJ+P5vm30=";
                  }
                  {
                    path = "model-00100-of-00131.safetensors";
                    bytes = 877984072;
                    oid = "43752e81a5c2b376073d5d0d7b70da8d08c49bdbbfcfeb695ea947a2913e4bc8";
                    hash = "sha256-Q3UugaXCs3YHPV0Ne3DajQjEm9u/z+tpXqlHopE+S8g=";
                  }
                  {
                    path = "model-00101-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "c2e978f7238036063914fe909214246730640be77eca215e3cf66d65724de9f1";
                    hash = "sha256-wul49yOANgY5FP6QkhQkZzBkC+d+yiFePPZtZXJN6fE=";
                  }
                  {
                    path = "model-00102-of-00131.safetensors";
                    bytes = 1096797160;
                    oid = "639efed3ea400a8dddeae25db120096898a514697dfc4cbbc0cd15f621c18421";
                    hash = "sha256-Y57+0+pACo3d6uJdsSAJaJilFGl9/Ey7wM0V9iHBhCE=";
                  }
                  {
                    path = "model-00103-of-00131.safetensors";
                    bytes = 1678209208;
                    oid = "f8da1b61296e012dc268b4f0d84c127ef0967df488fe65b037f74c8f893decd1";
                    hash = "sha256-+NobYSluAS3CaLTw2EwSfvCWffSI/mWwN/dMj4k97NE=";
                  }
                  {
                    path = "model-00104-of-00131.safetensors";
                    bytes = 993901144;
                    oid = "adff0f2aee7b7b701e39247cfdfa135c0cab8dfa4f8c7662352c0233adb78829";
                    hash = "sha256-rf8PKu57e3AeOSR8/foTXAyrjfpPjHZiNSwCM623iCk=";
                  }
                  {
                    path = "model-00105-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "6643d71382f00f7ffe16b05879e6ff0f6e56986dee8ec079a84aae82912c6987";
                    hash = "sha256-ZkPXE4LwD3/+FrBYeeb/D25WmG3ujsB5qEqugpEsaYc=";
                  }
                  {
                    path = "model-00106-of-00131.safetensors";
                    bytes = 1025359600;
                    oid = "680495ea0a23e73844e91670437b7b2a5ac5d46f9582923fb7fa91fe640821df";
                    hash = "sha256-aASV6goj5zhE6RZwQ3t7KlrF1G+VgpI/t/qR/mQIId8=";
                  }
                  {
                    path = "model-00107-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "886528d121b77433c1d66654294c13b4f61a004f1e6d1abf2d445fb0a99f7234";
                    hash = "sha256-iGUo0SG3dDPB1mZUKUwTtPYaAE8ebRq/LURfsKmfcjQ=";
                  }
                  {
                    path = "model-00108-of-00131.safetensors";
                    bytes = 1062060032;
                    oid = "a966c28a6267d43052fe87cb19e2e5730bad6154b12eb806b9ce49e007bfec96";
                    hash = "sha256-qWbCimJn1DBS/ofLGeLlcwutYVSxLrgGuc5J4Ae/7JY=";
                  }
                  {
                    path = "model-00109-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "f6074252e492ee5b0933f78cc48f3b90694a8096befb7666cc379c3d47093756";
                    hash = "sha256-9gdCUuSS7lsJM/eMxI87kGlKgJa++3ZmzDecPUcJN1Y=";
                  }
                  {
                    path = "model-00110-of-00131.safetensors";
                    bytes = 877983696;
                    oid = "e3e45e96bc13b52b748a0e2f397a624ad49958396468667d73ed4d725c8b5c1c";
                    hash = "sha256-4+RelrwTtSt0ig4vOXpiStSZWDlkaGZ9c+1NclyLXBw=";
                  }
                  {
                    path = "model-00111-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "d1d354e691eab0b77607faf7eb4adf00a75ee7f270c1cbcbad06aefc19aeac94";
                    hash = "sha256-0dNU5pHqsLd2B/r360rfAKde5/JwwcvLrQau/BmurJQ=";
                  }
                  {
                    path = "model-00112-of-00131.safetensors";
                    bytes = 1096797168;
                    oid = "e61a9a6ef0e538afca09d97a3ccbf3e7e2c647f65cc8eeebebb18621d7779b02";
                    hash = "sha256-5hqabvDlOK/KCdl6PMvz5+LGR/ZcyO7r67GGIdd3mwI=";
                  }
                  {
                    path = "model-00113-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "a14b94db5326bfaab1d8029296b8938f6daf91ba2dc07a4950a38afafa84f776";
                    hash = "sha256-oUuU21Mmv6qx2AKSlriTj22vkbotwHpJUKOK+vqE93Y=";
                  }
                  {
                    path = "model-00114-of-00131.safetensors";
                    bytes = 993907400;
                    oid = "ce4aeac52776038ec0c885915bb270dc65ee07d70d5f71827d5fba1045e2b43b";
                    hash = "sha256-zkrqxSd2A47AyIWRW7Jw3GXuB9cNX3GCfV+6EEXitDs=";
                  }
                  {
                    path = "model-00115-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "8185d8822428d2125876a9aa05aea11c8165713bc99e04ace29921eef0e1b683";
                    hash = "sha256-gYXYgiQo0hJYdqmqBa6hHIFlcTvJngSs4pkh7vDhtoM=";
                  }
                  {
                    path = "model-00116-of-00131.safetensors";
                    bytes = 993902176;
                    oid = "65954dccfa3be20611728311d97679e7f5d78ad519e52312524aa7cf666a48e5";
                    hash = "sha256-ZZVNzPo74gYRcoMR2XZ55/XXitUZ5SMSUkqnz2ZqSOU=";
                  }
                  {
                    path = "model-00117-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "12c8027363b1a7bb782282293314fa57b07be27d17670861858c0aed1e28a3ac";
                    hash = "sha256-EsgCc2Oxp7t4IoIpMxT6V7B74n0XZwhhhYwK7R4oo6w=";
                  }
                  {
                    path = "model-00118-of-00131.safetensors";
                    bytes = 878004272;
                    oid = "2d06ec9c1726f42bfc9ce0bbb47129917d8ab373c88eed4e758fb6940c92ad4a";
                    hash = "sha256-LQbsnBcm9Cv8nOC7tHEpkX2Ks3PIju1OdY+2lAySrUo=";
                  }
                  {
                    path = "model-00119-of-00131.safetensors";
                    bytes = 1678211256;
                    oid = "36008b48c4480085bfd1a81439d70d1029cfaf06cfdd037cec19b491a40659ec";
                    hash = "sha256-NgCLSMRIAIW/0agUOdcNECnPrwbP3QN87Bm0kaQGWew=";
                  }
                  {
                    path = "model-00120-of-00131.safetensors";
                    bytes = 1109903856;
                    oid = "49e4f90d92f60f6489bfe6d3e5250d8fe879c5995ae72ce67379cc7187fa4b0a";
                    hash = "sha256-SeT5DZL2D2SJv+bT5SUNj+h5xZla5yzmc3nMcYf6Swo=";
                  }
                  {
                    path = "model-00121-of-00131.safetensors";
                    bytes = 1678209208;
                    oid = "ae8e07cceeef2f568df035a7bc0c555656acb566ba5936f61a8a019df23361ad";
                    hash = "sha256-ro4HzO7vL1aN8DWnvAxVVlastWa6WTb2GooBnfIzYa0=";
                  }
                  {
                    path = "model-00122-of-00131.safetensors";
                    bytes = 993901136;
                    oid = "b3b21d33b925e31d475a509757cf7459aa4d3e73cb493706f40461387541e137";
                    hash = "sha256-s7IdM7kl4x1HWlCXV890WapNPnPLSTcG9ARhOHVB4Tc=";
                  }
                  {
                    path = "model-00123-of-00131.safetensors";
                    bytes = 1678209208;
                    oid = "f32fec30685afadd76f09bbb1dda680445ad765a97ff1febfc3122b7f73d7ec3";
                    hash = "sha256-8y/sMGha+t128Ju7HdpoBEWtdlqX/x/r/DEit/c9fsM=";
                  }
                  {
                    path = "model-00124-of-00131.safetensors";
                    bytes = 891089968;
                    oid = "e857f36ddd0db135f858c2c87c9fcf39c758965c626b280e47cb0c1e6c1423f8";
                    hash = "sha256-6Ffzbd0NsTX4WMLIfJ/POcdYllxiaygOR8sMHmwUI/g=";
                  }
                  {
                    path = "model-00125-of-00131.safetensors";
                    bytes = 1678209208;
                    oid = "b9de3774218d3cd7946cdbf913dedfc82591c18212d9c3fc9b9484e7dc68e9fe";
                    hash = "sha256-ud43dCGNPNeUbNv5E97fyCWRwYIS2cP8m5SE59xo6f4=";
                  }
                  {
                    path = "model-00126-of-00131.safetensors";
                    bytes = 1096795496;
                    oid = "29b39319522a00b1ef4ac909c4fb306059999f0a48fd07ca73cea687647631ee";
                    hash = "sha256-KbOTGVIqALHvSskJxPswYFmZnwpI/QfKc86mh2R2Me4=";
                  }
                  {
                    path = "model-00127-of-00131.safetensors";
                    bytes = 1678209208;
                    oid = "bf48ccb3b4ba75c288d9db2b94817c6a3993e9f84a5b9410d9f24edcec12e177";
                    hash = "sha256-v0jMs7S6dcKI2dsrlIF8ajmT6fhKW5QQ2fJO3OwS4Xc=";
                  }
                  {
                    path = "model-00128-of-00131.safetensors";
                    bytes = 993901136;
                    oid = "7feaa51c906a1a735e5fb52fd5499b59c473d442d77b44cbd610c9b6a3a9e0ba";
                    hash = "sha256-f+qlHJBqGnNeX7Uv1UmbWcRz1ELXe0TL1hDJtqOp4Lo=";
                  }
                  {
                    path = "model-00129-of-00131.safetensors";
                    bytes = 1678209208;
                    oid = "a5374c8d86aea48f21a4be2ad6cda37fbfbb01eff333d1179939a2e55d8db816";
                    hash = "sha256-pTdMjYaupI8hpL4q1s2jf7+7Ae/zM9EXmTmi5V2NuBY=";
                  }
                  {
                    path = "model-00130-of-00131.safetensors";
                    bytes = 2136177320;
                    oid = "204b122d02425f61115db9ab896648d95f6dadd6a716c65daf6aec297392ed56";
                    hash = "sha256-IEsSLQJCX2ERXbmriWZI2V9trdanFsZdr2rsKXOS7VY=";
                  }
                  {
                    path = "model-00131-of-00131.safetensors";
                    bytes = 1271398496;
                    oid = "ba6fc69ebb6a9da1938c2e041b8ef625f4550b641812da75845bc7dd7c361d80";
                    hash = "sha256-um/GnrtqnaGTjC4EG472JfRVC2QYEtp1hFvH3Xw2HYA=";
                  }
                  {
                    path = "model.safetensors.index.json";
                    bytes = 17410140;
                    oid = "0419e2c2dfbb925257d7409405433a793cf7ff7d96f3eba882a815ec6d9fe7a6";
                    hash = "sha256-BBniwt+7klJX10CUBUM6eTz3/32W8+uogqgV7G2f56Y=";
                  }
                  {
                    path = "preprocessor_config.json";
                    bytes = 390;
                    oid = "27225450ac9c6529872ee1924fcb0962ff5634834f817040f444118116f4e516";
                    hash = "sha256-JyJUUKycZSmHLuGST8sJYv9WNINPgXBA9EQRgRb05RY=";
                  }
                  {
                    path = "tokenizer.json";
                    bytes = 12809320;
                    oid = "0997f410c57a1f4e53b09e4be8f4a172d90edd9564368fb0847030937229b9f3";
                    hash = "sha256-CZf0EMV6H05TsJ5L6PShctkO3ZVkNo+whHAwk3IpufM=";
                  }
                  {
                    path = "tokenizer_config.json";
                    bytes = 17928;
                    oid = "b11349aafa7cdc6a320767cf7ceb29ed82f7eda5d65e8e0819e76f0ce947bf27";
                    hash = "sha256-sRNJqvp83GoyB2fPfOsp7YL37aXWXo4IGedvDOlHvyc=";
                  }
                  {
                    path = "video_preprocessor_config.json";
                    bytes = 385;
                    oid = "7768af27c1fafa9cc9011c1dc20067e03f8915e03b63504550e11d5066986d13";
                    hash = "sha256-d2ivJ8H6+pzJARwdwgBn4D+JFeA7Y1BFUOEdUGaYbRM=";
                  }
                  {
                    path = "vocab.json";
                    bytes = 6722759;
                    oid = "ce99b4cb2983d118806ce0a8b777a35b093e2000a503ebde25853284c9dfa003";
                    hash = "sha256-zpm0yymD0RiAbOCot3ejWwk+IAClA+veJYUyhMnfoAM=";
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
              # Retired 2026-08-29: NPU decommissioned permanently (fleet-7.2 session).
              status = "retired";
              archived = "/mnt/nas/models/weights/flm/Qwen3-4B-NPU2 (2026-08-11, rsync -a of the runtime-owned ~/.config/flm/models tree from the coordinator; no store hash exists for FLM weights)";
              backend = "npu";
              hosts = [ "coordinator" ];
              runtime = {
                repository = "https://github.com/FastFlowLM/FastFlowLM";
                commit = "fd371409897d7c0abb4de4dbc5098b9b43c094ff";
              };
              evidence = "api-only";
              hardware = "coordinator Strix Halo XDNA2 NPU; amdxdna/XRT from nix-amd-ai";
              notes = "Held the canonical utility slot until 2026-08-29, when a request-scoped owner rewrote `utility` to `qwen3:4b`, started and stopped FastFlowLM around the request, and never registered an FLM peer in llama-swap. The slot moved to qwen36-35b-a3b-mtp-ud-q8-k-xl with the NPU decommission; this row keeps only its archive receipt.";
            };

            flm-gemma4-it-e4b = {
              model = "gemma4-it:e4b";
              role = "utility";
              # Retired 2026-08-29: NPU decommissioned permanently (fleet-7.2 session).
              status = "retired";
              archived = "/mnt/nas/models/weights/flm/Gemma4-E4B-IT-NPU2 (2026-08-29, rsync -a of the runtime-owned ~/.config/flm/models tree from the coordinator; no store hash exists for FLM weights)";
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
              # Retired 2026-08-29: NPU decommissioned permanently (fleet-7.2 session).
              status = "retired";
              archived = "/mnt/nas/models/weights/flm/Qwen3.6-35B-A3B-NPU2 (2026-08-29, rsync -a of the runtime-owned ~/.config/flm/models tree from the coordinator; no store hash exists for FLM weights)";
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
              # Also the canonical utility deployment since 2026-08-29 (chosen
              # by Tom): the top-level `utility` slot names this row, so the
              # `utility-model` wrapper rewrites the stable id `utility` to the
              # served id below. No second roster row and no second load — the
              # drain and print seams dial the same resident backend as
              # everything else on this host.
              notes = "Default daily text generator, and the canonical utility deployment behind the stable `utility` id since 2026-08-29. The Q8 GGUF contains its matched MTP block; llama.cpp self-speculation is enabled without a separate draft file.";
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
