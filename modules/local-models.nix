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
  isSafeArtifactPath =
    path:
    path != ""
    && !(lib.hasPrefix "/" path)
    && lib.all (component: component != "" && component != "." && component != "..") (
      lib.splitString "/" path
    );

  deploymentList = builtins.attrValues catalog.deployments;
  canonicalForHost = lib.filterAttrs (
    _: deployment: deployment.status == "canonical" && lib.elem host deployment.hosts
  ) catalog.deployments;
  canonicalList = builtins.attrValues canonicalForHost;
  canonicalModelIds = map (deployment: deployment.model) canonicalList;
  selectedDeployments = lib.filterAttrs (name: _: lib.elem name cfg.allow) catalog.deployments;
  selectedList = builtins.attrValues selectedDeployments;

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
  deploymentArtifactIds = lib.unique (lib.concatMap referencedArtifactIds selectedList);
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

  localModels = lib.mapAttrs' renderModel selectedDeployments;

  artifactIds = builtins.attrNames catalog.artifacts;
  deploymentIds = builtins.attrNames catalog.deployments;
  artifactRows = builtins.attrValues catalog.artifacts;
  manifest = (pkgs.formats.json { }).generate "local-model-catalog.json" catalog;
  artifactEtc = lib.listToAttrs (
    map (artifactId: {
      name = "local-models/artifacts/${artifactId}";
      value.source = modelStore.materialized.${artifactId}.directory;
    }) cfg.artifacts
  );
  snapshotAliasArtifacts = lib.filterAttrs (
    artifactId: artifact: lib.elem artifactId cfg.artifacts && artifact.source.localName != null
  ) catalog.artifacts;
  snapshotAliasNames = map (artifact: artifact.source.localName) (
    builtins.attrValues snapshotAliasArtifacts
  );
  snapshotAliasEtc = lib.mapAttrs' (
    artifactId: artifact:
    lib.nameValuePair "local-models/snapshots/${artifact.source.localName}" {
      source = modelStore.materialized.${artifactId}.directory;
    }
  ) snapshotAliasArtifacts;

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
        lib.elem deployment.backend (catalog.backendKinds.local ++ catalog.backendKinds.appliances)
      ) deploymentList;
      message = "Every deployment must use a declared local or appliance backend.";
    }
    {
      assertion = lib.all (
        artifact: lib.elem artifact.source.primary (map (file: file.path) artifact.source.files)
      ) artifactRows;
      message = "Every local-model artifact primary must name one of its source files.";
    }
    {
      assertion = lib.all (
        artifact: lib.all (file: isSafeArtifactPath file.path) artifact.source.files
      ) artifactRows;
      message = "Local-model artifact paths must be safe repository-relative paths.";
    }
    {
      assertion = lib.all (
        artifact:
        let
          paths = map (file: file.path) artifact.source.files;
        in
        builtins.length paths == builtins.length (lib.unique paths)
      ) artifactRows;
      message = "Local-model artifacts must not repeat a repository-relative path.";
    }
    {
      assertion = lib.all (
        artifact:
        let
          basenames = map (file: builtins.baseNameOf file.path) artifact.source.files;
        in
        artifact.source.layout == "snapshot"
        || builtins.length basenames == builtins.length (lib.unique basenames)
      ) artifactRows;
      message = "Flat local-model artifact files must have unique basenames.";
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
        if lib.elem deployment.backend catalog.backendKinds.local then
          deployment.artifacts.model != null
        else
          referencedArtifactIds deployment == [ ]
      ) deploymentList;
      message = "Managed local deployments require a model artifact; runtime appliances must not root artifacts.";
    }
    {
      assertion = builtins.length canonicalModelIds == builtins.length (lib.unique canonicalModelIds);
      message = "Canonical public model IDs must be unique per host.";
    }
    {
      assertion = lib.all (
        deployment: lib.all (arg: !(lib.hasInfix "-hf" arg)) deployment.runtime.args
      ) deploymentList;
      message = "Runtime model downloads (-hf) are forbidden; use pinned store artifacts.";
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
        deployment:
        deployment.status == "canonical"
        && lib.elem host deployment.hosts
        && lib.elem deployment.backend catalog.backendKinds.local
      ) selectedList;
      message = "Every allowed local-model deployment must be a canonical managed backend assigned to this host.";
    }
    {
      assertion = builtins.length cfg.artifacts == builtins.length (lib.unique cfg.artifacts);
      message = "services.local-models.artifacts must not contain duplicate artifact IDs.";
    }
    {
      assertion = lib.all (artifactId: lib.elem artifactId artifactIds) cfg.artifacts;
      message = "services.local-models.artifacts references an unknown artifact ID.";
    }
    {
      assertion = lib.all (
        name: isSafeArtifactPath name && builtins.baseNameOf name == name
      ) snapshotAliasNames;
      message = "Local-model snapshot aliases must be safe single directory names.";
    }
    {
      assertion = builtins.length snapshotAliasNames == builtins.length (lib.unique snapshotAliasNames);
      message = "Selected local-model snapshot aliases must be unique.";
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
        on this host. Runtime appliances such as FastFlowLM stay outside this
        list and are invoked through their own explicit CLI.
      '';
    };

    artifacts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Additional artifact IDs to materialize without adding a llama-swap
        model row. This is for complete snapshots and modality-specific
        appliances such as Mage, ASR, and TTS.
      '';
    };
  };

  config = {
    assertions = catalogAssertions;

    # Metadata stays generational and inspectable alongside the selected artifacts.
    environment.etc = {
      "local-models/catalog.json".source = manifest;
    }
    // artifactEtc
    // snapshotAliasEtc;

    services.llama-swap.settings =
      assert catalogValid;
      {
        models = localModels;
        # Runtime appliances are deliberately not represented as proxy peers.
        peers = { };
      };

    # Only the explicit per-host deployment/artifact lists root weight FODs.
    system.extraDependencies = hostArtifactPackages;

  };
}
