{
  catalog,
  lib,
  pkgs,
}:

let
  safeName = name: lib.replaceStrings [ "/" ":" " " ] [ "-" "-" "-" ] name;

  fetchFile =
    artifactId: source: file:
    pkgs.fetchurl {
      url = "${lib.removeSuffix "/" source.hfUrl}/resolve/${source.revision}/${file.path}";
      hash = file.hash;
      # Snapshot members use a content-derived name, so byte-identical files
      # get the same fixed-output store path even when repositories place them
      # at different relative paths. Flat artifacts retain their
      # artifact-qualified names for backwards compatibility.
      name =
        if source.layout == "snapshot" then
          "hf-snapshot-sha256-${file.oid}"
        else
          "${safeName artifactId}-${builtins.baseNameOf file.path}";
    };

  materializeArtifact =
    artifactId: artifact:
    let
      fetched = map (file: {
        inherit (file) path;
        derivation = fetchFile artifactId artifact.source file;
      }) artifact.source.files;
      directory = pkgs.linkFarm "local-model-${safeName artifactId}" (
        map (file: {
          name = if artifact.source.layout == "snapshot" then file.path else builtins.baseNameOf file.path;
          path = file.derivation;
        }) fetched
      );
      package =
        if artifact.source.layout == "flat" && builtins.length fetched == 1 then
          (builtins.head fetched).derivation
        else
          directory;
      primary =
        if artifact.source.layout == "flat" && builtins.length fetched == 1 then
          package
        else
          "${package}/${
            if artifact.source.layout == "snapshot" then
              artifact.source.primary
            else
              builtins.baseNameOf artifact.source.primary
          }";
    in
    {
      inherit directory package primary;
    };

  materialized = lib.mapAttrs materializeArtifact catalog.artifacts;
in
{
  inherit materialized;
  packages = lib.mapAttrs (_: artifact: artifact.package) materialized;
}
