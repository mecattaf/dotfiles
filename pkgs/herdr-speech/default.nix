{ upstream, source }:
upstream.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./hold-space.patch ];
  # Upstream deliberately excludes these fixtures from its release source set.
  # Our native input tests need them to compile the existing unit-test binary.
  postPatch = (old.postPatch or "") + ''
    cp -r ${source}/tests ./tests
    cp -r ${source}/distribution ./distribution
  '';
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    cargo test --offline --release --bin herdr dictation_
    runHook postCheck
  '';
})
