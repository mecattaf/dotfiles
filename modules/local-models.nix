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
    inherit catalog lib;
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

  # The host's wanted-set manifest: the ONLY thing nix contributes about
  # weights (2026-08-21 decisive ruling — weights are static documents, never
  # store paths; see lib/model-store.nix). local-models-sync reconciles
  # /var/lib/local-models against this before llama-swap starts.
  wantedManifest = (pkgs.formats.json { }).generate "local-models-wanted.json" (
    modelStore.manifestFor hostArtifactIds
  );

  syncScript = pkgs.writeShellApplication {
    name = "local-models-sync";
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      manifest=/etc/local-models/wanted.json
      library=${lib.escapeShellArg cfg.libraryPath}
      root=${lib.escapeShellArg modelStore.runtimeRoot}
      mkdir -p "$root"
      chmod 0755 "$root"
      fail=0

      # Converge every wanted file. Present + right size → untouched (the
      # no-catalog-change nightly moves zero bytes, by ruling). Missing or
      # wrong size → copy from the Library, sha256-verify, land atomically.
      while IFS=$'\t' read -r id name bytes oid; do
        dest="$root/$id/$name"
        src="$library/$id/$name"
        if [ -e "$dest" ] && [ "$(stat -c %s "$dest")" = "$bytes" ]; then
          continue
        fi
        if [ ! -e "$src" ]; then
          echo "local-models-sync: MISSING in Library: $id/$name (run library-fetch on the NAS?)" >&2
          fail=1
          continue
        fi
        echo "local-models-sync: borrowing $id/$name ($bytes bytes)"
        mkdir -p "$(dirname "$dest")"
        cp "$src" "$dest.part"
        actual="$(sha256sum "$dest.part" | cut -d' ' -f1)"
        if [ "$actual" != "$oid" ]; then
          echo "local-models-sync: HASH MISMATCH for $id/$name (want $oid got $actual)" >&2
          rm -f "$dest.part"
          fail=1
          continue
        fi
        chmod 0644 "$dest.part"
        mv -f "$dest.part" "$dest"
      done < <(jq -r '.[] | .id as $id | .files[] | [$id, .name, (.bytes|tostring), .oid] | @tsv' "$manifest")

      # Prune only after a fully clean pass: artifacts (and stray files inside
      # kept artifacts) that the manifest no longer wants. Always re-borrowable
      # — the Library is the archive; device dirs are working copies.
      if [ "$fail" = 0 ]; then
        for dir in "$root"/*/; do
          [ -e "$dir" ] || continue
          id="$(basename "$dir")"
          if ! jq -e --arg id "$id" 'any(.[]; .id == $id)' "$manifest" >/dev/null; then
            echo "local-models-sync: pruning retired artifact $id"
            rm -rf "$dir"
            continue
          fi
          while IFS= read -r f; do
            rel="''${f#"$root/$id/"}"
            if ! jq -e --arg id "$id" --arg rel "$rel" \
              'any(.[]; .id == $id and any(.files[]; .name == $rel))' "$manifest" >/dev/null; then
              echo "local-models-sync: pruning stray file $id/$rel"
              rm -f "$f"
            fi
          done < <(find "$dir" -type f ! -name '*.part')
          find "$dir" -type d -empty -delete
        done
      fi
      exit "$fail"
    '';
  };

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
        ttl = deployment.ttl;
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
      # Archive-before-delete, made mechanical (2026-08-20): a retirement is
      # only real once the bytes survive somewhere. The `archived` receipt on
      # the row is the proof; without it the retirement does not evaluate.
      assertion = lib.all (deployment: deployment.status != "retired" || deployment.archived != null) deploymentList;
      message = "Every retired deployment must carry an `archived` receipt (NAS path + date) — archive the weights before retiring the row (docs/nas/model-archive.md).";
    }
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
      message = "Runtime model downloads (-hf) are forbidden; weights arrive only via the NAS Library flow (catalog row -> library-fetch -> local-models-sync).";
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

    libraryPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/nas/models/weights";
      description = ''
        Where this host reads the NAS model Library from (the coordinator's
        NFS mount by default; the worker mounts the read-only models export
        at /mnt/library). local-models-sync borrows wanted artifacts from
        here into /var/lib/local-models.
      '';
    };
  };

  config = {
    assertions = catalogAssertions;

    # Metadata stays generational and inspectable alongside the selected artifacts.
    environment.etc = {
      "local-models/catalog.json".source = manifest;
      "local-models/wanted.json".source = wantedManifest;
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

    # Weights live OUTSIDE the store (2026-08-21 decisive ruling): the sync
    # oneshot below converges /var/lib/local-models against wanted.json from
    # the NAS Library before llama-swap starts. World-readable on purpose —
    # llama-swap's DynamicUser sandbox reads these paths through
    # ProtectSystem=strict.
    systemd.tmpfiles.rules = lib.mkIf (hostArtifactIds != [ ]) [
      "d ${modelStore.runtimeRoot} 0755 root root -"
    ];

    systemd.services.local-models-sync = lib.mkIf (hostArtifactIds != [ ]) {
      description = "Borrow this host's model weights from the NAS Library";
      wantedBy = [ "multi-user.target" ];
      # Re-run on activation whenever the wanted-set changes; a no-change
      # rebuild restarts nothing and moves nothing.
      restartTriggers = [ wantedManifest ];
      # The Library lives across the network on every host; do not race the
      # uplink at boot. Ordering only — the real anti-race guard is per-host
      # on the mount itself (the worker gates on the NAS actually answering,
      # hosts/worker/default.nix, dotfiles#240; NM's "online" word alone was
      # measured insufficient there).
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = [ cfg.libraryPath ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe syncScript;
        # First borrow of a 39G model over the LAN takes ~8 min; several, more.
        TimeoutStartSec = "2h";
      };
    };

    # llama-swap starts after the working copies are converged. `wants`, not
    # `requires`: a failed borrow (Library unreachable) leaves llama-swap up
    # serving whatever is already local — only the missing rows error on use.
    systemd.services.llama-swap = lib.mkIf (hostArtifactIds != [ ]) {
      wants = [ "local-models-sync.service" ];
      after = [ "local-models-sync.service" ];
    };
  };
}
