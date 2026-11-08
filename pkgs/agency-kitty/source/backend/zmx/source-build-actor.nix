{ lib, stdenvNoCC, fetchurl, fetchzip, runCommand, gitMinimal, cacert, binutils }:

# Isolated candidate only. Production source-build.nix and its default are unchanged.
# Source-only build of the experimental stable-libghostty actor holder. The dependency
# derivation is fixed-output: neither the final compiler invocation nor its
# install phase has network access in the Nix sandbox.
let
  version = "1.0.1-agency.5-actor";
  upstreamCommit = "a35f00a2118b15a5e9d522a43035c8d7487df9b7";
  ghosttyCommit = "0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec";
  dependencyHash = "sha256-/5RgHb3mceLj1j3u5OG2xbyVCGCN0bvf7EErCGzbVcY=";
  patchFile = ./agency-actor.patch;
  source = fetchzip {
    url = "https://codeload.github.com/neurosnap/zmx/tar.gz/${upstreamCommit}";
    extension = "tar.gz";
    hash = "sha256-aud/azC9TpnKs4jJrXBWO0LXWUFgu7u6Gg2z9jgc79g=";
  };
  zig = stdenvNoCC.mkDerivation {
    pname = "agency-zig";
    version = "0.17.0";
    src = fetchurl {
      url = "https://ziglang.org/download/0.17.0/zig-x86_64-linux-0.17.0.tar.xz";
      sha256 = "1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026";
    };
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    dontPatchELF = true;
    installPhase = ''
      mkdir -p "$out"
      cp -R . "$out/"
    '';
    meta.platforms = [ "x86_64-linux" ];
  };
  dependencies = runCommand "agency-zmx-${version}-zig-dependencies" {
    nativeBuildInputs = [ gitMinimal cacert ];
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = dependencyHash;
    preferLocalBuild = false;
  } ''
    cp -R ${source} source
    chmod -R u+w source
    cd source
    patch -p1 < ${patchFile}
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    export NIX_SSL_CERT_FILE="$SSL_CERT_FILE"
    ${zig}/zig build --fetch=needed -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl
    # Ghostty's native image/SIMD dependencies are lazy in nested path
    # packages. --fetch=needed alone omits them; --fetch=all would fetch GUI
    # dependencies too. Fetch precisely the two native dependencies required
    # by this build and check their upstream Zig content hashes as well.
    # Zig0.17 only materializes a fetch into --pkg-dir with --save; without
    # --save it caches a compressed global archive. The temporary manifest
    # additions are discarded and are never part of the actual source build.
    cp build.zig.zon build.zig.zon.original
    ${zig}/zig fetch --save=agency_highway --pkg-dir zig-pkg https://deps.files.ghostty.org/highway-66486a10623fa0d72fe91260f96c892e41aceb06.tar.gz
    test -d zig-pkg/N-V-__8AAGmZhABbsPJLfbqrh6JTHsXhY6qCaLAQyx25e0XE
    ${zig}/zig fetch --save=agency_wuffs --pkg-dir zig-pkg https://deps.files.ghostty.org/wuffs-7411f488fe2e2c205c3d3b3d28638b7356522930.tar.gz
    test -d zig-pkg/N-V-__8AAP5JWgCGP_AD0teWpa4krRvE9VPZzvviGdbmN4jI
    mv build.zig.zon.original build.zig.zon
    mkdir -p "$out"
    cp -R zig-pkg/. "$out/"
  '';
in
stdenvNoCC.mkDerivation {
  pname = "agency-zmx-actor";
  inherit version;
  outputs = [ "out" "debug" ];
  src = source;
  patches = [ patchFile ];
  dontConfigure = true;
  dontStrip = true;
  dontPatchELF = true;
  strictDeps = true;
  buildPhase = ''
    runHook preBuild
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
    cp -R ${dependencies} zig-pkg
    chmod -R u+w zig-pkg
    ${zig}/zig build -j4 -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl
    runHook postBuild
  '';
  # Runtime gates run through runtime-test on compute after the sandboxed source
  # build. A build derivation must not acquire a live user's runtime directory.
  doCheck = false;
  installPhase = ''
    runHook preInstall
    install -Dm755 zig-out/bin/zmx "$out/bin/zmx"
    # Keep symbols available for review without pulling the whole compiler and
    # source cache into the runtime closure through DWARF source filenames.
    mkdir -p "$debug/lib/debug/agency-zmx"
    ${binutils}/bin/objcopy --only-keep-debug "$out/bin/zmx" "$debug/lib/debug/agency-zmx/zmx.debug"
    ${binutils}/bin/strip --strip-debug "$out/bin/zmx"
    ${binutils}/bin/objcopy --add-gnu-debuglink="$debug/lib/debug/agency-zmx/zmx.debug" "$out/bin/zmx"
    install -Dm644 ${./LICENSE.upstream} "$out/share/doc/agency-zmx/LICENSE.upstream"
    install -Dm644 ${./NOTICE.actor} "$out/share/doc/agency-zmx/NOTICE"
    install -Dm644 ${patchFile} "$out/share/doc/agency-zmx/agency.patch"
    cp -R ${./licenses} "$out/share/doc/agency-zmx/licenses"
    cat > "$out/share/doc/agency-zmx/source-build.json" <<EOF
    {"version":"${version}","upstream_commit":"${upstreamCommit}","ghostty_commit":"${ghosttyCommit}","patch_sha256":"${builtins.hashFile "sha256" patchFile}","zig_version":"0.17.0","target":"x86_64-linux-musl","optimization":"ReleaseSafe","dependency_hash":"${dependencyHash}"}
    EOF
    (cd "$out"; sha256sum bin/zmx > share/doc/agency-zmx/binary.sha256)
    runHook postInstall
  '';
  passthru = {
    inherit upstreamCommit ghosttyCommit dependencies zig;
    patchSha256 = builtins.hashFile "sha256" patchFile;
  };
  meta = {
    description = "Experimental bounded exclusive shadow-VT actor; not the default holder";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "zmx";
    outputsToInstall = [ "out" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}
