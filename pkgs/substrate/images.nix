{
  lib,
  dockerTools,
  runCommand,
  linkFarm,
  fetchurl,
  skopeo,
  jq,
  cacert,
  tzdata,
  # pkgs/substrate/default.nix, built with the fleet's Go 1.27.1.
  substrate,
}:
# Every image the Substrate install and the gVisor WorkerPool pull, as OCI
# layouts the NAS seeds into its registry (modules/ax-fleet/substrate.nix,
# myAxFleet.registrySeed). Each layout carries a `digest` file holding the
# manifest digest, so references are written by digest without IFD: whatever
# needs the digest reads the file at build or run time.
#
#   components  the six Substrate components, nix-built from d277088b, tagged
#               with the version (ate-setup --image-repo/--image-tag resolves
#               each tag to a digest with a HEAD request, then pins it).
#   thirdParty  the images the kind install names by digest, fetched as the
#               linux/amd64 child manifest of the upstream-pinned index
#               (patch 0002), bytes and digest preserved. Fixed-output.
#   gvisor      the runsc tarball SandboxConfig gvisor-default names, fetched
#               with the sha256 that manifest carries.
#
# The whole set is one derivation (a linkFarm) so `nix build` of the flake's
# substrate-images output proves every image; the parts are in passthru.
let
  inherit (substrate) version;

  # ko's default base is gcr.io/distroless/static-debian13 (.ko.yaml). What a
  # static Go binary needs from it: CA roots, zoneinfo, a passwd naming root and
  # nonroot 65532 (atenet runs as 65532, atelet as 0; MEASURED
  # manifests/ate-install), and a world-writable /tmp.
  staticBase = ''
    mkdir -p etc tmp home/nonroot
    chmod 1777 tmp
    cat > etc/passwd <<'EOF'
    root:x:0:0:root:/root:/sbin/nologin
    nonroot:x:65532:65532:nonroot:/home/nonroot:/sbin/nologin
    nobody:x:65534:65534:nobody:/nonexistent:/sbin/nologin
    EOF
    cat > etc/group <<'EOF'
    root:x:0:
    nonroot:x:65532:
    nobody:x:65534:
    EOF
    sed -i 's/^    //' etc/passwd etc/group
  '';

  # docker-archive -> OCI layout plus its manifest digest. Layers are gzipped
  # so the registry and containerd hold compressed blobs, as they would for a
  # ko push.
  toOci =
    {
      image,
      tag,
      repo,
    }:
    runCommand "${lib.replaceStrings [ "/" ] [ "-" ] repo}-${tag}-oci"
      {
        nativeBuildInputs = [
          skopeo
          jq
        ];
        passthru = {
          inherit repo tag image;
        };
      }
      ''
        export HOME=$TMPDIR
        skopeo --insecure-policy --tmpdir "$TMPDIR" copy \
          --dest-compress --dest-compress-format gzip \
          docker-archive:${image} oci:$out:${tag}
        jq -r '.manifests | if length == 1 then .[0].digest else error("expected one manifest") end' \
          $out/index.json > $out/digest
        grep -Eq '^sha256:[0-9a-f]{64}$' $out/digest
      '';

  component =
    name:
    let
      image = dockerTools.buildLayeredImage {
        name = "substrate/${name}";
        tag = version;
        contents = [
          cacert
          tzdata
        ];
        extraCommands = staticBase + ''
          mkdir -p ko-app
          cp ${substrate}/bin/${name} ko-app/${name}
        '';
        config = {
          # ko's layout: the binary at /ko-app/<name> is the entrypoint.
          Entrypoint = [ "/ko-app/${name}" ];
          Env = [
            "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
            "ZONEINFO=${tzdata}/share/zoneinfo"
            "PATH=/ko-app"
          ];
          WorkingDir = "/";
          Labels = {
            "org.opencontainers.image.source" = "https://github.com/agent-substrate/substrate";
            "org.opencontainers.image.revision" = substrate.rev;
            "org.opencontainers.image.version" = version;
          };
        };
      };
    in
    toOci {
      inherit image;
      tag = version;
      repo = "substrate/${name}";
    };

  components = lib.genAttrs substrate.components component;

  # A digest-preserving copy of one upstream manifest. The build fetches the
  # upstream-pinned index, checks that it lists `digest` for linux/amd64, then
  # copies that manifest and its blobs byte for byte. outputHash pins the result.
  thirdPartyImage =
    {
      name,
      upstream,
      index,
      digest,
      repo,
      tag,
      hash,
    }:
    runCommand "${name}-${tag}-oci"
      {
        nativeBuildInputs = [
          skopeo
          jq
        ];
        SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
        impureEnvVars = lib.fetchers.proxyImpureEnvVars;
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        outputHash = hash;
        passthru = {
          inherit
            repo
            tag
            digest
            index
            upstream
            ;
        };
      }
      ''
        export HOME=$TMPDIR
        skopeo --insecure-policy --tmpdir "$TMPDIR" inspect --raw docker://${upstream}@${index} > index.json
        echo "${lib.removePrefix "sha256:" index}  index.json" | sha256sum -c -
        jq -e --arg d ${digest} \
          '[.manifests[] | select(.digest == $d and .platform.os == "linux" and .platform.architecture == "amd64")] | length == 1' \
          index.json
        skopeo --insecure-policy --tmpdir "$TMPDIR" copy --preserve-digests \
          docker://${upstream}@${digest} oci:$out:${tag}
        jq -e --arg d ${digest} '.manifests[0].digest == $d' $out/index.json
        echo ${digest} > $out/digest
      '';

  # upstream index digests: manifests/ate-install at d277088b (MEASURED grep).
  # linux/amd64 children: `skopeo inspect --raw` of each index (MEASURED
  # 2026-09-23); the same values are in patches/0002.
  thirdParty = lib.mapAttrs (name: a: thirdPartyImage (a // { inherit name; })) {
    envoy = {
      upstream = "docker.io/envoyproxy/envoy";
      repo = "envoyproxy/envoy";
      tag = "v1.39-latest";
      index = "sha256:57e14a549d7bd43c8d3f6d03e8cfa653e037d4b38e133acd9b54f38c524401b4";
      digest = "sha256:be87c8b52663c1164a5bdf3c5419017a269cb3d8c74be1ec93638a71f1ffbd4b";
      hash = "sha256-8eny55hV9lIrOBFpRt9Zw563sJHEf5IsJsAgvyYrSNs=";
    };
    postgres = {
      upstream = "docker.io/library/postgres";
      repo = "library/postgres";
      tag = "18-alpine";
      index = "sha256:9a8afca54e7861fd90fab5fdf4c42477a6b1cb7d293595148e674e0a3181de15";
      digest = "sha256:b6a16ed0eb96e2c362811f7eeb951eac8b459e7b40be4149ea5444aa7c65569b";
      hash = "sha256-s0f5LZJr0644wB7RDApe03GXwwNIvvUZD3JXta5qcQQ=";
    };
    rustfs = {
      upstream = "docker.io/rustfs/rustfs";
      repo = "rustfs/rustfs";
      tag = "1.0.0-beta.3";
      index = "sha256:378642b05b7dcb4849fb77ebe6aca4ced1c3f66e7e504247df95a5c9018d3358";
      digest = "sha256:d441111efe3af5bbd6e29eba7cd124f96bb7d49a0612390907f9216d5f970382";
      hash = "sha256-TKKJLC0H9huZDQQNgx8s9xGvpre2bSa2GGArAFfv53s=";
    };
    aws-cli = {
      upstream = "docker.io/amazon/aws-cli";
      repo = "amazon/aws-cli";
      tag = "2.17.0";
      index = "sha256:643507c10ada7964ca6157b3d799f030b90577643da9955d319a77399ed80d73";
      digest = "sha256:7b7edf789765c22d75e61ad6f307c06950e15357b79ea1749104641ce3a11fec";
      hash = "sha256-kZF9g+VfTk5gmtNsZhJNBaX9KceOvDl2s/eWD/ucY00=";
    };
    otel-collector = {
      upstream = "docker.io/otel/opentelemetry-collector-contrib";
      repo = "otel/opentelemetry-collector-contrib";
      tag = "0.157.0";
      index = "sha256:f2f01157055a9b2aab9df7118e1f1c9abf345e99b23bc7a2bc791db374a7d0f6";
      digest = "sha256:4eb842091c796156d4d3c994eb22ba793590f5723719dbf6b8436cb4dfc17f48";
      hash = "sha256-/btIX9XM2O9wkPwAiN6mLJw8JZ2qoB1yzChWcYiEaGY=";
    };
    jaeger = {
      upstream = "docker.io/jaegertracing/all-in-one";
      repo = "jaegertracing/all-in-one";
      tag = "1.55";
      index = "sha256:f6b5d09073f14f76873d300f565a6691d815e81bea8e07e1dc3ff67e0596dd4e";
      digest = "sha256:d5bbf80eb37e3a0d1b1644f17d1c3a7b88abd74177ec06198d4a289b58b41798";
      hash = "sha256-Ag47jLKCMmMczbW0muNZuaOYkMtEHxVYEt9+BkgYWQ0=";
    };
    prometheus = {
      upstream = "docker.io/prom/prometheus";
      repo = "prom/prometheus";
      tag = "v3.5.3";
      index = "sha256:ddc2493835a1509976d5e4e0c94199c4f843ce1f42dd6bcfc8231ba734a93ff7";
      digest = "sha256:442634af681c5988a3ccbd4c6e6ab57e077dc89eead4a31e2abf410501874a92";
      hash = "sha256-yf0l7RsqNY+X6muqRkaK+PlfuUP8w2+2UMaM8I1oUxs=";
    };
    # Named by the patched SandboxConfig as localhost:5000/pause:3.10.2@...;
    # atelet rewrites localhost:5000 to kind-registry:5000, so repo `pause`.
    pause = {
      upstream = "registry.k8s.io/pause";
      repo = "pause";
      tag = "3.10.2";
      index = "sha256:f548e0e8e3dc1896ca956272154dde3314e8cc4fde0a57577ee9fa1c63f5baf4";
      digest = "sha256:412c4a7219cb8a299a37337f3d87810c5340095322e15594a1637785adad0f17";
      hash = "sha256-wQV0nZBm2siOhrsElV7IS1dyk3ppsRzC0TtugyGGxA0=";
    };
  };

  # SandboxConfig gvisor-default's amd64 asset (sandboxconfig-gvisor.yaml:34-35
  # at d277088b). atelet tries anonymous GCS, then its S3 client with the same
  # bucket and key against the in-cluster RustFS; bootstrap step 40 puts this
  # file there, so a node without internet still gets runsc.
  gvisor =
    let
      bucket = "gvisor";
      key = "releases/nightly/2026-09-02/x86_64/gvisor.tar.zstd";
      sha256 = "d547d81401461fd1c679c5c4fa0a6c2b8ef7dc3c22ce23c9e25dcc4c69cfd06f";
    in
    fetchurl {
      name = "gvisor-nightly-2026-09-02-x86_64.tar.zstd";
      url = "https://storage.googleapis.com/${bucket}/${key}";
      inherit sha256;
      passthru = {
        inherit bucket key sha256;
      };
    };

  # The shape myAxFleet.registrySeed takes: name -> { oci, repo, tag }.
  seed =
    lib.mapAttrs' (
      n: v:
      lib.nameValuePair "substrate-${n}" {
        oci = v;
        inherit (v) repo tag;
      }
    ) components
    // lib.mapAttrs (_: v: {
      oci = v;
      inherit (v) repo tag;
    }) thirdParty;
in
linkFarm "substrate-images-${version}" (
  lib.mapAttrsToList (n: v: {
    name = "components/${n}";
    path = v;
  }) components
  ++ lib.mapAttrsToList (n: v: {
    name = "third-party/${n}";
    path = v;
  }) thirdParty
  ++ [
    {
      name = "gvisor/gvisor.tar.zstd";
      path = gvisor;
    }
  ]
)
// {
  inherit
    components
    thirdParty
    gvisor
    seed
    version
    ;
}
