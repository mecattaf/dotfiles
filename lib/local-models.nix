{ lib }:

let
  inherit (lib) mkOption types;

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
      url = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Explicit immutable upstream URL for non-Hugging-Face artifacts.";
      };
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
        description = "What the artifact is: weights, a speculative head, a projector, or a sidecar.";
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
        imported = mkOption {
          type = types.bool;
          default = false;
          description = "Locally prepared immutable artifact: explicit NAS import, never a network download.";
        };
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
        gate = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Why this row is not acquired yet: a step only Tom can take (for
            example accepting a model licence). A gated row stays in the
            catalog as a record, library-fetch skips it, and no host may put it
            in its wanted set. Remove the field to release it.
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

  evaluated = lib.evalModules {
    modules = [
      {
        options = {
          artifacts = mkOption {
            type = types.attrsOf artifactType;
            default = { };
          };
        };

        config = {
          # This is a metadata roster. modules/strix.nix roots only its explicit
          # per-host allowlists, so catalog candidates never download merely by
          # existing here.
          # gufo-models.json: Gufo's collection, the fleet's full set of
          # models (Tom, 2026-10-13: "use that as the full collection of
          # modles that we use"), as gufo-org/gufo v0.22.0 pins it, plus its Q8 options. Bytes
          # and sha256 come from the Hugging Face API at the pinned revisions.
          artifacts =
            (builtins.fromJSON (builtins.readFile ./speech-intake-models.json))
            // (builtins.fromJSON (builtins.readFile ./gufo-models.json))
            // (builtins.fromJSON (builtins.readFile ./ds4-models.json))
            // {
              "qwen3-tts-1.7b-base-q8-0" = mkSingleFileArtifact {
                maker = "Qwen";
                hfUrl = "https://huggingface.co/Serveurperso/Qwen3-TTS-GGUF";
                revision = "b7ee2e8c7459c3bea99da23e3d178125a7d1713c";
                path = "qwen-talker-1.7b-base-Q8_0.gguf";
                bytes = 2079448256;
                oid = "4b9a33a236908dd9435a42f7a396e38038329d053b704342a6413c08544c4fda";
                hash = "sha256-S5ozojaQjdlDWkL3o5bjgDgynQU7cENCpkE8CFRMT9o=";
                quantization = "Q8_0";
                notes = "Qwen speech cloning; ServeurpersoCom runtime and matching codec only.";
              };
              qwen3-tts-tokenizer-f32 = mkSingleFileArtifact {
                kind = "tokenizer";
                maker = "Qwen";
                hfUrl = "https://huggingface.co/Serveurperso/Qwen3-TTS-GGUF";
                revision = "b7ee2e8c7459c3bea99da23e3d178125a7d1713c";
                path = "qwen-tokenizer-12hz-F32.gguf";
                bytes = 647263104;
                oid = "b16b95557c7c7340a121757bd6855b9609e1cf4ad3fad0778b89393293ae5f3d";
                hash = "sha256-sWuVVXx8c0ChIXV71oVblgnhz0rT+tB3i4k5MpOuXz0=";
                notes = "Matching full-precision codec for ServeurpersoCom Qwen TTS GGUFs.";
              };

              # ── the one diarization model: VibeVoice-ASR-Streaming-7B ──────
              # Tom, 2026-09-16: the only diarization model; call-diarize loads it
              # on the coordinator. Complete snapshot including its own streaming
              # tokenizer (<|text_chunk_end|> = 151665); never pair it with a
              # plain Qwen2.5 tokenizer.
              vibevoice-asr-streaming-7b-bf16 = {
                kind = "model";
                maker = "Microsoft";
                notes = "Official BF16 streaming ASR with speaker labels (Qwen2.5-7B backbone, 8.67B parameters): 2.933 s chunks plus 0.533 s lookahead at 24 kHz, no timestamps. Audited 2026-09-14 on gfx1151 (~17.6 GB peak, compute RTF ~0.40); coordinator-only.";
                source = {
                  hfUrl = "https://huggingface.co/microsoft/VibeVoice-ASR-Streaming-7B";
                  revision = "60d858b518b4e19d404af3737f848fc185b30177";
                  layout = "snapshot";
                  primary = "config.json";
                  files = [
                    {
                      path = "added_tokens.json";
                      bytes = 713;
                      oid = "d0a4c6e0954c94843fae3c966a7d0b52c7b8c0787fba5731733e6ab602245b88";
                      hash = "sha256-0KTG4JVMlIQ/rjyWan0LUse4wHh/ulcxcz5qtgIkW4g=";
                    }
                    {
                      path = "config.json";
                      bytes = 3709;
                      oid = "804c6e78705f629e0e3484ce130967d43f8d5e1a728e5c1322bdd697e8704c7d";
                      hash = "sha256-gExueHBfYp4ONITOEwln1D+NXhpyjlwTIr3Wl+hwTH0=";
                    }
                    {
                      path = "merges.txt";
                      bytes = 1671839;
                      oid = "599bab54075088774b1733fde865d5bd747cbcc7a547c5bc12610e874e26f5e3";
                      hash = "sha256-WZurVAdQiHdLFzP96GXVvXR8vMelR8W8EmEOh04m9eM=";
                    }
                    {
                      path = "model-00001-of-00008.safetensors";
                      bytes = 2488346304;
                      oid = "3685d210ad49c49521e71a0cc5418ea94b20761c801dc8fc95938c4ec1ab27b3";
                      hash = "sha256-NoXSEK1JxJUh5xoMxUGOqUsgdhyAHcj8lZOMTsGrJ7M=";
                    }
                    {
                      path = "model-00002-of-00008.safetensors";
                      bytes = 2389316008;
                      oid = "d0252f5e9bdf7e65bb0ae051c49148fd5d77e531057556eb955fc6dc72f4f0bc";
                      hash = "sha256-0CUvXpvffmW7CuBRxJFI/V135TEFdVbrlV/G3HL08Lw=";
                    }
                    {
                      path = "model-00003-of-00008.safetensors";
                      bytes = 2466376400;
                      oid = "eeeb0c24e4a3746f16512c0d4aef84732bf8bb4dc5452782e4db356eb5fc7ce7";
                      hash = "sha256-7usMJOSjdG8WUSwNSu+Ecyv4u03FRSeC5Ns1brX8fOc=";
                    }
                    {
                      path = "model-00004-of-00008.safetensors";
                      bytes = 2466376432;
                      oid = "02fec24aaf3e59cbc653b55d94665d6393543f2550364c2c8bc9e75e2a2ca3c0";
                      hash = "sha256-Av7CSq8+WcvGU7VdlGZdY5NUPyVQNkwsi8nnXioso8A=";
                    }
                    {
                      path = "model-00005-of-00008.safetensors";
                      bytes = 2499431160;
                      oid = "a78637bdc2b44f28601f7ee12503e28f5e9faedde35ff5bcdc2e7356c9a6458e";
                      hash = "sha256-p4Y3vcK0TyhgH37hJQPij16frt3jX/W83C5zVsmmRY4=";
                    }
                    {
                      path = "model-00006-of-00008.safetensors";
                      bytes = 2483469960;
                      oid = "5bc9dfef14c62989192ab39356da45a9ccc9f0ef82f7f7127e48c17b5bd5a2f8";
                      hash = "sha256-W8nf7xTGKYkZKrOTVtpFqczJ8O+C9/cSfkjBe1vVovg=";
                    }
                    {
                      path = "model-00007-of-00008.safetensors";
                      bytes = 1464887514;
                      oid = "bb6da42b3547124eb67645fc6fb92523e93310a107872643f7df6dd75f85b4d7";
                      hash = "sha256-u22kKzVHEk62dkX8b7klI+kzEKEHhyZD999t11+FtNc=";
                    }
                    {
                      path = "model-00008-of-00008.safetensors";
                      bytes = 1089994880;
                      oid = "b1499fbe8bc0454eeafc1177db144679940f2456eae188299214c629d4d618b4";
                      hash = "sha256-sUmfvovARU7q/BF32xRGeZQPJFbq4YgpkhTGKdTWGLQ=";
                    }
                    {
                      path = "model.safetensors.index.json";
                      bytes = 120115;
                      oid = "29df2f8e046f5bd8a6d765a700fd767a9c505fa46fe9fd6d50f476c3bdcae638";
                      hash = "sha256-Kd8vjgRvW9im12WnAP12epxQX6Rv6f1tUPR2w73K5jg=";
                    }
                    {
                      path = "preprocessor_config.json";
                      bytes = 192;
                      oid = "99bf76b83a21385d2a8f5226edd9ec598f63e1ff7a50384dc8cf6b7753b9f9c4";
                      hash = "sha256-mb92uDohOF0qj1Im7dnsWY9j4f96UDhNyM9rd1O5+cQ=";
                    }
                    {
                      path = "special_tokens_map.json";
                      bytes = 1177;
                      oid = "cf263f1a86f252cae2cef55ca02f001fecefc92646016f0ed2f7349238b8504d";
                      hash = "sha256-zyY/GobyUsrizvVcoC8AH+zvySZGAW8O0vc0kji4UE0=";
                    }
                    {
                      path = "tokenizer.json";
                      bytes = 7032406;
                      oid = "38e847ed54238171badeeaeaf8760632c949336d3d54207d2d34483c56bc7d57";
                      hash = "sha256-OOhH7VQjgXG63urq+HYGMslJM209VCB9LTRIPFa8fVc=";
                    }
                    {
                      path = "tokenizer_config.json";
                      bytes = 9330;
                      oid = "badef858f0481ccaea85cf86879737f1397c61d0385cdc9b785b657407606e02";
                      hash = "sha256-ut74WPBIHMrqhc+Gh5c38Tl8YdA4XNybeFtldAdgbgI=";
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

            };
        };
      }
    ];
  };
in
{
  inherit (evaluated.config) artifacts;
}
