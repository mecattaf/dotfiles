{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
# Track substrate (DESIGN.md sections 8, 9 and 14 S3): upstream Agent Substrate
# d277088b on the fleet's k3s, installed by its own `ate-setup --kind` exactly
# as the 2026-09-23 probe ran it (MEASURED rc 0, probe-build.md section 4), with
# --image-repo/--image-tag pointing at nix-built images in the NAS registry
# instead of ko.
#
# This file writes ONLY the myAxFleet extension points:
#   registrySeed   the six component images, the eight third-party images
#   bootstrap      20-registry-svc, 30-substrate, 40-gvisor-asset, 50-workerpool
# and an assertion that the version is one string everywhere. It renders
# nothing on a host where myAxFleet.enable is false, and the extension points
# are consumed only on the control role (the NAS), so the coordinator and the
# worker see an unchanged closure from this file.
let
  cfg = config.myAxFleet;
  on = cfg.enable && cfg.role == "control";

  inherit (pkgs.stdenv.hostPlatform) system;

  # ONE image set for every evaluator (fix round 2), as ax.nix already does:
  # built from the flake's own nixpkgs pin, never the host's `pkgs`. The NAS
  # evaluates on nixpkgs-stable, and the round-2 review MEASURED that the six
  # component images the real NAS would seed (ateapi, atecontroller, atelet,
  # atenet, ateom-gvisor, podcertcontroller) had other digests than the ones
  # the VM test ran. The Go toolchain comes from the nixpkgs-go input, the
  # same derivation pkgs/ax uses. ax-fleet-topology asserts the parity.
  fleetPkgs = inputs.nixpkgs.legacyPackages.${system};
  substrate = fleetPkgs.callPackage ../../pkgs/substrate {
    go_1_27 = inputs.nixpkgs-go.legacyPackages.${system}.go_1_27;
  };
  images = fleetPkgs.callPackage ../../pkgs/substrate/images.nix { inherit substrate; };

  kubectl = "${cfg.k3sPackage}/bin/kubectl";
  jq = "${pkgs.jq}/bin/jq";
  curl = "${pkgs.curl}/bin/curl";

  ns = "ate-system";

  # 10.42.0.1:5000 -> host and port, for the kind-registry EndpointSlice.
  registryParts = lib.splitString ":" cfg.registry;
  registryHost = lib.head registryParts;
  registryPort = lib.toInt (lib.last registryParts);

  # "ate.dev/sandboxClass=gvisor:NoSchedule" -> key, value, effect.
  taint =
    let
      m = builtins.match "([^=]+)=([^:]*):(.+)" cfg.harnessTaint;
    in
    {
      key = lib.elemAt m 0;
      value = lib.elemAt m 1;
      effect = lib.elemAt m 2;
    };

  # ── 20: the Service atelet's --localhost-registry-replacement names ──
  # The kind overlay runs atelet with --localhost-registry-replacement=
  # kind-registry:5000 (manifests/ate-install/kind/atelet/kustomization.yaml),
  # so every localhost:5000/... image atelet pulls itself (the pause image, the
  # Task images ax names) resolves to this Service. The probe needed exactly
  # this object pointing at its node's registry (MEASURED probe-build.md 4).
  registrySvc = pkgs.writeText "ax-fleet-20-registry-svc.yaml" (
    builtins.toJSON {
      apiVersion = "v1";
      kind = "List";
      items = [
        {
          apiVersion = "v1";
          kind = "Namespace";
          metadata.name = ns;
        }
        {
          apiVersion = "v1";
          kind = "Service";
          metadata = {
            name = "kind-registry";
            namespace = ns;
            labels."app.kubernetes.io/managed-by" = "ax-fleet";
          };
          spec.ports = [
            {
              name = "registry";
              port = 5000;
              targetPort = registryPort;
              protocol = "TCP";
            }
          ];
        }
        {
          apiVersion = "discovery.k8s.io/v1";
          kind = "EndpointSlice";
          metadata = {
            name = "kind-registry-nas";
            namespace = ns;
            labels = {
              "kubernetes.io/service-name" = "kind-registry";
              "endpointslice.kubernetes.io/managed-by" = "ax-fleet";
            };
          };
          addressType = "IPv4";
          ports = [
            {
              name = "registry";
              port = registryPort;
              protocol = "TCP";
            }
          ];
          endpoints = [
            {
              addresses = [ registryHost ];
              conditions.ready = true;
            }
          ];
        }
      ];
    }
  );

  # The install is re-run only when what it installs changes: the installer,
  # the patched manifests and every image are all in these three paths. The
  # component binaries themselves are not in the NAS closure, only the images.
  stamp = "${substrate.ate-setup}|${substrate.installTree}|${images}";

  # ── 50: the gVisor WorkerPool, on the harness only ──
  # nodeSelector and tolerations go through spec.template (MEASURED
  # pkg/api/v1alpha1/workerpool_types.go). Resources: limits.memory caps each
  # worker pod's cgroup, which holds the gVisor sandbox (DESIGN.md section 2,
  # replacing ax patch P3). Capacity is read from limits only and an unreported
  # dimension is unconstrained (cmd/ateapi/internal/scheduling HasRoom), so no
  # CPU limit. The requests are set explicitly: with limits alone Kubernetes
  # defaults requests to limits, and 2 x 16Gi would be reserved up front.
  workerPoolSpec = {
    replicas = cfg.workerPool.replicas;
    sandboxClass = "gvisor";
    workerImage = "@WORKER_IMAGE@";
    template = {
      labels."ax.mecattaf.dev/pool" = "ateom-gvisor";
      nodeSelector = {
        "ax.mecattaf.dev/role" = "harness";
        "ate.dev/substrate-version" = cfg.substrateVersion;
      };
      tolerations = [
        {
          inherit (taint) key value effect;
          operator = "Equal";
        }
        {
          key = "node.kubernetes.io/unreachable";
          operator = "Exists";
          effect = "NoExecute";
          tolerationSeconds = cfg.workerPool.unreachableTolerationSeconds;
        }
        {
          key = "node.kubernetes.io/not-ready";
          operator = "Exists";
          effect = "NoExecute";
          tolerationSeconds = cfg.workerPool.unreachableTolerationSeconds;
        }
      ];
      # ephemeral-storage (fix round 4): passed through unchanged by
      # atecontroller's applyWorkerPoolPodTemplate (REPORTED
      # workerpool_apply.go:522-528 at d277088b).
      resources = {
        limits = {
          memory = cfg.workerPool.memoryLimit;
          ephemeral-storage = cfg.workerPool.ephemeralStorageLimit;
        };
        requests = {
          cpu = "250m";
          memory = "1Gi";
          ephemeral-storage = cfg.workerPool.ephemeralStorageRequest;
        };
      };
    };
  };
  workerPoolTemplate = pkgs.writeText "ax-fleet-50-workerpool.json" (
    builtins.toJSON {
      apiVersion = "ate.dev/v1alpha1";
      kind = "WorkerPool";
      metadata = {
        name = "ateom-gvisor";
        namespace = ns;
        labels."app.kubernetes.io/managed-by" = "ax-fleet";
      };
      spec = workerPoolSpec;
    }
  );
in
{
  config = lib.mkIf on {
    assertions = [
      {
        assertion = cfg.substrateVersion == substrate.version;
        message = "myAxFleet.substrateVersion (${cfg.substrateVersion}) must equal pkgs/substrate's version (${substrate.version}): it is the node label, the image tag and ate-setup's VERSION at once.";
      }
      {
        assertion = builtins.match "([^=]+)=([^:]*):(.+)" cfg.harnessTaint != null;
        message = "myAxFleet.harnessTaint must read key=value:Effect.";
      }
      {
        assertion = builtins.length registryParts == 2;
        message = "myAxFleet.registry must read host:port.";
      }
    ];

    # Components under substrate/<name>:<version>; third-party images under
    # their upstream repositories, which the docker.io and registry.k8s.io
    # mirrors in registries.yaml resolve to. The pause image under `pause`,
    # which atelet reaches as kind-registry:5000/pause.
    myAxFleet.registrySeed = images.seed;

    myAxFleet.bootstrap = {
      "20-registry-svc" = ''
        # 20-registry-svc: Namespace ${ns} and the kind-registry Service ->
        # ${cfg.registry}, before ate-setup starts atelet.
        ${kubectl} apply -f ${registrySvc}
      '';

      "25-rustfs-secret" = ''
        # 25-rustfs-secret: the RustFS credential RustFS, ate-api and atelet
        # read through secretKeyRef (pkgs/substrate patch 0003), in place of
        # the kind overlay's literal default published upstream. Generated
        # once on this host into /var/lib/ax-fleet/rustfs.env (0600 root),
        # applied before ate-setup starts those pods. Never printed.
        f=/var/lib/ax-fleet/rustfs.env
        if [ ! -s "$f" ]; then
          (
            umask 077
            tmp=$(mktemp /var/lib/ax-fleet/.rustfs.env.XXXXXX)
            rnd() { head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'; }
            printf 'access-key=ax%s\nsecret-key=%s\n' "$(rnd 10)" "$(rnd 32)" > "$tmp"
            mv "$tmp" "$f"
          )
          echo "generated $f"
        fi
        ${kubectl} -n ${ns} create secret generic ax-fleet-rustfs --from-env-file="$f" \
          --dry-run=client -o yaml | ${kubectl} apply -f - >/dev/null
        echo "secret ${ns}/ax-fleet-rustfs applied"
      '';

      "30-substrate" = ''
        # 30-substrate: upstream's own installer, once per (installer, images)
        # pair. The stamp lives in the cluster, so a wiped cluster re-installs.
        want='${stamp}'
        have=$(${kubectl} -n kube-system get configmap ax-fleet-substrate \
          -o jsonpath='{.data.stamp}' 2>/dev/null || true)
        if [ "$have" = "$want" ]; then
          echo "substrate ${substrate.version} already installed from this closure"
        else
          # ate-setup walks up from its working directory to go.mod and reads
          # manifests/ from there; it writes nothing under that root.
          cd ${substrate.installTree}
          env -u GCE_REGION -u CLUSTER_LOCATION -u NETWORK -u SUBNETWORK \
              -u MEMORYSTORE_INSTANCE -u PROJECT_ID \
            VERSION=${cfg.substrateVersion} BUCKET_NAME=ate-snapshots \
            HOME="''${HOME:-/var/lib/ax-fleet}" \
            ${substrate.ate-setup}/bin/ate-setup --kind --no-dev-env \
              --kubeconfig "$KUBECONFIG" --context default \
              --rollout-timeout 10m \
              --image-repo ${cfg.registry}/substrate \
              --image-tag ${cfg.substrateVersion} \
              deploy ate-system
          cd /
          ${kubectl} -n kube-system create configmap ax-fleet-substrate \
            --from-literal=stamp="$want" \
            --from-literal=version=${cfg.substrateVersion} \
            --dry-run=client -o yaml | ${kubectl} apply -f -
          echo "substrate ${substrate.version} installed"
        fi
      '';

      "40-gvisor-asset" = ''
        # 40-gvisor-asset: put the pinned runsc tarball where atelet's S3
        # fallback looks for gs://${images.gvisor.bucket}/${images.gvisor.key}
        # (same bucket and key; the scheme is ignored). The credential is
        # read from the Secret 25-rustfs-secret applied and kept off argv.
        ${kubectl} -n ${ns} rollout status deploy/rustfs --timeout=10m
        ip=$(${kubectl} -n ${ns} get svc rustfs -o jsonpath='{.spec.clusterIP}')
        base="http://$ip:9000"
        creds=$(mktemp)
        trap 'rm -f "$creds"' EXIT
        chmod 600 "$creds"
        ${kubectl} -n ${ns} get secret ax-fleet-rustfs -o json | ${jq} -r '
          .data
          | "user = \"\(.["access-key"] | @base64d):\(.["secret-key"] | @base64d)\""' > "$creds"
        s3() { ${curl} -sS --aws-sigv4 "aws:amz:us-east-1:s3" -K "$creds" "$@"; }
        code=$(s3 -o /dev/null -w '%{http_code}' -I "$base/${images.gvisor.bucket}")
        if [ "$code" != 200 ]; then
          s3 -f -X PUT "$base/${images.gvisor.bucket}" -o /dev/null
          echo "created bucket ${images.gvisor.bucket}"
        fi
        obj="$base/${images.gvisor.bucket}/${images.gvisor.key}"
        code=$(s3 -o /dev/null -w '%{http_code}' -I "$obj")
        if [ "$code" != 200 ]; then
          s3 -f -T ${images.gvisor} \
            -H "x-amz-content-sha256: ${images.gvisor.sha256}" \
            -H "Content-Type: application/zstd" "$obj" -o /dev/null
          echo "uploaded ${images.gvisor.key}"
        fi
        got=$(s3 -f "$obj" | sha256sum | cut -d' ' -f1)
        if [ "$got" != "${images.gvisor.sha256}" ]; then
          echo "gvisor asset sha256 mismatch in RustFS: $got" >&2
          exit 1
        fi
        echo "gvisor asset verified (sha256 ${images.gvisor.sha256})"
      '';

      "50-workerpool" = ''
        # 50-workerpool: WorkerPool ateom-gvisor on the harness node(s), by
        # digest (the CRD's CEL rule wants an @). The digest is read from the
        # store at run time, so evaluation needs no IFD.
        digest=$(tr -d '[:space:]' < ${images.components.ateom-gvisor}/digest)
        ref="${cfg.registry}/substrate/ateom-gvisor:${cfg.substrateVersion}@$digest"
        sed "s|@WORKER_IMAGE@|$ref|" ${workerPoolTemplate} | ${kubectl} apply -f -
        echo "workerpool ateom-gvisor: ${toString cfg.workerPool.replicas} replica(s), $ref"
      '';
    };
  };
}
