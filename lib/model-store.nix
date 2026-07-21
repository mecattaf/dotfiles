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
      name = "${safeName artifactId}-${builtins.baseNameOf file.path}";
    };

  materializeArtifact =
    artifactId: artifact:
    let
      fetched = map (file: {
        inherit (file) path;
        derivation = fetchFile artifactId artifact.source file;
      }) artifact.source.files;
      package =
        if builtins.length fetched == 1 then
          (builtins.head fetched).derivation
        else
          pkgs.linkFarm "local-model-${safeName artifactId}" (
            map (file: {
              name = builtins.baseNameOf file.path;
              path = file.derivation;
            }) fetched
          );
      primary =
        if builtins.length fetched == 1 then
          package
        else
          "${package}/${builtins.baseNameOf artifact.source.primary}";
    in
    {
      inherit package primary;
    };

  materialized = lib.mapAttrs materializeArtifact catalog.artifacts;
in
{
  inherit materialized;
  packages = lib.mapAttrs (_: artifact: artifact.package) materialized;
}
