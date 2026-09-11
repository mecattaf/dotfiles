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
              notes = "Halogen Flash server bundle: 4-bit checkpoint + quality overlay + vision tower + flat tokenizer, pinned to the revision kyuz0's ai-toolbox-cockpit curates for server 0.5.x.";
              source = {
                hfUrl = "https://huggingface.co/peonist-ai/halogen-qwen3.8-flash-next";
                revision = "ac23b1b223b4e9192d27c22367d4dbacf2b595ef";
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
                    bytes = 2477677120;
                    oid = "737d6bdaef274d3cc22de5bc265b390b89db5fb1e709f58db75287fdc35bb276";
                    hash = "sha256-c31r2u8nTTzCLeW8Jls5C4nbX7HnCfWNt1KH/cNbsnY=";
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

            # ── the small general model on the coordinator ─────────────────
            gemma4-12b-it-q8-0 = mkSingleFileArtifact {
              maker = "Google";
              baseCheckpoint = {
                url = "https://huggingface.co/google/gemma-4-12B-it";
                revision = "707f0a3b8a3c7ad586ed01e27eafbad8a27dd0f7";
              };
              hfUrl = "https://huggingface.co/unsloth/gemma-4-12b-it-GGUF";
              revision = "fc034cfff751157913579611efad8462ac1be606";
              path = "gemma-4-12b-it-Q8_0.gguf";
              bytes = 12669647680;
              oid = "f20e7ff1be28c283eeeb18fc895733791c56a5851d5cd3fe9691b7f7d12afa72";
              hash = "sha256-8g5/8b4owoPu6xj8iVczeRxWpYUdXNP+lpG399Eq+nI=";
              quantization = "Q8_0";
              notes = "Gemma 4 12B instruction model, Q8_0; served by a hand-run llama-server on the coordinator.";
            };

            gemma4-12b-it-mtp-q8-0 = mkSingleFileArtifact {
              kind = "mtp-head";
              maker = "Google";
              baseCheckpoint = {
                url = "https://huggingface.co/google/gemma-4-12B-it";
                revision = "707f0a3b8a3c7ad586ed01e27eafbad8a27dd0f7";
              };
              hfUrl = "https://huggingface.co/unsloth/gemma-4-12b-it-GGUF";
              revision = "fc034cfff751157913579611efad8462ac1be606";
              path = "MTP/mtp-gemma-4-12b-it-Q8_0.gguf";
              bytes = 465109248;
              oid = "145db9094bc0f85f1701e255a2ed216dcc9800fc8bc8631ad00905b456bd451b";
              hash = "sha256-FF25CUvA+F8XAeJVou0hbcyYAPyLyGMa0AkFtFa9RRs=";
              quantization = "Q8_0";
              notes = "Matched Q8 MTP head for gemma4-12b-it-q8-0 (llama-server --spec-type mtp).";
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
