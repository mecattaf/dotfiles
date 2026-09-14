{
  lib,
  runCommand,
  fetchurl,
  python3,
  makeWrapper,
}:
let
  source = fetchurl {
    url = "https://github.com/dscripka/openWakeWord/archive/refs/tags/v0.6.0.tar.gz";
    hash = "sha256-knuBiPlBQLFvwH6JFuc1ysmH+o9z7VSmVpMq6eWB6F8=";
  };
  python = python3.withPackages (ps: [
    ps.numpy
    ps.onnxruntime
    ps.scipy
    ps.scikit-learn
    ps.requests
    ps.tqdm
  ]);
in
runCommand "upstream-openwakeword-0.6.0-fixture"
  {
    nativeBuildInputs = [ makeWrapper ];
    meta.license = lib.licenses.asl20;
  }
  ''
    mkdir -p $out/lib $out/bin
    tar -xzf ${source}
    cp -r openWakeWord-0.6.0/openwakeword $out/lib/
    cp openWakeWord-0.6.0/LICENSE $out/lib/LICENSE-openWakeWord
    cp ${./openwakeword.py} $out/lib/replay.py
    makeWrapper ${python}/bin/python3 $out/bin/openwakeword-fixture \
      --set PYTHONPATH $out/lib --set OPENBLAS_NUM_THREADS 1 --set OMP_NUM_THREADS 1 \
      --set MKL_NUM_THREADS 1 --add-flags $out/lib/replay.py
  ''
