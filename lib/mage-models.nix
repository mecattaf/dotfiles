# Immutable Hugging Face snapshots for the selected Microsoft Mage inference
# release: Turbo generation/editing plus Mage-VL.
#
# Microsoft no longer serves the six Mage-Flow repositories publicly. The
# mage-flow-community organization contains Hub-native duplicates whose commits
# record the original Microsoft repository identity. Mage-VL remains pinned to
# Microsoft's live repository.
let
  mkFile = path: bytes: oid: hash: {
    inherit
      path
      bytes
      oid
      hash
      ;
  };

  # The selected Turbo Mage-Flow checkpoints are self-contained Diffusers-style
  # snapshots.
  # They share every file except repository metadata and the 4B transformer
  # weights. Keeping this list once makes that identity explicit;
  # model-store.nix gives identical content the same fixed-output name so Nix
  # downloads/stores one copy even though each assembled snapshot remains
  # independently usable.
  mageFlowCommonFiles = [
    (mkFile "assets/cuisine.jpg" 2182758
      "a1fabb7558f74bf3dfa66bbaffb12b654510feb8f049d4c1e5d6ded5241a3793"
      "sha256-ofq7dVj3S/Pfpmu6/7ErZUUQ/rjwSdTB5dbe1SQaN5M="
    )
    (mkFile "assets/dog.jpg" 525201 "164d8dfe707fb854e288ad2eea65c2db87e90af11f689c85502860eeaf3f4794"
      "sha256-Fk2N/nB/uFTiiK0u6mXC24fpCvEfaJyFUChg7q8/R5Q="
    )
    (mkFile "assets/edit_gallery_appearance.jpg" 3449652
      "cb5ee8fd3157483aa4f766892e968c6bf6bf06f1c944b04298755f258446d1f5"
      "sha256-y17o/TFXSDqk92aJLpaMa/a/BvHJRLBCmHVfJYRG0fU="
    )
    (mkFile "assets/edit_gallery_content.jpg" 3226041
      "493d9362bfe16246da6851762fc863a56f5131bb9cc7dd70ca181fb888fdc885"
      "sha256-ST2TYr/hYkbaaFF2L8hjpW9RMbucx91wyhgfuIj9yIU="
    )
    (mkFile "assets/edit_gallery_human_creative.jpg" 3307499
      "4accce02b8460946a4f7c6e4d6ac74a29a04b4cbdcac01c5ec6a878d391155ad"
      "sha256-SszOArhGCUak98bk1qx0opoEtMvcrAHF7GqHjTkRVa0="
    )
    (mkFile "assets/edit_gallery_lowlevel.jpg" 2735850
      "b2796b15234934522a89f47b08725a95dce0d9beb8520f1515c14e2af89dd54f"
      "sha256-snlrFSNJNFIqifR7CHJaldzg2b64Ug8VFcFOKvid1U8="
    )
    (mkFile "assets/edit_gallery_restoration.jpg" 3443743
      "77207d09e6c489781424c9e5b756d1b2949eda24c34c431d803c79101cc4ef78"
      "sha256-dyB9CebEiXgUJMnlt1bRspSe2iTDTEMdgDx5EBzE73g="
    )
    (mkFile "assets/edit_gallery_scene_subject.jpg" 3460184
      "acd40223465f051ad97d3ac618819d365e8c4c92c7a16e65812544868f0d8091"
      "sha256-rNQCI0ZfBRrZfTrGGIGdNl6MTJLHoW5lgSVEho8NgJE="
    )
    (mkFile "assets/edit_gallery_showcase_1.jpg" 3473559
      "18b04ac991809a0cebddeec915b01b94fae5a94c00c3055a94dbeb7ad20b4b52"
      "sha256-GLBKyZGAmgzr3e7JFbAblPrlqUwAwwValNvretILS1I="
    )
    (mkFile "assets/edit_gallery_showcase_2.jpg" 3983759
      "0422949b4dc8c82c7172adb837744c2bff9e48b009b47e9f6dd3136f3d29cfe9"
      "sha256-BCKUm03IyCxxcq24N3RMK/+eSLAJtH6fbdMTbz0pz+k="
    )
    (mkFile "assets/general.jpg" 2252562
      "f3bcdcc89b69a604e82c58cf29d472c8cc7fc56f0b4a88e2c8fe1172e173a5ef"
      "sha256-87zcyJtppgToLFjPKdRyyMx/xW8LSojiyP4RcuFzpe8="
    )
    (mkFile "assets/mage-flow-cover.png" 2551049
      "38c0e930ccd4f6169d644cf350d2ed99503c5aca98a96049d2dc755c3e5c8292"
      "sha256-OMDpMMzU9hadZEzzUNLtmVA8WsqYqWBJ0tx1XD5cgpI="
    )
    (mkFile "assets/mage_vae.jpg" 254985
      "5f5d152b9f049bc6c0d7601f448456c1834747ee06c713f7b9856b6b219d43ae"
      "sha256-X10VK58Em8bA12AfRIRWwYNHR+4GxxP3uYVrayGdQ64="
    )
    (mkFile "assets/multiref_000000_0.jpg" 45473
      "1c6deb67312a377225792074b8ef7b4d1bc99fe81b5ecc33a462ef10a524d02c"
      "sha256-HG3rZzEqN3IleSB0uO97TRvJn+gbXswzpGLvEKUk0Cw="
    )
    (mkFile "assets/multiref_000000_1.png" 824404
      "c58549bd7fc1992f84615df9128cbc6cf24e8b2b8aba55f2521b6f278d144ca9"
      "sha256-xYVJvX/BmS+EYV35Eoy8bPJOiyuKulXyUhtvJ40UTKk="
    )
    (mkFile "assets/nr_mmdit.jpg" 470704
      "11d128f23e121e6eb4a228c5d848ba986d78c989205971ca8e8b8f93369b878c"
      "sha256-EdEo8j4SHm60oijF2Ei6mG14yYkgWXHKjouPkzabh4w="
    )
    (mkFile "assets/one_to_many_editing_diversity.jpg" 259747
      "33b3b590596193c0b7fdb32bd5139696924d3d38829ab78a4eefa127f9f91e90"
      "sha256-M7O1kFlhk8C3/bMr1ROWlpJNPTiCmreKTu+hJ/n5HpA="
    )
    (mkFile "assets/portrait.jpg" 1827782
      "599eacf83cd0a8bb19cc3cc79fd6a94b38891917bfcf27bb278ae7a4bcb33d0e"
      "sha256-WZ6s+DzQqLsZzDzHn9apSziJGRe/zye7J4rnpLyzPQ4="
    )
    (mkFile "assets/t2i_teaser.jpg" 1150108
      "a94ad93cb9d77344da044f0b9a48c326771cc93d5bf689986d31674ace42ccc2"
      "sha256-qUrZPLnXc0TaBE8LmkjDJnccyT1b9omYbTFnSs5CzMI="
    )
    (mkFile "assets/text_en.jpg" 2088960
      "24b4c332bfa239f5e6ef2c31c85f7e51c70d31c59b5cf23a81a710af1f441d11"
      "sha256-JLTDMr+iOfXm7ywxyF9+UccNMcWbXPI6gacQrx9EHRE="
    )
    (mkFile "assets/text_zh.jpg" 1936946
      "b79d49a353176b4b14a40ee371d2444f9cdeb45e54d877c4730180443af395d7"
      "sha256-t51Jo1MXa0sUpA7jcdJET5zetF5U2HfEcwGARDrzldc="
    )
    (mkFile "model_index.json" 497 "d380701c58a36f8906cdae8388e166cffe2a9c08e24013bbdc691bcb16e7aa04"
      "sha256-04BwHFijb4kGza6DiOFmz/4qnAjiQBO73GkbyxbnqgQ="
    )
    (mkFile "scheduler/scheduler_config.json" 169
      "438fd8bcf254740e5d3f3e9800bbd9c571e342ab87885388d1505b7531c69c02"
      "sha256-Q4/YvPJUdA5dPz6YALvZxXHjQquHiFOI0VBbdTHGnAI="
    )
    (mkFile "text_encoder/.gitattributes" 1519
      "11ad7efa24975ee4b0c3c3a38ed18737f0658a5f75a0a96787b576a78a023361"
      "sha256-Ea1++iSXXuSww8OjjtGHN/Blil91oKlnh7V2p4oCM2E="
    )
    (mkFile "text_encoder/README.md" 7133
      "a884e5e78f7d6f7bfe237f909dbc41a126542e259dc79d8ab33cc8980580ff79"
      "sha256-qITl5499b3v+I3+QnbxBoSZULiWdx52KszzImAWA/3k="
    )
    (mkFile "text_encoder/chat_template.json" 5502
      "6f8a6a55027e3da5160105556cda5dd69f6423f1c32645f6730d32de7773d0c4"
      "sha256-b4pqVQJ+PaUWAQVVbNpd1p9kI/HDJkX2cw0y3ndz0MQ="
    )
    (mkFile "text_encoder/config.json" 1505
      "edac7703329133edfc53e46ac0081835144c99d7eebf28b71c732694d435224d"
      "sha256-7ax3AzKRM+38U+RqwAgYNRRMmdfuvyi3HHMmlNQ1Ik0="
    )
    (mkFile "text_encoder/generation_config.json" 269
      "8469742d1fce0de951c8909b26a2c0c0d8490837ce476efb114da9e0cefc4d44"
      "sha256-hGl0LR/ODelRyJCbJqLAwNhJCDfOR277EU2p4M78TUQ="
    )
    (mkFile "text_encoder/merges.txt" 1671839
      "599bab54075088774b1733fde865d5bd747cbcc7a547c5bc12610e874e26f5e3"
      "sha256-WZurVAdQiHdLFzP96GXVvXR8vMelR8W8EmEOh04m9eM="
    )
    (mkFile "text_encoder/model-00001-of-00002.safetensors" 4967229296
      "30a01a0556622645a3cce87b655bbbbbc1f170c196099f1b666c93202c3339a9"
      "sha256-MKAaBVZiJkWjzOh7ZVu7u8HxcMGWCZ8bZmyTICwzOak="
    )
    (mkFile "text_encoder/model-00002-of-00002.safetensors" 3908490048
      "046296a2a387efb43b0c997d5833c789604d168834f6e0d3064bf7bb13d002a6"
      "sha256-BGKWoqOH77Q7DJl9WDPHiWBNFog09uDTBkv3uxPQAqY="
    )
    (mkFile "text_encoder/model.safetensors.index.json" 64742
      "58a7841d7bff2548dd91577d216274a83cf1b500bc6a534b809d6c1b1707cf2b"
      "sha256-WKeEHXv/JUjdkVd9IWJ0qDzxtQC8alNLgJ1sGxcHzys="
    )
    (mkFile "text_encoder/preprocessor_config.json" 390
      "27225450ac9c6529872ee1924fcb0962ff5634834f817040f444118116f4e516"
      "sha256-JyJUUKycZSmHLuGST8sJYv9WNINPgXBA9EQRgRb05RY="
    )
    (mkFile "text_encoder/tokenizer.json" 7032403
      "a5d85b6dcc535e6b93115a9ef287e6132fdbf30270da6218194ba742261173c7"
      "sha256-pdhbbcxTXmuTEVqe8ofmEy/b8wJw2mIYGUunQiYRc8c="
    )
    (mkFile "text_encoder/tokenizer_config.json" 10868
      "c2da771801886ad9ae98181793ffd3dfb7f1af30f6f7c6a4e15d7dbba52e2399"
      "sha256-wtp3GAGIatmumBgXk//T37fxrzD298ak4V19u6UuI5k="
    )
    (mkFile "text_encoder/video_preprocessor_config.json" 385
      "7768af27c1fafa9cc9011c1dc20067e03f8915e03b63504550e11d5066986d13"
      "sha256-d2ivJ8H6+pzJARwdwgBn4D+JFeA7Y1BFUOEdUGaYbRM="
    )
    (mkFile "text_encoder/vocab.json" 2776833
      "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"
      "sha256-yhDX6fs+0YV13R4neiV5wW0QjjLydDloSvoOELFECRA="
    )
    (mkFile "transformer/config.json" 709
      "8493c3b2722738c2a824ac82b1fd9c89fefb4e354fc88363207193db7fe702de"
      "sha256-hJPDsnInOMKoJKyCsf2cif77TjVPyINjIHGT23/nAt4="
    )
    (mkFile "vae/config.json" 112 "abd124d603d6c6a03e9d0f2aa6d113b8c4afda0738400bdf2f99240aeaeaff76"
      "sha256-q9Ek1gPWxqA+nQ8qptETuMSv2gc4QAvfL5kkCurq/3Y="
    )
    (mkFile "vae/diffusion_pytorch_model.safetensors" 345053056
      "34e076dc1e8a15321e1e07be5111d59cf16dd10b804b7c7e20b4de29013427e0"
      "sha256-NOB23B6KFTIeHge+URHVnPFt0QuAS3x+ILTeKQE0J+A="
    )
  ];

  mkMageFlow =
    {
      repository,
      revision,
      variant,
      files,
    }:
    {
      kind = "model";
      maker = "Microsoft (mage-flow-community mirror)";
      notes = "Full upstream BF16 Mage-Flow ${variant} snapshot. Load its immutable directory with the MageFlowPipeline/CLI; this diffusion model is not a llama-swap backend.";
      source = {
        layout = "snapshot";
        localName = repository;
        hfUrl = "https://huggingface.co/mage-flow-community/${repository}";
        inherit revision;
        primary = "model_index.json";
        files = mageFlowCommonFiles ++ files;
      };
    };
in
{
  mage-flow-4b-turbo-bf16 = mkMageFlow {
    repository = "Mage-Flow-Turbo";
    revision = "65bb3500f0da9df6a41ec6383716fc02cf014773";
    variant = "text-to-image Turbo (4-step)";
    files = [
      (mkFile ".gitattributes" 2792 "1a56e4250c336521cf860fa77a9df0d13d2ef57d7215d6928434078a3953a0f2"
        "sha256-GlbkJQwzZSHPhg+nep3w0T0u9X1yFdaShDQHijlToPI="
      )
      (mkFile "README.md" 33684 "868eb8c61a4ac113f9ed2ea76f0b2863d46c3c9286aa4dfef470fbbf56564de7"
        "sha256-ho64xhpKwRP57S6nbwsoY9RsPJKGqk3+9HD7v1ZWTec="
      )
      (mkFile "transformer/diffusion_pytorch_model.safetensors" 8231536760
        "6df47df3d7efc9ebdad075b87b3e9e4f74d09dca672d592271788f0ee27ab97d"
        "sha256-bfR989fvyeva0HW4ez6eT3TQncpnLVkicXiPDuJ6uX0="
      )
    ];
  };

  mage-flow-edit-4b-turbo-bf16 = mkMageFlow {
    repository = "Mage-Flow-Edit-Turbo";
    revision = "66df6fa1aba5b40cd4120739134292eab9779da3";
    variant = "image-editing Turbo (4-step)";
    files = [
      (mkFile ".gitattributes" 2792 "1a56e4250c336521cf860fa77a9df0d13d2ef57d7215d6928434078a3953a0f2"
        "sha256-GlbkJQwzZSHPhg+nep3w0T0u9X1yFdaShDQHijlToPI="
      )
      (mkFile "README.md" 33694 "f8de31f661ceb77b0d5880e5d9075e4dabed9e2ffdff957977c8431a42cb580d"
        "sha256-+N4x9mHOt3sNWIDl2QdeTavtni/9/5V5d8hDGkLLWA0="
      )
      (mkFile "transformer/diffusion_pytorch_model.safetensors" 8231536760
        "29c3726ecd64afe149eef28af3e27b6b40de52646bfd16757a37da4b6fbcf288"
        "sha256-KcNybs1kr+FJ7vKK8+J7a0DeUmRr/RZ1ejfaS2+88og="
      )
    ];
  };

  mage-vl-bf16 = {
    kind = "model";
    maker = "Microsoft";
    notes = "Full official BF16 Mage-VL snapshot: image/video understanding, traditional and neural codec paths, and the proactive streaming gate. The future online route must use the upstream feat/mage-vl SGLang branch behind llama-swap; no compatible backend is declared yet.";
    source = {
      layout = "snapshot";
      localName = "Mage-VL";
      hfUrl = "https://huggingface.co/microsoft/Mage-VL";
      revision = "5c78cab61938e73859b63724d9bf5cb88c477eaa";
      primary = "config.json";
      files = [
        (mkFile ".gitattributes" 1947 "e3645ea2e6944c6af3f1d2b3ef56af6df1e48572e45ad9f30c446dfe70873fd3"
          "sha256-42ReouaUTGrz8dKz71avbfHkhXLkWtnzDERt/nCHP9M="
        )
        (mkFile "README.md" 25218 "1afb0d0c11ba448a854aa1b560a66beff25326b41e03056540eeba94265742e3"
          "sha256-GvsNDBG6RIqFSqG1YKZr7/JTJrQeAwVlQO66lCZXQuM="
        )
        (mkFile "added_tokens.json" 605 "58b54bbe36fc752f79a24a271ef66a0a0830054b4dfad94bde757d851968060b"
          "sha256-WLVLvjb8dS95okonHvZqCggwBUtN+tlL3nV9hRloBgs="
        )
        (mkFile "assets/mage-vl-cover.png" 2712894
          "f5a8f9a516d1d26b4798e9633fbca431b10d7065fa6f3c05df3b2a3bbbe3abff"
          "sha256-9aj5pRbR0mtHmOljP7ykMbENcGX6bzwF3zsqO7vjq/8="
        )
        (mkFile "assets/mage-vl-framework.png" 1522442
          "9a62ff5d41f67f420f3d32426358eee2fd56870eb07cd09a0e6f3a7fa96291f4"
          "sha256-mmL/XUH2f0IPPTJCY1ju4v1Whw6wfNCaDm86f6likfQ="
        )
        (mkFile "chat_template.jinja" 1017
          "a0bc6f6fc7a29a80017a433e8f03a1cc1236e838a944a2d034295a60c4f2fddb"
          "sha256-oLxvb8eimoABekM+jwOhzBI26DipRKLQNClaYMTy/ds="
        )
        (mkFile "codec_video_processing_mage_vl.py" 26124
          "4dadf463f79a315b253ff05f4e8a57421a1c2538bed1ebd3652fe412e373e0fd"
          "sha256-Ta30Y/eaMVslP/BfTopXQhocJTi+0evTZS/kEuNz4P0="
        )
        (mkFile "config.json" 3243 "fd4621212569e893ce2caa110431fde73f3cc1a1d92e1b8320bb4e0cfbcad34a"
          "sha256-/UYhISVp6JPOLKoRBDH95z88waHZLhuDILtODPvK00o="
        )
        (mkFile "configuration_mage_vl.py" 4926
          "7e3da0c90726ef33da4f0362b3c71dc28650003f1cc11e061d3e99404a8bfed8"
          "sha256-fj2gyQcm7zPaTwNis8cdwoZQAD8cwR4GHT6ZQEqL/tg="
        )
        (mkFile "examples/dog.jpg" 525201 "164d8dfe707fb854e288ad2eea65c2db87e90af11f689c85502860eeaf3f4794"
          "sha256-Fk2N/nB/uFTiiK0u6mXC24fpCvEfaJyFUChg7q8/R5Q="
        )
        (mkFile "examples/soccer-broadcast.mp4" 3914911
          "9d840e86558fe5a59bb743092d161228c63c687ab53588ee476a1cd46064125a"
          "sha256-nYQOhlWP5aWbt0MJLRYSKMY8aHq1NYjuR2oc1GBkElo="
        )
        (mkFile "generation_config.json" 121
          "8b9afb365eaab1c8fc2395f618067ee2307b9821e207f12c5c52cf371a14b0e0"
          "sha256-i5r7Nl6qscj8I5X2GAZ+4jB7mCHiB/EsXFLPNxoUsOA="
        )
        (mkFile "inference.py" 5990 "b70b06ef25073f3178c156859da658c61e26dc8d1baad2f56a9c37acbfa7f12b"
          "sha256-twsG7yUHPzF4wVaFnaZYxh4m3I0bqtL1apw3rL+n8Ss="
        )
        (mkFile "merges.txt" 1671853 "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"
          "sha256-iDHk8aBERxNA98CoPXvXEwaluGfpX9hw900MUwipBNU="
        )
        (mkFile "model-00001-of-00002.safetensors" 4967403560
          "98fa203652a843650343732d2597f08c9b491cf4e310cd269eed34ca27ebce58"
          "sha256-mPogNlKoQ2UDQ3MtJZfwjJtJHPTjEM0mnu00yifrzlg="
        )
        (mkFile "model-00002-of-00002.safetensors" 4516272328
          "719360069004f6b7b59303bd21bc1111bcd353bb0ccdebe1fe3971b87cd7b30f"
          "sha256-cZNgBpAE9re1kwO9IbwREbzTU7sMzevh/jlxuHzXsw8="
        )
        (mkFile "model.safetensors.index.json" 65768
          "2cad26f4364750d9b0551dff11e776837b9ef822fe29e068f68d935a8e65cc54"
          "sha256-LK0m9DZHUNmwVR3/Eed2g3ue+CL+KeBo9o2TWo5lzFQ="
        )
        (mkFile "modeling_mage_vl.py" 72783
          "3fe8bb1e40fa38db4ae08da097ee1238aa4258c4d454e66fe93a44d08ab641ec"
          "sha256-P+i7HkD6ONtK4I2gl+4SOKpCWMTUVOZv6TpE0Iq2Qew="
        )
        (mkFile "neural_codec/DCVC/LICENSE.txt" 1074
          "7c77a44a8acd9b41fdc209864a8016b3d430b5d0e09309818d5b7444336df744"
          "sha256-fHekSorNm0H9wgmGSoAWs9QwtdDgkwmBjVt0RDNt90Q="
        )
        (mkFile "neural_codec/DCVC/NOTICE.txt" 14429
          "ecd478088d8f3cdf2a9378c35ebb83213a5470c84750875c53081e212241f651"
          "sha256-7NR4CI2PPN8qk3jDXruDITpUcMhHUIdcUwgeISJB9lE="
        )
        (mkFile "neural_codec/DCVC/src/cpp/py_rans/py_rans.cpp" 15043
          "8d7bf63b3877e15e6a49f28b52bfd1f343f5899de0461fc6c155c885d9e512f1"
          "sha256-jXv2Ozh34V5qSfKLUr/R80P1iZ3gRh/GwVXIhdnlEvE="
        )
        (mkFile "neural_codec/DCVC/src/cpp/py_rans/py_rans.h" 2456
          "b7ebdd2f00d685486f24317ed2efa09a4772e06aba02932ee696377e6d64e3d4"
          "sha256-t+vdLwDWhUhvJDF+0u+gmkdy4Gq6ApMu5pY3fm1k49Q="
        )
        (mkFile "neural_codec/DCVC/src/cpp/py_rans/rans.cpp" 17735
          "fd78ff143d4f62b6b7393b8468eaa6558b8e6fd5021b15f84b8c7b22ae3e9a72"
          "sha256-/Xj/FD1PYra3OTuEaOqmVYuOb9UCGxX4S4x7Iq4+mnI="
        )
        (mkFile "neural_codec/DCVC/src/cpp/py_rans/rans.h" 6986
          "9b15dc5c77bcbf9bde1ce88c7bb357b5170bb8601ef9852960335999eafb5261"
          "sha256-mxXcXHe8v5veHOiMe7NXtRcLuGAe+YUpYDNZmer7UmE="
        )
        (mkFile "neural_codec/DCVC/src/cpp/py_rans/rans_byte.h" 5077
          "a5d057d14657c8acc4a24300f2aa9424ff0544b42e92551a17a746fd0cc70a77"
          "sha256-pdBX0UZXyKzEokMA8qqUJP8FRLQuklUaF6dG/QzHCnc="
        )
        (mkFile "neural_codec/DCVC/src/cpp/setup.py" 820
          "36ade348d410279cc0043a6d20ba3105c6aae30c593250ed2424431950785307"
          "sha256-Nq3jSNQQJ5zABDptILoxBcaq4wxZMlDtJCRDGVB4Uwc="
        )
        (mkFile "neural_codec/DCVC/src/layers/cuda_inference.py" 7071
          "9641636f1d6e06bfd18ac9f94837f3cfeeb64b77253988cc7f54f0e2be2e6433"
          "sha256-lkFjbx1uBr/Risn5SDfzz+62S3clOYjMf1Tw4r4uZDM="
        )
        (mkFile "neural_codec/DCVC/src/layers/extensions/inference/bind.cpp" 1661
          "a6047535c368a38446a3edbe584e4511cfc441b0c858f9d11f57d8cbcd8e6ca6"
          "sha256-pgR1NcNoo4RGo+2+WE5FEc/EQbDIWPnRH1fYy82ObKY="
        )
        (mkFile "neural_codec/DCVC/src/layers/extensions/inference/common.h" 10154
          "7825d382f8e01f80dcc777b4075984301e072a6340112d03ddfa341ddeeadd7b"
          "sha256-eCXTgvjgH4Dcx3e0B1mEMB4HKmNAES0D3fo0Hd7q3Xs="
        )
        (mkFile "neural_codec/DCVC/src/layers/extensions/inference/def.h" 5639
          "f495c634944c6482e7282a2beb80373a1416f1b8ee73d6a015b3f52a5b79f066"
          "sha256-9JXGNJRMZILnKCor64A3OhQW8bjuc9agFbP1Klt58GY="
        )
        (mkFile "neural_codec/DCVC/src/layers/extensions/inference/impl.cpp" 6666
          "985728101e8556ddd0ec3fe39aad7edd4de4c082bc3b7559ba0e1f48d2f7d683"
          "sha256-mFcoEB6FVt3Q7D/jmq1+3U3kwIK8O3VZug4fSNL31oM="
        )
        (mkFile "neural_codec/DCVC/src/layers/extensions/inference/kernel.cu" 47400
          "875aff392b0dca42af382ae48c0dceaba5672239fec710e47ae7e616c2cd92a3"
          "sha256-h1r/OSsNykKvOCrkjA3Oq6VnIjn+xxDkeufmFsLNkqM="
        )
        (mkFile "neural_codec/DCVC/src/layers/extensions/inference/setup.py" 1202
          "aae9650bbffd90425dc83ff9611f359d05bc4457a37daf8b87ed48d90951656b"
          "sha256-qullC7/9kEJdyD/5YR81nQW8RFejfa+Lh+1I2QlRZWs="
        )
        (mkFile "neural_codec/DCVC/src/layers/layers.py" 5475
          "2839de3e14029c2c384849d58c233c6eaf1d66d8386eb5e8713e2b5aed4bfb10"
          "sha256-KDnePhQCnCw4SEnVjCM8bq8dZtg4brXocT4rWu1L+xA="
        )
        (mkFile "neural_codec/DCVC/src/models/common_model.py" 13211
          "b93f028ee97891c01bfd291a22edcb63f8664cdfcc78b8d5a21c8f98558777a1"
          "sha256-uT8Cjul4kcAb/SkaIu3LY/hmTN/MeLjVohyPmFWHd6E="
        )
        (mkFile "neural_codec/DCVC/src/models/entropy_models.py" 13366
          "9f01781847cbff2afd3d2b2ce6b14b1a0905bb1da41ca5e20e68ab4a031e0e57"
          "sha256-nwF4GEfL/yr9PSss5rFLGgkFux2kHKXiDmirSgMeDlc="
        )
        (mkFile "neural_codec/DCVC/src/models/image_model.py" 7864
          "b72fbfb95c392e68aea3bd0820c53c4ec901a8372e203319a5f8372547dbb37d"
          "sha256-ty+/uVw5Lmiuo70IIMU8TskBqDcuIDMZpfg3JUfbs30="
        )
        (mkFile "neural_codec/DCVC/src/models/video_model.py" 13075
          "3ba7094ef0ef938897bdfefcea18ebe2d9c79743768348c2d33a3a70a85ead8a"
          "sha256-O6cJTvDvk4iXvf786hjr4tnHl0N2g0jC0zo6cKherYo="
        )
        (mkFile "neural_codec/DCVC/src/utils/common.py" 6756
          "e3db33408fe0e4f3f659ab77b40c903cd3fd91ee7ec2dd007d33cfad06e87b36"
          "sha256-49szQI/g5PP2Wat3tAyQPNP9ke5+wt0AfTPPrQboezY="
        )
        (mkFile "neural_codec/DCVC/src/utils/metrics.py" 3174
          "986aa1c803aca94d651a1eb3c3f7690f36045a02053972e0275000f1b4f780f9"
          "sha256-mGqhyAOsqU1lGh6zw/dpDzYEWgIFOXLgJ1AA8bT3gPk="
        )
        (mkFile "neural_codec/DCVC/src/utils/stream_helper.py" 6035
          "40fb73b75fd2d96b371c5d5733928c83e1c785c40e8b89a93ea4414af5431bf1"
          "sha256-QPtzt1/S2Ws3HF1XM5KMg+HHhcQOi4mpPqRBSvVDG/E="
        )
        (mkFile "neural_codec/DCVC/src/utils/transforms.py" 1623
          "8d07100e2e531357f4a315db33e3ae137076b2378d1835888fc6055dfb46fe55"
          "sha256-jQcQDi5TE1f0oxXbM+OuE3B2sjeNGDWIj8YFXftG/lU="
        )
        (mkFile "neural_codec/DCVC/src/utils/video_reader.py" 2759
          "33476bef2c7815ba09e7b706a0596347b30e43e68c227f0a851bfc0c3d9fec82"
          "sha256-M0dr7yx4FboJ57cGoFljR7MOQ+aMIn8KhRv8DD2f7II="
        )
        (mkFile "neural_codec/DCVC/src/utils/video_writer.py" 1402
          "53b76c28abc4058b602c7c2cac6c0189d669cdd0af9464bcb6a77e1ab25283dd"
          "sha256-U7dsKKvEBYtgLHwsrGwBidZpzdCvlGS8tqd+GrJSg90="
        )
        (mkFile "neural_codec/README.md" 3253
          "66b7285cb259dc8f2885940513dcd2506d0e74f6d0396fd528a34dcca3cf6cf2"
          "sha256-ZrcoXLJZ3I8ohZQFE9zSUG0OdPbQOW/VKKNNzKPPbPI="
        )
        (mkFile "neural_codec/canvas_assembler.py" 9100
          "8bd6b8eb549111fbf930e2751986ce88eb6d66d090df86a8c125469d4413f06a"
          "sha256-i9a461SREfv5MOJ1GYbOiOttZtCQ34aowSVGnUQT8Go="
        )
        (mkFile "neural_codec/codec_dcvc_config.py" 2899
          "a088776acf7e1c59bfb2cb298ceb3e9e6346644c18ad55ecd475eb045bb074f4"
          "sha256-oIh3as9+HFm/ssspjOs+nmNGZEwYrVXs1HXrBFuwdPQ="
        )
        (mkFile "neural_codec/codec_loader.py" 3899
          "23e7cf09b645585165cf274f9f4222bb6782bf13e7c1f2c28208848584198387"
          "sha256-I+fPCbZFWFFlzydPn0Iiu2eCvxPnwfLCggiEhYQZg4c="
        )
        (mkFile "neural_codec/codec_tools/__init__.py" 0
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
          "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="
        )
        (mkFile "neural_codec/codec_tools/codec_patch_gop/__init__.py" 252
          "f0f4216f435695a06d78af3d92a41b624056a64ba43befcea8a8e5940377df75"
          "sha256-8PQhb0NWlaBteK89kqQbYkBWpkukO+/OqKjllAN333U="
        )
        (mkFile "neural_codec/codec_tools/codec_patch_gop/energy_sampling.py" 21471
          "8a8ae72111f55dbfd5104ac040d0385931e497a37323a147582b4734240b8719"
          "sha256-iornIRH1Xb/VEErAQNA4WTHkl6NzI6FHWCtHNCQLhxk="
        )
        (mkFile "neural_codec/codec_tools/codec_patch_gop/frame_utils.py" 17735
          "b7495f41e65fa5d6d66e0d735d0e4a178b02b58cd22ee1ecb4375d999e54c437"
          "sha256-t0lfQeZfpdbWbg1zXQ5KF4sCtYzSLuHstDddmZ5UxDc="
        )
        (mkFile "neural_codec/codec_tools/codec_patch_gop/patch_utils.py" 5229
          "d1dae44745ec5bef7aae540141cddb45c51cf4fb3a9ed710a28c005d043f22fe"
          "sha256-0drkR0XsW+96rlQBQc3bRcUc9Ps6ntcQoowAXQQ/Iv4="
        )
        (mkFile "neural_codec/codec_tools/codec_patch_gop/scoring.py" 3969
          "a2360c44338e94fdb3b51627cad47b34f5e8b16a8f4882ddd78a568d2f4896df"
          "sha256-ojYMRDOOlP2ztRYnytR7NPXosWqPSILd14pWjS9Ilt8="
        )
        (mkFile "neural_codec/codec_tools/codec_patch_gop/utils.py" 6472
          "2d660b068cc5cad1842815729e4222e9fd685833239c0ee252e2d32bd7cebac2"
          "sha256-LWYLBozFytGEKBVynkIi6f1oWDMjnA7iUuLTK9fOusI="
        )
        (mkFile "neural_codec/codec_tools/codec_patch_gop/video_probe.py" 10691
          "ecfda73ebcc8d4f3e116faf764822df675bd57f149c3c8f9ac83b15f2ca12667"
          "sha256-7P2nPrzI1PPhFvr3ZIIt9nW9V/FJw8j5rIOxXyyhJmc="
        )
        (mkFile "neural_codec/codec_tools/codec_patch_gop/video_processor.py" 71859
          "0c316cc3ba49d36fb81029a0731f4ded059d9f42688ab6627d868868a32d1d59"
          "sha256-DDFsw7pJ02+4ECmgcx9N7QWdn0JoirZifYaIaKMtHVk="
        )
        (mkFile "neural_codec/codec_tools/pipeline/__init__.py" 0
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
          "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="
        )
        (mkFile "neural_codec/codec_tools/pipeline/generate_codec_patch_smart_resize.py" 110346
          "6a5293550f504eaf2e2ba73604b9bec922966d157c9ec3682bccb3e5cac57d9b"
          "sha256-alKTVQ9QTq8uK6c2BLm+ySKWbRV8nsNoK8yz5crFfZs="
        )
        (mkFile "neural_codec/codec_tools/pipeline/process_video_bitcost_mv_mask_collage.py" 66163
          "16c870cd8e7e85d0193216258e97e7ad13fbd86732af76bff407daaad08bb079"
          "sha256-FshwzY5+hdAZMhYljpfnrRP72Gcyr3a/9AfaqtCLsHk="
        )
        (mkFile "neural_codec/codec_tools/pipeline/process_video_bitcost_readiness.py" 29212
          "1502206b7136e3d168b8b8cdf389a61d9b0a6517ce02946247eb21ed0586f603"
          "sha256-FQIga3E249FouLjN84mmHZsKZRfOApRiR+sh7QWG9gM="
        )
        (mkFile "neural_codec/dcvc_readiness_gen.py" 5854
          "e6bb6761a58fff91b4bb8d0ccf88fee7a7cc9d82880a4190f749178f4fa43c12"
          "sha256-5rtnYaWP/5G0u40Mz4j+56fMnYKICkGQ90kXj0+kPBI="
        )
        (mkFile "neural_codec/dcvc_rt_engine.py" 12054
          "97cc52781ff58275df319f9128cfb675e920b9c1373290d132d96e9989e10443"
          "sha256-l8xSeB/1gnXfMZ+RKM+2dekgucE3MpDRMtlumYnhBEM="
        )
        (mkFile "neural_codec/dcvc_rt_inter.tar" 82899063
          "b12e7faf4ddb6126d8e138a627ed6a349b8e1052d3ed9e343e1ba266466675d6"
          "sha256-sS5/r03bYSbY4TimJ+1qNJuOEFLT7Z40PhuiZkZmddY="
        )
        (mkFile "neural_codec/dcvc_rt_intra.tar" 182764252
          "555eff5f4026774f477bebdcbb3b52548e0da230803959dcebcea4d732a90dd9"
          "sha256-VV7/X0Amd09He+vcuztSVI4NojCAOVnc686k1zKpDdk="
        )
        (mkFile "neural_codec/infer_dcvc_rt.py" 5118
          "5e5929bf7497c116f135fce086cb04a4007a2de4d4a39fa4c2ff7c9eaf5fb7dd"
          "sha256-Xlkpv3SXwRbxNfzghssEpAB6LeTUo5+kwv98nq9ft90="
        )
        (mkFile "neural_codec/precompute_dcvc_rt.py" 12167
          "f7b4835ad43653c73bdd9bb61e889fb60c1a8688e42fc40d6eb2f71c3b48e12e"
          "sha256-97SDWtQ2U8c73Zu2HoiftgwahojkL8QNbrL3HDtI4S4="
        )
        (mkFile "neural_codec/reproduce_bench.py" 6500
          "ec72d3ce5c8b937972257dae895b6ab42367a0bbed3660066f6b9e07adb2b8ae"
          "sha256-7HLTzlyLk3lyJX2uiVtqtCNnoLvtNmAGb2ueB62yuK4="
        )
        (mkFile "preprocessor_config.json" 1813
          "86401f541a46dee7689e84444b87cfa556e1575f1994a446582dc58d919cc69e"
          "sha256-hkAfVBpG3udonoRES4fPpVbhV18ZlKRGWC3FjZGcxp4="
        )
        (mkFile "processing_mage_vl.py" 23652
          "43f72035c055439187e06fe06dd459fbf4a103da7374d75ded63cd745368fe33"
          "sha256-Q/cgNcBVQ5GH4G/gbdRZ+/ShA9pzdNdd7WPNdFNo/jM="
        )
        (mkFile "special_tokens_map.json" 613
          "76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd"
          "sha256-doYudlJmuFqpRZdn4zy68Tlw8yeg6I0cZYRsLd06Hs0="
        )
        (mkFile "streammind_gate.py" 5102 "5d9a9d7525aeecc0360ffd43f891ce9d2220297df5092a293a98e2fd31e9d99d"
          "sha256-XZqddSWu7MA2D/1D+JHOnSIgKX31CSopOpji/THp2Z0="
        )
        (mkFile "streammind_gate.safetensors" 1073494728
          "01938c515679c1130cff2e6a2af2e4cbc3aad10ea7ccb29229e64c2cfdbf6535"
          "sha256-AZOMUVZ5wRMM/y5qKvLky8Oq0Q6nzLKSKeZMLP2/ZTU="
        )
        (mkFile "tokenizer.json" 11422064 "ba0c439f7be467bf47d12a7e6f9adc6116201056fc60c67f431c679b7c16afc8"
          "sha256-ugxDn3vkZ79H0Sp+b5rcYRYgEFb8YMZ/Qxxnm3wWr8g="
        )
        (mkFile "tokenizer_config.json" 4750
          "f64d944a98d2d9901581be7a5f36b626ff2dc0d5b7d5dedb412412ca39606df0"
          "sha256-9k2USpjS2ZAVgb56Xza2Jv8twNW31d7bQSQSyjlgbfA="
        )
        (mkFile "video_preprocessor_config.json" 465
          "9d8345e0c7be09da56d8ea535fa6a5fa1a35728ccec9e7dbffa030ba34ce4a72"
          "sha256-nYNF4Me+CdpW2OpTX6al+ho1cozOyefb/6AwujTOSnI="
        )
        (mkFile "video_processing_mage_vl.py" 28368
          "67f28ea772c260b131983e8a90ad15948134a1baa769bfe6adbf0dd383541acb"
          "sha256-Z/KOp3LCYLExmD6KkK0VlIE0obqnab/mrb8N04NUGss="
        )
        (mkFile "vocab.json" 2776833 "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"
          "sha256-yhDX6fs+0YV13R4neiV5wW0QjjLydDloSvoOELFECRA="
        )
      ];
    };
  };
}
