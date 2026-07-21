{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.local-models;
  catalog = import ../lib/local-models.nix { inherit lib; };
  modelStore = import ../lib/model-store.nix {
    inherit catalog lib pkgs;
  };
  system = pkgs.stdenv.hostPlatform.system;
  strixAi = inputs.nix-strix-halo.packages.${system};
  host = config.networking.hostName;

  deploymentList = builtins.attrValues catalog.deployments;
  canonicalForHost = lib.filterAttrs (
    _: deployment: deployment.status == "canonical" && lib.elem host deployment.hosts
  ) catalog.deployments;
  canonicalList = builtins.attrValues canonicalForHost;
  canonicalModelIds = map (deployment: deployment.model) canonicalList;
  peerDeployments = lib.filter (deployment: deployment.peer != null) canonicalList;
  gpuDeployments = lib.filterAttrs (_: deployment: deployment.peer == null) canonicalForHost;

  peerNames = lib.unique (map (deployment: deployment.peer.name) peerDeployments);
  peers = lib.genAttrs peerNames (
    peerName:
    let
      members = lib.filter (deployment: deployment.peer.name == peerName) peerDeployments;
    in
    {
      proxy = (builtins.head members).peer.proxy;
      models = map (deployment: deployment.model) members;
    }
  );
  peerUnits = lib.unique (
    lib.filter (unit: unit != null) (map (deployment: deployment.peer.systemdUnit) peerDeployments)
  );

  referencedArtifactIds =
    deployment: lib.filter (artifactId: artifactId != null) (builtins.attrValues deployment.artifacts);
  hostArtifactIds = lib.unique (
    lib.concatMap referencedArtifactIds (builtins.attrValues gpuDeployments)
  );
  hostArtifactPackages = map (
    artifactId: modelStore.materialized.${artifactId}.package
  ) hostArtifactIds;

  resolveArtifacts =
    deployment:
    lib.mapAttrs (
      _: artifactId: if artifactId == null then null else modelStore.materialized.${artifactId}.primary
    ) deployment.artifacts;

  expandRuntimeArg =
    deploymentName: resolved: arg:
    lib.foldl' (
      expanded: slot:
      let
        token = "@${slot}@";
        path = resolved.${slot};
      in
      if lib.hasInfix token expanded && path == null then
        throw "local-model deployment ${deploymentName}: ${token} has no artifact"
      else if path == null then
        expanded
      else
        lib.replaceStrings [ token ] [ (toString path) ] expanded
    ) arg (builtins.attrNames resolved);

  renderModel =
    deploymentName: deployment:
    let
      resolved = resolveArtifacts deployment;
      modelPath = resolved.model;
      runtimeArgs = map (expandRuntimeArg deploymentName resolved) deployment.runtime.args;
      extraArgs = lib.concatMapStringsSep " " lib.escapeShellArg runtimeArgs;
      command =
        if deployment.backend == "rocm" then
          "${strixAi.llama-cpp-rocm}/bin/llama-server --port \${PORT} -m ${lib.escapeShellArg (toString modelPath)}"
        else if deployment.backend == "vulkan" then
          "${strixAi.llama-cpp-vulkan}/bin/llama-server --port \${PORT} -m ${lib.escapeShellArg (toString modelPath)}"
        else if deployment.backend == "ds4" then
          "${strixAi.ds4-rocm}/bin/ds4-server --host 127.0.0.1 --port \${PORT} -m ${lib.escapeShellArg (toString modelPath)}"
        else
          throw "local-model deployment ${deploymentName}: backend ${deployment.backend} has no llama-swap command renderer yet";
    in
    {
      name = deployment.model;
      value = {
        name = deployment.model;
        cmd = command + lib.optionalString (runtimeArgs != [ ]) " ${extraArgs}";
      };
    };

  gpuModels = lib.mapAttrs' renderModel gpuDeployments;

  artifactIds = builtins.attrNames catalog.artifacts;
  deploymentIds = builtins.attrNames catalog.deployments;
  artifactRows = builtins.attrValues catalog.artifacts;
  peerProxyFor =
    peerName:
    lib.unique (
      map (deployment: deployment.peer.proxy) (
        lib.filter (deployment: deployment.peer != null && deployment.peer.name == peerName) deploymentList
      )
    );
  manifest = (pkgs.formats.json { }).generate "local-model-catalog.json" catalog;

  catalogAssertions = [
    {
      assertion = lib.all (
        artifact: lib.elem artifact.source.primary (map (file: file.path) artifact.source.files)
      ) artifactRows;
      message = "Every local-model artifact primary must name one of its source files.";
    }
    {
      assertion = lib.all (
        artifact:
        let
          basenames = map (file: builtins.baseNameOf file.path) artifact.source.files;
        in
        builtins.length basenames == builtins.length (lib.unique basenames)
      ) artifactRows;
      message = "Split local-model artifact files must have unique basenames.";
    }
    {
      assertion = lib.all (
        deployment: lib.all (artifactId: lib.elem artifactId artifactIds) (referencedArtifactIds deployment)
      ) deploymentList;
      message = "Every local-model deployment artifact reference must exist in the artifact catalog.";
    }
    {
      assertion = lib.all (
        deployment:
        if deployment.peer == null then
          deployment.artifacts.model != null
        else
          referencedArtifactIds deployment == [ ]
      ) deploymentList;
      message = "Local GPU deployments require a model artifact; external peers must not root artifacts.";
    }
    {
      assertion = lib.all (
        deployment:
        deployment.status != "canonical" || deployment.peer != null || lib.elem "worker" deployment.hosts
      ) deploymentList;
      message = "Every canonical GPU deployment must be assigned to the exhaustive worker roster.";
    }
    {
      assertion = builtins.length canonicalModelIds == builtins.length (lib.unique canonicalModelIds);
      message = "Canonical llama-swap model IDs must be unique per host.";
    }
    {
      assertion = lib.all (
        deployment: lib.all (arg: !(lib.hasInfix "-hf" arg)) deployment.runtime.args
      ) deploymentList;
      message = "Runtime model downloads (-hf) are forbidden; use pinned store artifacts.";
    }
    {
      assertion = lib.all (peerName: builtins.length (peerProxyFor peerName) == 1) peerNames;
      message = "All deployments on one llama-swap peer must use the same proxy URL.";
    }
    {
      assertion = lib.all (
        deployment:
        (deployment.supersedes == null || lib.elem deployment.supersedes deploymentIds)
        && (deployment.supersededBy == null || lib.elem deployment.supersededBy deploymentIds)
      ) deploymentList;
      message = "Local-model lineage must reference another deployment row.";
    }
  ];
  failedCatalogAssertion = lib.findFirst (entry: !entry.assertion) null catalogAssertions;
  catalogValid =
    if failedCatalogAssertion == null then true else throw failedCatalogAssertion.message;
in
{
  options.services.local-models.downloadAllModels = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Materialize every canonical model artifact assigned to this host and
      expose it through llama-swap. False evaluates metadata only and roots no
      roster weights in the NixOS closure.
    '';
  };

  config = {
    assertions = catalogAssertions;

    # Metadata is generational and inspectable even while downloads are disabled.
    environment.etc."local-models/catalog.json".source = manifest;

    services.llama-swap.settings =
      assert catalogValid;
      {
        inherit peers;
        models = if cfg.downloadAllModels then gpuModels else { };
      };

    # This is the only branch that roots weight FODs. With the committed false
    # setting, Nix never needs to resolve or fetch any catalog artifact.
    system.extraDependencies = lib.optionals cfg.downloadAllModels hostArtifactPackages;

    systemd.services.llama-swap = lib.mkIf (peerUnits != [ ]) {
      wants = peerUnits;
      after = peerUnits;
    };
  };
}
