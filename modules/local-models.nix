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

  # The host's wanted-set manifest: the ONLY thing Nix contributes about
  # weights (2026-08-21 decisive ruling — weights are static documents, never
  # store paths; see lib/model-store.nix). It is metadata for an explicit
  # operator transaction; evaluating or activating NixOS never moves bytes.
  wantedManifest = (pkgs.formats.json { }).generate "local-models-wanted.json" (
    modelStore.manifestFor hostArtifactIds
  );

  borrowScript = pkgs.writeShellApplication {
    name = "local-models-borrow";
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
      pkgs.findutils
      pkgs.util-linux
      # local-models-prune-audit + local-models-prune-set: the would-prune set,
      # printed and never acted on. See pkgs/local-models-prune.nix.
      pkgs.local-models-prune
    ];
    text = ''
      case "''${1:-}" in
        --dry-run) mode=dry-run ;;
        --yes) mode=apply ;;
        *)
          echo "usage: local-models-borrow --dry-run|--yes" >&2
          echo "Model borrowing is an explicit transaction; NixOS activation never runs it." >&2
          exit 2
          ;;
      esac
      if [ "$#" -ne 1 ]; then
        echo "usage: local-models-borrow --dry-run|--yes" >&2
        exit 2
      fi

      default_library=${lib.escapeShellArg cfg.libraryPath}
      default_root=${lib.escapeShellArg modelStore.runtimeRoot}
      manifest="''${LOCAL_MODELS_MANIFEST:-/etc/local-models/wanted.json}"
      library="''${LOCAL_MODELS_LIBRARY:-$default_library}"
      root="''${LOCAL_MODELS_ROOT:-$default_root}"
      lock="''${LOCAL_MODELS_BORROW_LOCK:-/run/lock/local-models-borrow.lock}"
      reserve="''${LOCAL_MODELS_RESERVE_BYTES:-8589934592}"

      case "$reserve" in
        "" | *[!0-9]*)
          echo "local-models-borrow: REFUSING — reserve must be a non-negative byte count" >&2
          exit 2
          ;;
      esac
      if [ ! -r "$manifest" ]; then
        echo "local-models-borrow: REFUSING — cannot read manifest $manifest" >&2
        exit 6
      fi

      mkdir -p "$root"
      chmod 0755 "$root"
      mkdir -p "$(dirname "$lock")"
      exec 9>"$lock"
      if ! flock -n 9; then
        echo "local-models-borrow: REFUSING — another borrow transaction holds $lock" >&2
        exit 4
      fi

      rows() {
        jq -r '.[] | .id as $id | .files[] | [$id, .name, (.bytes|tostring), .oid] | @tsv' "$manifest"
      }

      # Preflight the WHOLE transaction before moving one byte. Reserving 8 GiB
      # keeps an operator borrow from filling the system disk. This is
      # intentionally conservative for a wrong-sized existing destination: the
      # old file remains usable until its verified replacement lands.
      needed=0
      entries=0
      fail=0
      while IFS=$'\t' read -r id name bytes oid; do
        dest="$root/$id/$name"
        src="$library/$id/$name"
        if [ -e "$dest" ] && [ "$(stat -c %s "$dest")" = "$bytes" ]; then
          continue
        fi
        entries=$((entries + 1))
        needed=$((needed + bytes))
        echo "local-models-borrow: WOULD borrow $id/$name ($bytes bytes)"
        if [ ! -e "$src" ]; then
          echo "local-models-borrow: MISSING in Library: $id/$name (run library-fetch on the NAS?)" >&2
          fail=1
        elif [ "$(stat -c %s "$src")" != "$bytes" ]; then
          echo "local-models-borrow: WRONG SIZE in Library: $id/$name" >&2
          fail=1
        fi
      done < <(rows)

      available_blocks="$(stat -f -c %a "$root")"
      block_size="$(stat -f -c %S "$root")"
      available=$((available_blocks * block_size))
      if [ "$available" -gt "$reserve" ]; then
        usable=$((available - reserve))
      else
        usable=0
      fi
      echo "local-models-borrow: PLAN $entries file(s), $needed bytes; $available bytes free, $reserve reserved"

      if [ "$fail" -ne 0 ]; then
        echo "local-models-borrow: REFUSING — the canonical NAS Library is incomplete" >&2
        exit 5
      fi
      if [ "$needed" -gt "$usable" ]; then
        echo "local-models-borrow: REFUSING — transaction needs $needed bytes but only $usable are available after reserve" >&2
        exit 3
      fi
      if [ "$mode" = dry-run ]; then
        exit 0
      fi

      # Apply exactly the preflighted plan. Present + right size is untouched;
      # missing or wrong size is copied from the canonical NAS Library,
      # sha256-verified during the copy, and atomically landed.
      current_part=""
      trap '[ -z "$current_part" ] || rm -f "$current_part"' EXIT
      trap 'exit 129' HUP
      trap 'exit 130' INT
      trap 'exit 143' TERM
      while IFS=$'\t' read -r id name bytes oid; do
        dest="$root/$id/$name"
        src="$library/$id/$name"
        if [ -e "$dest" ] && [ "$(stat -c %s "$dest")" = "$bytes" ]; then
          continue
        fi
        echo "local-models-borrow: borrowing $id/$name ($bytes bytes)"
        mkdir -p "$(dirname "$dest")"
        current_part="$dest.part"
        # Hash DURING the copy (tee splits the stream), not after: the old
        # cp-then-sha256sum shape re-read the whole artifact from local NVMe
        # as a second pass — ~40-60s of pure overhead on an 80GB borrow
        # (2026-08-29). Failure behavior is unchanged: pipefail + set -e
        # abort on a failed read/write exactly as a failed cp did.
        if ! actual="$(tee "$dest.part" < "$src" | sha256sum | cut -d' ' -f1)"; then
          echo "local-models-borrow: COPY FAILED for $id/$name" >&2
          rm -f "$dest.part"
          current_part=""
          fail=1
          continue
        fi
        if [ "$actual" != "$oid" ]; then
          echo "local-models-borrow: HASH MISMATCH for $id/$name (want $oid got $actual)" >&2
          rm -f "$dest.part"
          current_part=""
          fail=1
          continue
        fi
        chmod 0644 "$dest.part"
        mv -f "$dest.part" "$dest"
        current_part=""
      done < <(rows)

      # THIS TRANSACTION NEVER DELETES (dotfiles#296, ruled pruner disposition:
      # "wanted.json aligned", with a guard). It used to end here with two
      # unconditional prune branches — `rm -rf` of any artifact directory the
      # manifest no longer named, and `rm -f` of any stray file inside a kept
      # one — run by a boot-time oneshot with no operator present. Any change
      # that narrowed the wanted set therefore became tens of GiB of deleted
      # weights at the next boot, before anyone read the diff.
      #
      # What is left is an AUDIT: the same set, computed by the same rules,
      # printed and not touched. Deletion moved to the explicit manual verb
      # `local-models-prune`, which refuses unless the set it computes is
      # byte-for-byte the set a preceding `--dry-run` recorded.
      #
      # Still gated on a fully clean pass: a set computed from a failed borrow
      # would name files that are merely MISSING, not retired.
      if [ "$fail" = 0 ]; then
        local-models-prune-audit
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

  # ── the application-facing utility slot ───────────────────────────────────
  # Migrated here from modules/npu-llm.nix on 2026-08-29 (that module was
  # deleted outright 2026-08-31 with the appliance tier, #270; git history
  # keeps it). The stable id
  # `utility` is now backed by a GPU roster row served through llama-swap, so
  # the wrapper is a plain catalog-row-onto-host projection — this module's job
  # — rather than anything FastFlowLM ever owned. It is installed only where the
  # slot's deployment is canonical, assigned to this host, AND allowed into that
  # host's llama-swap roster: without the last condition the wrapper would name
  # a served id the local proxy does not know.
  utilityDeployment = catalog.deployments.${catalog.utility.deployment};
  utilityEnabled =
    utilityDeployment.status == "canonical"
    && lib.elem host utilityDeployment.hosts
    && lib.elem catalog.utility.deployment cfg.allow;
  utilityEndpoint = "http://localhost:${toString config.services.llama-swap.port}";
  utilityRunner = pkgs.writeShellApplication {
    name = "utility-model";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../pkgs/utility-model/utility_model.py} "$@" \
        --endpoint ${lib.escapeShellArg utilityEndpoint} \
        --concrete-model ${lib.escapeShellArg utilityDeployment.model} \
        --context-tokens ${toString catalog.utility.contextTokens}
    '';
  };

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
      assertion = lib.all (
        deployment: deployment.status != "retired" || deployment.archived != null
      ) deploymentList;
      message = "Every retired deployment must carry an `archived` receipt (NAS path + date) — archive the weights before retiring the row (docs/nas/model-archive.md).";
    }
    {
      assertion =
        lib.sort builtins.lessThan rendererBackends
        == lib.sort builtins.lessThan catalog.backendKinds.local;
      message = "Every local-model backend must have exactly one llama-swap command renderer.";
    }
    {
      # The appliance tier is retired (2026-08-31, #270): a backend value
      # outside `local` is legal only as history, on a row that is itself
      # retired. Anything live must be an engine the renderer table can serve.
      assertion = lib.all (
        deployment: lib.elem deployment.backend catalog.backendKinds.local || deployment.status == "retired"
      ) deploymentList;
      message = "Every non-retired deployment must use a managed local backend; retired backend values (npu) are archive records only.";
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
      message = "Managed local deployments require a model artifact; retired archive rows must not root artifacts.";
    }
    {
      assertion = builtins.length canonicalModelIds == builtins.length (lib.unique canonicalModelIds);
      message = "Canonical public model IDs must be unique per host.";
    }
    {
      assertion = lib.all (
        deployment: lib.all (arg: !(lib.hasInfix "-hf" arg)) deployment.runtime.args
      ) deploymentList;
      message = "Runtime model downloads (-hf) are forbidden; internet downloads terminate in the canonical NAS Library and device borrowing is an explicit operator transaction.";
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
    {
      # The utility slot must name a row llama-swap can actually serve
      # (2026-08-29 GPU migration). A non-local backend here — historically the
      # FLM appliance rows, today only a retired archive value — would mean the
      # wrapper forwards the stable `utility` id to an endpoint that has never
      # heard of it — the exact failure the FLM-era seam avoided by owning its
      # own child process.
      assertion =
        utilityDeployment.status != "canonical"
        || lib.elem utilityDeployment.backend catalog.backendKinds.local;
      message = "The catalog's utility deployment must be a managed local backend served through llama-swap.";
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
        Canonical deployment IDs to describe and expose through llama-swap on
        this host. This option publishes paths and metadata only; it never
        transfers model bytes. Use local-models-borrow explicitly when a
        working copy is wanted. Every entry must be a managed local backend;
        there is no other interactive serving tier (the NPU/FastFlowLM
        appliance tier was decommissioned 2026-08-29 and retired from the
        schema 2026-08-31, #270).
      '';
    };

    artifacts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Additional artifact IDs to describe without adding a llama-swap model
        row. This does not transfer bytes; local-models-borrow is the explicit
        transaction. This is for complete snapshots and modality-specific
        appliances such as Mage, ASR, and TTS.
      '';
    };

    libraryPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/nas/models/weights";
      description = ''
        Where this host reads the NAS model Library from (the coordinator's
        NFS mount by default; the worker mounts the read-only models export
        at /mnt/library). The explicit local-models-borrow transaction reads
        wanted artifacts here and copies them into /var/lib/local-models.
      '';
    };
  };

  config = {
    assertions = catalogAssertions;

    # The stable `utility` door, on the hosts that serve it and nowhere else.
    # Borrow and prune are both explicit operator transactions. Neither is a
    # service, timer, boot unit, or activation hook. local-models-prune is the
    # ONLY thing on this fleet that deletes a working copy (dotfiles#296):
    #   sudo local-models-borrow --dry-run  # inspect bytes and free-space gate
    #   sudo local-models-borrow --yes      # copy + verify from the NAS Library
    #   sudo local-models-prune --dry-run    # read the set, record the intent
    #   sudo local-models-prune --yes        # delete it, iff it has not changed
    environment.systemPackages =
      lib.optional utilityEnabled utilityRunner
      ++ lib.optionals (hostArtifactIds != [ ]) [
        borrowScript
        pkgs.local-models-prune
      ];

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
        # `peers` is upstream llama-swap's instance-to-instance federation
        # primitive: entries name REMOTE llama-swap/OpenAI providers this proxy
        # routes and proxies model requests to (verified against the shipped
        # v240 binary 2026-08-31 — internal/router.{Peer,NewPeer,peerMember},
        # "peer: routing model %s to peer %s" — the shipped README documents
        # none of it). This comment used to justify the empty set by the NPU
        # appliance tier ("runtime appliances are deliberately not represented
        # as proxy peers"); that tier is retired (#270) and the field is now
        # simply UNCLAIMED: it stays empty until the flashnext dual-node
        # gateway design (#270) deliberately federates the twins' proxies.
        # flake.nix pins peers == { } — relax that assert in the same change
        # that first populates this.
        peers = { };
      };

    # Weights live OUTSIDE the store (2026-08-21 decisive ruling). NixOS creates
    # only the empty root and publishes metadata; it NEVER starts, schedules,
    # orders against, or waits for a model-byte transfer. Existing working
    # copies stay world-readable because llama-swap's DynamicUser sandbox reads
    # these paths through ProtectSystem=strict. Missing rows fail only when an
    # operator tries to use them.
    systemd.tmpfiles.rules = lib.mkIf (hostArtifactIds != [ ]) [
      "d ${modelStore.runtimeRoot} 0755 root root -"
    ];
  };
}
