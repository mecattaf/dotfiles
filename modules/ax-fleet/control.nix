{
  config,
  lib,
  pkgs,
  ...
}:
# The control node: the NAS. "Hypervisor on NAS" (Tom, 2026-09-23) read as
# everything that schedules or remembers: the k3s server WITH its kubelet and
# NO taint (so CoreDNS, local-path, Substrate's and ax's control pods and every
# PersistentVolume land here by elimination, because the coordinator is
# tainted), the registry, and the two runners that seed it and bootstrap the
# cluster. DESIGN.md sections 6.2, 6.3, 7, 8, 9.
#
# Nothing churns on the 57 GB eMMC root: k3s's datastore, containerd and
# kubelet state are bind-mounted from the fast tier (stateRoot), and every
# PersistentVolume and the registry live on the data pool. The NAS's shared
# PostgreSQL (Paperless, Immich) is not touched.
let
  cfg = config.myAxFleet;
  on = cfg.enable && cfg.role == "control";

  gates = "ClusterTrustBundle=true,ClusterTrustBundleProjection=true,PodCertificateRequest=true";

  registryPort = lib.toInt (lib.last (lib.splitString ":" cfg.registry));
  registryHost = lib.head (lib.splitString ":" cfg.registry);

  serverFlags = [
    "--cluster-cidr=${cfg.podCidr}"
    "--service-cidr=${cfg.serviceCidr}"
    "--cluster-dns=${cfg.clusterDns}"
    "--flannel-backend=vxlan"
    "--advertise-address=${cfg.lan.address}"
    "--tls-san=${cfg.lan.address}"
    "--tls-san=nas"
    "--disable-helm-controller"
    # k3s's network-policy controller off: Substrate ships no NetworkPolicy
    # (MEASURED at d277088b). Confining worker pods by policy is a follow-up.
    "--disable-network-policy"
    # local-storage stays ON: the kind install's PostgreSQL and RustFS claim
    # volumes (MEASURED kind/rustfs.yaml:16, postgres/postgres.yaml:242).
    "--default-local-storage-path=${cfg.localPathRoot}"
    "--secrets-encryption"
    "--service-node-port-range=${cfg.nodePortRange}"
    "--kube-apiserver-arg=feature-gates=${gates}"
    # The gates alone serve nothing; this is what serves the group (A5a,
    # MEASURED; upstream's hack/create-kind-cluster.sh runtimeConfig).
    "--kube-apiserver-arg=runtime-config=certificates.k8s.io/v1beta1=true"
    "--kube-controller-manager-arg=feature-gates=${gates}"
  ];

  # k3s hot state on the fast tier, by bind mount (not --data-dir: the NixOS
  # module links manifests and images into fixed /var/lib/rancher/k3s paths).
  binds = {
    "/var/lib/rancher" = "${cfg.stateRoot}/k3s/rancher";
    "/var/lib/kubelet" = "${cfg.stateRoot}/k3s/kubelet";
    "/var/log/pods" = "${cfg.stateRoot}/k3s/pod-logs";
  };

  kubectl = "${cfg.k3sPackage}/bin/kubectl";

  # ── the bootstrap steps this track owns ──
  bootstrapApi = ''
    # 10-api: wait for the apiserver and the admin kubeconfig.
    for _ in $(seq 1 300); do
      if [ -s /etc/rancher/k3s/k3s.yaml ] && ${kubectl} get --raw /readyz >/dev/null 2>&1; then
        echo "apiserver ready"
        exit 0
      fi
      sleep 2
    done
    echo "apiserver not ready" >&2
    exit 1
  '';

  bootstrapKubeconfig = ''
    # 60-kubeconfig: the admin kubeconfig for ax-fleet-kubeconfig on the
    # coordinator (read over the existing ssh trust). 0640 root:wheel, never
    # printed.
    install -d -m 0755 /etc/ax-fleet
    tmp=$(mktemp /etc/ax-fleet/.admin.kubeconfig.XXXXXX)
    sed 's#https://127.0.0.1:6443#https://${cfg.serverAddress}:6443#' /etc/rancher/k3s/k3s.yaml > "$tmp"
    chown root:wheel "$tmp"
    chmod 0640 "$tmp"
    mv "$tmp" /etc/ax-fleet/admin.kubeconfig
  '';

  stepNames = lib.sort (a: b: a < b) (lib.attrNames cfg.bootstrap);
  stepScript = name: pkgs.writeShellScript "ax-fleet-step-${name}" ''
    set -euo pipefail
    ${cfg.bootstrap.${name}}
  '';

  seedScript = ''
    set -euo pipefail
    for _ in $(seq 1 120); do
      curl -fsS -o /dev/null http://${cfg.registry}/v2/ && break
      sleep 1
    done
    curl -fsS -o /dev/null http://${cfg.registry}/v2/
    ${lib.concatStrings (
      lib.mapAttrsToList (name: s: ''
        echo "seed ${name}: ${s.repo}:${s.tag}"
        digest=$(tr -d '[:space:]' < ${s.oci}/digest)
        skopeo --insecure-policy copy --all --preserve-digests --dest-tls-verify=false \
          oci:${s.oci} docker://${cfg.registry}/${s.repo}:${s.tag}
        skopeo --insecure-policy inspect --raw --tls-verify=false \
          docker://${cfg.registry}/${s.repo}@"$digest" >/dev/null
        echo "seeded ${s.repo}@$digest"
      '') cfg.registrySeed
    )}
    echo "registry seed complete: ${toString (lib.length (lib.attrNames cfg.registrySeed))} image(s)"
  '';
in
{
  config = lib.mkIf on {
    myAxFleet.kubelet = {
      # Protects DNS, DHCP, headscale, Paperless and Immich on 8 cores / 22 GiB.
      systemReserved = lib.mkDefault "cpu=2,memory=8Gi";
    };

    myAxFleet.bootstrap = {
      "10-api" = bootstrapApi;
      "60-kubeconfig" = bootstrapKubeconfig;
    };

    services.k3s = {
      role = "server";
      disable = [
        "traefik"
        "servicelb"
        "metrics-server"
      ];
      # No nodeTaint: the NAS is untainted (DESIGN D5). The `none` version
      # value keeps Substrate's version-keyed atelet DaemonSet off the NAS
      # (ate-setup only labels nodes that lack the key).
      nodeLabel = [
        "ax.mecattaf.dev/role=control"
        "ate.dev/substrate-version=none"
      ];
      extraFlags = serverFlags;
      manifests = lib.mapAttrs (name: m: {
        inherit (m) source;
        target = "${name}.yaml";
      }) cfg.manifests;
    };

    # ── bind mounts: k3s state on the fast tier ──
    # systemd mount units, not fileSystems: they stay out of local-fs.target
    # (a failed bind cannot drop the router into emergency mode at boot; only
    # k3s, which RequiresMountsFor them, would fail), and the VM test runs the
    # exact same units (qemu-vm replaces `fileSystems` wholesale).
    systemd.mounts = lib.mapAttrsToList (where: what: {
      inherit what where;
      type = "none";
      options = "bind";
      requires = [ "ax-fleet-dirs.service" ];
      after = [ "ax-fleet-dirs.service" ];
      wantedBy = [ "k3s.service" ];
      before = [ "k3s.service" ];
    }) binds;

    systemd.services.ax-fleet-dirs = {
      description = "ax-fleet: create the k3s state and data-pool directories";
      unitConfig = {
        DefaultDependencies = false;
        RequiresMountsFor = [
          cfg.stateRoot
          cfg.localPathRoot
          cfg.registryRoot
        ];
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${lib.concatMapStringsSep "\n" (d: "${pkgs.coreutils}/bin/install -d -m 0711 ${d}") (
          lib.attrValues binds
        )}
        ${pkgs.coreutils}/bin/install -d -m 0711 ${cfg.localPathRoot}
        ${pkgs.coreutils}/bin/install -d -m 0750 -o docker-registry -g docker-registry ${cfg.registryRoot}
      '';
    };

    systemd.services.k3s = {
      wants = [ "ax-fleet-dirs.service" ];
      after = [ "ax-fleet-dirs.service" ];
      unitConfig.RequiresMountsFor = (lib.attrNames binds) ++ [ cfg.localPathRoot ];
    };

    # ── the registry (moved from #446), on the data pool ──
    services.dockerRegistry = {
      enable = true;
      listenAddress = registryHost;
      port = registryPort;
      storagePath = cfg.registryRoot;
      enableDelete = true;
      enableGarbageCollect = true;
      garbageCollectDates = "weekly";
      # openFirewall NOT used: the source-scoped rule below is the access control.
    };
    systemd.services.docker-registry = {
      wants = [ "ax-fleet-dirs.service" ];
      after = [ "ax-fleet-dirs.service" ];
      unitConfig.RequiresMountsFor = [ cfg.registryRoot ];
    };

    # ── firewall: only what the coordinator and the pods need ──
    # #447 opened 6443 to the whole LAN and #446 opened 5432/9000/5000 to the
    # whole LAN. Now: 6443, 5000 and VXLAN only from the coordinator; DNS and
    # the apiserver from pods on cni0. 5432, 6379 and 9000 are never opened on
    # the host. Nothing on tailscale0.
    networking.firewall.extraInputRules = ''
      iifname "${cfg.lan.interface}" ip saddr { ${lib.concatStringsSep ", " cfg.harnessAddresses} } tcp dport { 6443, ${toString registryPort} } accept comment "ax-fleet: kube API and registry, coordinator only"
      iifname "${cfg.lan.interface}" ip saddr { ${lib.concatStringsSep ", " cfg.harnessAddresses} } udp dport 8472 accept comment "ax-fleet: flannel VXLAN, coordinator only"
      iifname "cni0" ip saddr ${cfg.podCidr} tcp dport { 53, 6443 } accept comment "ax-fleet: pods to AdGuard and the apiserver"
      iifname "cni0" ip saddr ${cfg.podCidr} udp dport 53 accept comment "ax-fleet: pods to AdGuard"
    '';

    # ── the registry seed: from store paths in the NAS closure ──
    systemd.services.ax-fleet-registry-seed = {
      description = "ax-fleet: seed the NAS registry from the store, digests preserved";
      wantedBy = [ "multi-user.target" ];
      requires = [ "docker-registry.service" ];
      after = [ "docker-registry.service" ];
      path = [
        pkgs.skopeo
        pkgs.curl
        pkgs.coreutils
      ];
      environment.HOME = "/var/lib/ax-fleet";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "ax-fleet";
      };
      script = seedScript;
    };

    # ── the bootstrap: myAxFleet.bootstrap, in name order ──
    systemd.services.ax-fleet-bootstrap = {
      description = "ax-fleet: bootstrap the cluster (idempotent steps, in name order)";
      wantedBy = [ "multi-user.target" ];
      wants = [
        "k3s.service"
        "docker-registry.service"
        "ax-fleet-registry-seed.service"
      ];
      after = [
        "k3s.service"
        "docker-registry.service"
        "ax-fleet-registry-seed.service"
      ];
      path = [
        cfg.k3sPackage
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused
        pkgs.gawk
        pkgs.findutils
        pkgs.jq
        pkgs.curl
        pkgs.skopeo
        pkgs.util-linux
        pkgs.bash
      ];
      environment = {
        KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
        HOME = "/var/lib/ax-fleet";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 30;
        TimeoutStartSec = "45min";
        StateDirectory = "ax-fleet";
      };
      script = ''
        set -euo pipefail
        ${lib.concatMapStringsSep "\n" (n: ''
          echo "== ax-fleet-bootstrap step ${n}"
          ${stepScript n}
        '') stepNames}
        echo "== ax-fleet-bootstrap complete: ${toString (lib.length stepNames)} step(s)"
      '';
    };
  };
}
