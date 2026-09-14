let
  pinned = builtins.fetchTree {
    type = "github";
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "da39501c8d0a093136854eddcd6927c8a8bb0d8f";
    narHash = "sha256-guyexwrrF5GBKqjO0eg9LNIvrXn4j2frNak63sDr8zg=";
  };
  p = import pinned { };
  compiler = import ./compiler.nix { pkgs = p; };
  runtimeLib = p.runCommand "openvino-with-isolated-npu-compiler" { } ''
    mkdir -p $out/lib/openvino
    for f in ${p.openvino.lib}/lib/*.so*; do ln -s "$f" $out/lib/; done
    for f in ${p.openvino.lib}/lib/openvino/*; do ln -s "$f" $out/lib/openvino/; done
    for f in ${compiler}/lib/*.so*; do ln -s "$f" $out/lib/openvino/; done
    rm $out/lib/openvino/libopenvino_intel_npu_plugin.so
    cp -aL ${p.openvino.lib}/lib/openvino/libopenvino_intel_npu_plugin.so $out/lib/openvino/
    rm $out/lib/libopenvino.so*
    cp -aL ${p.openvino.lib}/lib/libopenvino.so.2026.3.1 $out/lib/
    ln -s libopenvino.so.2026.3.1 $out/lib/libopenvino.so.2631
    ln -s libopenvino.so.2026.3.1 $out/lib/libopenvino.so
  '';
  py = p.python3.withPackages (ps: [
    ps.openvino
    ps.numpy
  ]);
in
p.symlinkJoin {
  name = "scott-wake-npu-compatibility";
  paths = [
    py
    p.intel-npu-driver
    p.level-zero
    compiler
  ];
  nativeBuildInputs = [ p.makeWrapper ];
  postBuild = ''
    makeWrapper ${py}/bin/python3 $out/bin/wake-python \
      --prefix LD_LIBRARY_PATH : ${
        p.lib.makeLibraryPath [
          runtimeLib
          p.intel-npu-driver
          p.level-zero
          compiler
        ]
      } \
      --set OMP_NUM_THREADS 1 --set OPENBLAS_NUM_THREADS 1
  '';
}
