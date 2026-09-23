{
  lib,
  runCommand,
  skopeo,
  jq,
}:
# Turn a dockerTools image (a docker-archive tarball) into an OCI image layout
# at the output root (oci-layout, index.json, blobs/) plus a `digest` file with
# the manifest digest (sha256:...). That is the shape myAxFleet.registrySeed
# takes: the NAS pushes it with `skopeo copy --preserve-digests`, so the digest
# a manifest or a Task names is the digest the registry serves.
#
# The digest is read at BUILD time, inside this derivation, and consumers read
# it from "${layout}/digest" in their own build steps. No import-from-derivation.
{
  name,
  image,
  tag ? "latest",
}:
runCommand "${lib.replaceStrings [ "/" ] [ "-" ] name}-oci"
  {
    nativeBuildInputs = [
      skopeo
      jq
    ];
    passthru = { inherit image tag; };
  }
  ''
    export HOME=$TMPDIR
    # gzip layers: these images cross the coordinator's wifi leg when pulled.
    skopeo --insecure-policy --tmpdir "$TMPDIR" copy --quiet \
      --dest-compress --dest-compress-format gzip \
      docker-archive:${image} oci:$out:${tag}
    jq -r '.manifests[0].digest' $out/index.json > $out/digest
    grep -Eq '^sha256:[0-9a-f]{64}$' $out/digest
  ''
