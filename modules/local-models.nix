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
  selectedDeployments = lib.filterAttrs (name: _: lib.elem name cfg.allow) catalog.deployments;
  selectedList = builtins.attrValues selectedDeployments;
  peerDeployments = lib.filter (deployment: deployment.peer != null) selectedList;
  gpuDeployments = lib.filterAttrs (_: deployment: deployment.peer == null) selectedDeployments;

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

  modelRenderers = import ../lib/local-model-runtime.nix {
    inherit lib;
    packages = {
      llamaRocm = strixAi.llama-cpp-rocm;
      llamaVulkan = strixAi.llama-cpp-vulkan;
      ds4 = strixAi.ds4-rocm;
      vllm = strixAi.vllm-rocm;
      mlxLm = strixAi.mlx-lm;
    };
  };
  rendererBackends = builtins.attrNames modelRenderers;

  referencedArtifactIds =
    deployment: lib.filter (artifactId: artifactId != null) (builtins.attrValues deployment.artifacts);
  deploymentArtifactIds = lib.unique (
    lib.concatMap referencedArtifactIds (builtins.attrValues gpuDeployments)
  );
  hostArtifactIds = lib.unique (deploymentArtifactIds ++ cfg.artifacts);
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
      modelArtifact = modelStore.materialized.${deployment.artifacts.model};
      modelPath = modelArtifact.primary;
      modelDirectory = modelArtifact.directory;
      runtimeArgs = map (expandRuntimeArg deploymentName resolved) deployment.runtime.args;
      extraArgs = lib.concatMapStringsSep " " lib.escapeShellArg runtimeArgs;
      renderer = modelRenderers.${deployment.backend} or null;
      rendered =
        if renderer == null then
          throw "local-model deployment ${deploymentName}: backend ${deployment.backend} has no llama-swap command renderer"
        else
          renderer { inherit deployment modelDirectory modelPath; };
    in
    {
      name = deployment.model;
      value = rendered // {
        name = deployment.model;
        cmd = rendered.cmd + lib.optionalString (runtimeArgs != [ ]) " ${extraArgs}";
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
  artifactEtc = lib.listToAttrs (
    map (artifactId: {
      name = "local-models/artifacts/${artifactId}";
      value.source = modelStore.materialized.${artifactId}.directory;
    }) cfg.artifacts
  );

  catalogAssertions = [
    {
      assertion =
        lib.sort builtins.lessThan rendererBackends
        == lib.sort builtins.lessThan catalog.backendKinds.local;
      message = "Every local-model backend must have exactly one llama-swap command renderer.";
    }
    {
      assertion = lib.all (
        deployment:
        if deployment.peer == null then
          lib.elem deployment.backend catalog.backendKinds.local
        else
          lib.elem deployment.backend catalog.backendKinds.peers
      ) deploymentList;
      message = "Local deployments must use rendered backends and peers must use peer-only backends.";
    }
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
    {
      assertion = builtins.length cfg.allow == builtins.length (lib.unique cfg.allow);
      message = "services.local-models.allow must not contain duplicate deployment IDs.";
    }
    {
      assertion = lib.all (deploymentId: lib.elem deploymentId deploymentIds) cfg.allow;
      message = "services.local-models.allow references an unknown deployment ID.";
    }
    {
      assertion = lib.all (
        deployment: deployment.status == "canonical" && lib.elem host deployment.hosts
      ) selectedList;
      message = "Every allowed local-model deployment must be canonical and assigned to this host.";
    }
    {
      assertion = builtins.length cfg.artifacts == builtins.length (lib.unique cfg.artifacts);
      message = "services.local-models.artifacts must not contain duplicate artifact IDs.";
    }
    {
      assertion = lib.all (artifactId: lib.elem artifactId artifactIds) cfg.artifacts;
      message = "services.local-models.artifacts references an unknown artifact ID.";
    }
  ];
  failedCatalogAssertion = lib.findFirst (entry: !entry.assertion) null catalogAssertions;
  catalogValid =
    if failedCatalogAssertion == null then true else throw failedCatalogAssertion.message;
in
{
  options.services.local-models = {
    allow = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Canonical deployment IDs to materialize and expose through llama-swap
        on this host. Catalog entries not named here remain metadata-only.
      '';
    };

    artifacts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Additional artifact IDs to materialize without adding a llama-swap
        model row. This is for modality-specific appliances such as ASR/TTS.
      '';
    };
  };

  config = {
    assertions = catalogAssertions;

    # Metadata stays generational and inspectable alongside the selected artifacts.
    environment.etc = {
      "local-models/catalog.json".source = manifest;
    }
    // artifactEtc;

    services.llama-swap.settings =
      assert catalogValid;
      {
        inherit peers;
        models = gpuModels;
      };

    # Only the explicit per-host deployment/artifact lists root weight FODs.
    system.extraDependencies = hostArtifactPackages;

    systemd.services.llama-swap = lib.mkIf (peerUnits != [ ]) {
      wants = peerUnits;
      after = peerUnits;
    };
  };
}
