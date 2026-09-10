{
  catalog,
  lib,
}:
# ─── The runtime model store: paths and manifests, never derivations ─────────
#
# REWRITTEN 2026-08-21 (Tom, decisive): "model weights are static items, like
# a large pdf doc that we read — they need NO movement on the nix nightly
# side." The previous version of this file turned every catalog artifact into
# a fetchurl fixed-output derivation rooted via system.extraDependencies,
# which made every host closure carry hundreds of GB of weights. That design
# died the day the update-center tried to build the fleet on the NAS's 57G
# eMMC (2026-08-21, first observed run).
#
# Now this file computes only DATA:
#   - where an artifact's files live at runtime on a device
#     (/var/lib/local-models/<artifactId>/…, optionally populated by the
#     explicit local-models-borrow command in modules/local-models.nix), and
#   - the per-file facts (target name, HF-relative path, bytes, sha256 oid)
#     that the borrow command and NAS library-fetch unit need.
#
# Nix evaluates descriptions and never moves bytes. Weights flow HF → NAS
# Library (/mnt/nas/models/weights) under its independent acquisition action,
# then Library → device only under an explicit operator borrow transaction.
let
  runtimeRoot = "/var/lib/local-models";

  # Flat artifacts collapse to basenames (unique by catalog assertion);
  # snapshot artifacts keep their repository-relative tree.
  targetName = layout: path: if layout == "snapshot" then path else builtins.baseNameOf path;

  materializeArtifact = artifactId: artifact: rec {
    directory = "${runtimeRoot}/${artifactId}";
    primary = "${directory}/${targetName artifact.source.layout artifact.source.primary}";
    files = map (file: {
      # `name` is the path relative to `directory`; `path` is the
      # HF-repository-relative path (what the NAS fetches); `oid` is the
      # git-lfs sha256 in hex — exactly what `sha256sum` verifies against.
      name = targetName artifact.source.layout file.path;
      inherit (file) path bytes oid;
      url = "${lib.removeSuffix "/" artifact.source.hfUrl}/resolve/${artifact.source.revision}/${file.path}";
    }) artifact.source.files;
  };

  materialized = lib.mapAttrs materializeArtifact catalog.artifacts;

  # Manifest rows for a set of artifact ids — the JSON contract shared by the
  # device-side borrow command (name/bytes/oid) and NAS library-fetch (plus url).
  manifestFor =
    artifactIds:
    map (artifactId: {
      id = artifactId;
      files = materialized.${artifactId}.files;
    }) artifactIds;
in
{
  inherit runtimeRoot materialized manifestFor;
}
