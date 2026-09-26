{ upstream, source }:
upstream.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./hold-space.patch ];
  # Upstream deliberately excludes these fixtures from its release source set.
  # Our native input tests need them to compile the existing unit-test binary.
  # Merged into, never nested: the release source set may already carry part of
  # a directory (v0.9.1 ships distribution/ without latest.json).
  postPatch = (old.postPatch or "") + ''
    mkdir -p tests distribution
    cp -rT --no-preserve=mode ${source}/tests ./tests
    cp -rT --no-preserve=mode ${source}/distribution ./distribution
  '';
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    cargo test --offline --release --bin herdr dictation_
    runHook postCheck
  '';
})
