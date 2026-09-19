{ lib }:

let
  inherit (lib) mkOption types;

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
          artifacts =
            mageArtifacts
            // (builtins.fromJSON (builtins.readFile ./speech-intake-models.json))
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

              # Restored 2026-09-19 (Tom: "FARA 9b should BE BROUGHT BACK").
              # Bytes, oid and hash are the ones this catalogue carried until
              # 2026-09-16; the Library copies were deleted that night
              # (/mnt/nas/models/weights/RETIRED-2026-09-16.tsv), so
              # library-fetch has to re-download both files from bartowski.
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
                notes = "Q8_0 is an explicit operator choice for the mid-tier browser-computer-use appliance; do not silently down-quantize it. A higher-precision row (BF16, or FP8 if an engine ever exists for it here) is Tom's open decision of 2026-09-19, not a silent substitution: see docs/local-ai/fara-restore-2026-09-19.md.";
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

              # ── the fleet's one big model: Halogen Flash on the worker ─────
              # Qwen3.8-Flash-Next in Peonist's proprietary .hgn format, served
              # ONLY by ghcr.io/peonist-ai/halogen-flash-server (modules/halogen.nix)
              # on gfx1151. Nothing else loads these bytes: not llama.cpp, not vLLM,
              # not transformers. Snapshot layout because the server wants the
              # tokenizer as a FLAT directory beside the checkpoint (the entrypoint
              # refuses HF-cache symlink trees). The quality overlay is the default
              # sidecar (HALOGEN_CK_OVERLAY); the speed arm is deliberately not
              # carried. The vision tower is included because OCR and image reading
              # run through this model now.
              halogen-qwen38-flash-next = {
                kind = "model";
                maker = "Peonist";
                baseCheckpoint = {
                  url = "https://huggingface.co/Qwen/Qwen3.8-Flash-Next";
                  revision = "main";
                };
                quantization = "W4B";
                notes = "Halogen Flash server bundle: 4-bit checkpoint + quality overlay + vision tower + flat tokenizer. Pinned to the revision whose quality overlay carries the draft head's 8-bit projections (upstream 0.6.0 reissued that one file; the earlier pin was kyuz0's ai-toolbox-cockpit revision for server 0.5.x). The mtp head and the speed overlay upstream also publishes are deliberately not carried: the head is only read on the GGUF path, which this fleet does not take.";
                source = {
                  hfUrl = "https://huggingface.co/peonist-ai/halogen-qwen3.8-flash-next";
                  revision = "8114dba56501121211d1c647d8f34e7c15df46f4";
                  layout = "snapshot";
                  primary = "qwen38-flash-next-w4b.hgn";
                  files = [
                    {
                      path = "qwen38-flash-next-w4b.hgn";
                      bytes = 124068083904;
                      oid = "9c116bbc01f77b7a15464c1a124eb3325b286089b8a2a6f2856c9b246a235bd6";
                      hash = "sha256-nBFrvAH3e3oVRkwaEk6zMlsoYIm4oqbyhWybJGojW9Y=";
                    }
                    {
                      path = "qwen38-flash-next-w4b.overlay.hgn";
                      bytes = 2572466560;
                      oid = "1cdfc3a9f988955bfe9a71bb808d393030abbf9f99d34ffa1ef93815a49b39ab";
                      hash = "sha256-HN/DqfmIlVv+mnG7gI05MDCrv5+Z00/6Hvk4FaSbOas=";
                    }
                    {
                      path = "qwen38-flash-next-vision.hgn";
                      bytes = 897916416;
                      oid = "d62e0ae553fe88afd3833733d4a4c669f34d20fd8dfce4b9610525bed2134b10";
                      hash = "sha256-1i4K5VP+iK/Tgzcz1KTGafNNIP2N/OS5YQUlvtITSxA=";
                    }
                    {
                      path = "tokenizer/chat_template.jinja";
                      bytes = 8952;
                      oid = "c3cf9e34abf4f9e36c2d72165aa9c132d3e2a725b6c2586aaa3a8af9d7a81041";
                      hash = "sha256-w8+eNKv0+eNsLXIWWqnBMtPipyW2wlhqqjqK+deoEEE=";
                    }
                    {
                      path = "tokenizer/generation_config.json";
                      bytes = 202;
                      oid = "e70c136c1b78ddc1fb0905bac8e733a4dc448d4f852a5dd75143fffc70be550e";
                      hash = "sha256-5wwTbBt43cH7CQW6yOczpNxEjU+FKl3XUUP//HC+VQ4=";
                    }
                    {
                      path = "tokenizer/merges.txt";
                      bytes = 3353259;
                      oid = "a9d356d7bdf1ef4949e3e748e95b8e10ad9d4e2e838eddc38a0a7b6b94d1db8d";
                      hash = "sha256-qdNW173x70lJ4+dI6VuOEK2dTi6Djt3Digp7a5TR240=";
                    }
                    {
                      path = "tokenizer/tokenizer.json";
                      bytes = 12809320;
                      oid = "0997f410c57a1f4e53b09e4be8f4a172d90edd9564368fb0847030937229b9f3";
                      hash = "sha256-CZf0EMV6H05TsJ5L6PShctkO3ZVkNo+whHAwk3IpufM=";
                    }
                    {
                      path = "tokenizer/tokenizer_config.json";
                      bytes = 17928;
                      oid = "b11349aafa7cdc6a320767cf7ceb29ed82f7eda5d65e8e0819e76f0ce947bf27";
                      hash = "sha256-sRNJqvp83GoyB2fPfOsp7YL37aXWXo4IGedvDOlHvyc=";
                    }
                    {
                      path = "tokenizer/vocab.json";
                      bytes = 6722759;
                      oid = "ce99b4cb2983d118806ce0a8b777a35b093e2000a503ebde25853284c9dfa003";
                      hash = "sha256-zpm0yymD0RiAbOCot3ejWwk+IAClA+veJYUyhMnfoAM=";
                    }
                  ];
                };
              };

              # ── the alternate Halogen model: Qwen3.8-27B on the same worker ──
              # Served by Peonist's halogen-server image (ghcr.io/peonist-ai/halogen),
              # a sibling engine to the Flash one with its own checkpoint format
              # generation (p1w4d-d2, ~6.3 bits/weight at decode). Mutually
              # exclusive with the Flash server at runtime — the box holds one
              # resident model — and switched by an operator
              # (modules/halogen.nix, `halogen-switch`). Text only.
              halogen-qwen38-27b = {
                kind = "model";
                maker = "Peonist";
                baseCheckpoint = {
                  url = "https://huggingface.co/Qwen/Qwen3.8-27B";
                  revision = "1d4bf0f2ff6012fd82039f2fa52739d0dd7c60c0";
                };
                quantization = "P1W4D-D2";
                notes = "halogen-server bundle: the 27B dense checkpoint plus its flat tokenizer, pinned to the revision halogen-server 0.1.3 documents.";
                source = {
                  hfUrl = "https://huggingface.co/peonist-ai/halogen-qwen3.8-27b";
                  revision = "d92dc33afed1cdc073846c76e51090fa493ce74a";
                  layout = "snapshot";
                  primary = "qwen3.8-27b-p1w4d-d2.hgn";
                  files = [
                    {
                      path = "qwen3.8-27b-p1w4d-d2.hgn";
                      bytes = 35865565184;
                      oid = "274c3fc767fb57faf025dd03c76376b1fc1b32448aef45aaf02d1898fa962089";
                      hash = "sha256-J0w/x2f7V/rwJd0Dx2N2sfwbMkSK70Wq8C0YmPqWIIk=";
                    }
                    {
                      path = "tokenizer/chat_template.jinja";
                      bytes = 8952;
                      oid = "c3cf9e34abf4f9e36c2d72165aa9c132d3e2a725b6c2586aaa3a8af9d7a81041";
                      hash = "sha256-w8+eNKv0+eNsLXIWWqnBMtPipyW2wlhqqjqK+deoEEE=";
                    }
                    {
                      path = "tokenizer/merges.txt";
                      bytes = 3353259;
                      oid = "a9d356d7bdf1ef4949e3e748e95b8e10ad9d4e2e838eddc38a0a7b6b94d1db8d";
                      hash = "sha256-qdNW173x70lJ4+dI6VuOEK2dTi6Djt3Digp7a5TR240=";
                    }
                    {
                      path = "tokenizer/tokenizer.json";
                      bytes = 12809320;
                      oid = "0997f410c57a1f4e53b09e4be8f4a172d90edd9564368fb0847030937229b9f3";
                      hash = "sha256-CZf0EMV6H05TsJ5L6PShctkO3ZVkNo+whHAwk3IpufM=";
                    }
                    {
                      path = "tokenizer/tokenizer_config.json";
                      bytes = 17928;
                      oid = "b11349aafa7cdc6a320767cf7ceb29ed82f7eda5d65e8e0819e76f0ce947bf27";
                      hash = "sha256-sRNJqvp83GoyB2fPfOsp7YL37aXWXo4IGedvDOlHvyc=";
                    }
                    {
                      path = "tokenizer/vocab.json";
                      bytes = 6722759;
                      oid = "ce99b4cb2983d118806ce0a8b777a35b093e2000a503ebde25853284c9dfa003";
                      hash = "sha256-zpm0yymD0RiAbOCot3ejWwk+IAClA+veJYUyhMnfoAM=";
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
