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
  # The guard table is the control ROLE's, whatever `enable` says (fix round
  # 3): after the kill switch, pods (the egress gateway among them) outlive
  # k3s until ax-fleet-teardown. Inert without cni0 and flannel.1.
  roleOn = cfg.role == "control";
  on = cfg.enable && roleOn;

  halogenHost = lib.head (lib.splitString ":" cfg.halogenEndpoint);
  halogenPort = lib.last (lib.splitString ":" cfg.halogenEndpoint);

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

  waitLanAddr = pkgs.writeShellScript "ax-fleet-wait-lan-addr" ''
    for _ in $(${pkgs.coreutils}/bin/seq 30); do
      ${pkgs.iproute2}/bin/ip -4 addr show dev ${cfg.lan.interface} 2>/dev/null \
        | ${pkgs.gnugrep}/bin/grep -qF 'inet ${cfg.lan.address}/' && exit 0
      ${pkgs.coreutils}/bin/sleep 1
    done
    echo "ax-fleet: ${cfg.lan.address} not on ${cfg.lan.interface} after 30 s; starting anyway" >&2
    exit 0
  '';

  # ── the cluster-range guard (fix round 1, 2026-09-23) ──
  # The NAS is the house default gateway and forwards with policy accept, and
  # kube-proxy's KUBE-SERVICES DNAT sits in PREROUTING for every interface. So
  # without this, any LAN device that routes the pod or Service range via
  # 10.42.0.1 reaches ClusterIPs and pods (MEASURED by the security review:
  # ax-server 200, Redis INFO, RustFS 403; and, through VXLAN, pods on the
  # coordinator). At priority raw, before any DNAT: destinations in the
  # cluster ranges are accepted only from the pod-side interfaces. VXLAN
  # outer packets target ${cfg.lan.address}, so flannel is unaffected, and
  # traffic the NAS itself originates never passes prerouting.
  rangeGuard = ''
    chain prerouting {
      type filter hook prerouting priority raw; policy accept;
      iifname { "cni0", "flannel.1", "lo" } return
      iifname "veth*" return
      # The match carries the drop (never a bare drop): IPv6 and every other
      # destination fall through to policy accept.
      ip daddr { ${cfg.podCidr}, ${cfg.serviceCidr} } counter drop comment "ax-fleet: cluster ranges only from pods and flannel"
    }

    # ── pod egress from the router (fix round 3) ──
    # MEASURED by the round-3 review: postgres-0 reached worker:2222 and the
    # egress gateway (atenet-egress, a pod on this node, which carries every
    # sandbox's allowlisted traffic) reached every TCP port on the worker,
    # sshd included: ax drops the Gateway's port and Substrate never compares
    # one (REPORTED ax client.go:457-490, egresspolicy.go:133-158). Here the
    # port IS enforced: from pods, the only private address is Halogen on its
    # port; the tailnet and the containers are never reachable; the internet
    # is. Pod-to-NAS-host traffic (DNS, the apiserver, the registry) is INPUT
    # and unaffected. Same shape as the coordinator's guard (harness.nix).
    chain forward {
      type filter hook forward priority filter; policy accept;
      iifname != { "cni0", "flannel.1" } return
      ct state established,related return
      oifname { "cni0", "flannel.1" } return
      ip daddr ${halogenHost} tcp dport ${halogenPort} return
      ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 169.254.0.0/16 } counter drop comment "ax-fleet: pods reach no private address but Halogen"
      ip6 daddr { fc00::/7, fe80::/10 } counter drop comment "ax-fleet: pods reach no private address but Halogen"
      oifname { ${lib.concatMapStringsSep ", " (i: ''"${i}"'') cfg.guardInterfaces} } counter drop comment "ax-fleet: pods never reach the tailnet"
      oifname "ve-*" counter drop comment "ax-fleet: pods never reach the NAS's containers"
    }

    # ── the cluster from the NAS's own processes: root only (fix round 4) ──
    # The coordinator's owner match (harness.nix apiRules) had no counterpart
    # here: prerouting never sees locally generated packets, so paperless,
    # immich, atticd, headscale or nginx (MEASURED uid-map) could open the
    # unauthenticated ax-server API and the password-less ax-redis, and, while
    # a seed runs, push to the loopback writer. Only NEW connections are
    # policed: replies from AdGuard or the registry to pods are established.
    chain output {
      type filter hook output priority filter; policy accept;
      ct state != new return
      meta skuid 0 return
      ${lib.optionalString (cfg.clusterClientUids != [ ]) "meta skuid { ${lib.concatMapStringsSep ", " toString cfg.clusterClientUids} } return"}
      ip daddr { ${cfg.podCidr}, ${cfg.serviceCidr} } counter reject comment "ax-fleet: the cluster ranges from this host, root only"
      ip daddr 127.0.0.1 tcp dport ${lib.last (lib.splitString ":" seedAddr)} counter reject with tcp reset comment "ax-fleet: the seed's writable registry, root only"
    }
  '';

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
  stepScript =
    name:
    pkgs.writeShellScript "ax-fleet-step-${name}" ''
      set -euo pipefail
      ${cfg.bootstrap.${name}}
    '';

  # ── the registry: read-only to the network, writable only to the seed ──
  # (fix round 2) The round-2 review MEASURED an unprivileged user on the
  # coordinator pushing blobs (202), mounting across repos (201) and
  # overwriting substrate/atelet:d277088b's tag (201): the source-address rule
  # admits every uid and every pod on the coordinator (masqueraded to its LAN
  # address). ate-setup resolves --image-tag to a digest at install time, so a
  # rewritten tag is what would get pinned. Now the served instance on
  # ${cfg.registry} runs with storage.maintenance.readonly, and delete is off;
  # the seed pushes through a second, loopback-only instance on the same root
  # directory that lives only for the seed run, as the registry user.
  seedAddr = "127.0.0.1:5001";
  registryBase = {
    version = "0.1";
    log.fields.service = "registry";
    storage = {
      cache.blobdescriptor = "inmemory";
      delete.enabled = false;
      filesystem.rootdirectory = cfg.registryRoot;
    };
    http.headers.X-Content-Type-Options = [ "nosniff" ];
  };
  seedRegistryConfig = pkgs.writeText "ax-fleet-seed-registry.json" (
    builtins.toJSON (lib.recursiveUpdate registryBase { http.addr = seedAddr; })
  );

  seedScript = ''
    set -euo pipefail
    # The writable instance, loopback only, gone when this script exits.
    setpriv --reuid=docker-registry --regid=docker-registry --init-groups \
      ${lib.getExe config.services.dockerRegistry.package} serve ${seedRegistryConfig} &
    writer=$!
    trap 'kill $writer 2>/dev/null || true; wait $writer 2>/dev/null || true' EXIT
    for _ in $(seq 1 120); do
      curl -fsS -o /dev/null http://${cfg.registry}/v2/ && curl -fsS -o /dev/null http://${seedAddr}/v2/ && break
      sleep 1
    done
    curl -fsS -o /dev/null http://${cfg.registry}/v2/
    curl -fsS -o /dev/null http://${seedAddr}/v2/
    ${lib.concatStrings (
      lib.mapAttrsToList (name: s: ''
        echo "seed ${name}: ${s.repo}:${s.tag}"
        digest=$(tr -d '[:space:]' < ${s.oci}/digest)
        skopeo --insecure-policy copy --all --preserve-digests --dest-tls-verify=false \
          oci:${s.oci} docker://${seedAddr}/${s.repo}:${s.tag}
        # Read back through the served, read-only instance: what pods pull.
        skopeo --insecure-policy inspect --raw --tls-verify=false \
          docker://${cfg.registry}/${s.repo}@"$digest" >/dev/null
        echo "seeded ${s.repo}@$digest"
      '') cfg.registrySeed
    )}
    echo "registry seed complete: ${toString (lib.length (lib.attrNames cfg.registrySeed))} image(s)"
  '';
in
{
  config = lib.mkMerge [
  (lib.mkIf roleOn {
    assertions = [
      {
        assertion = config.networking.nftables.enable;
        message = "modules/ax-fleet/control.nix: the control role's cluster-range guard is an nftables table; the NAS runs nftables.";
      }
    ];
    networking.nftables.tables.ax-fleet-guard = {
      family = "inet";
      content = rangeGuard;
    };
    # The teardown leaves a guard the generation declares (pkgs/ax-fleet-teardown).
    environment.etc."ax-fleet/guard-declared".text = "control\n";
  })
  (lib.mkIf on {
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
      # Lazy: at the kill-switch switch, pods and shims outlive k3s
      # (KillMode=process) and can keep /var/lib/kubelet busy, which made the
      # rollback switch exit 4 (MEASURED, fix round 1 VM run 4). Detaching
      # lazily leaves the data on /mnt/fast untouched; ax-fleet-teardown then
      # stops what still holds it.
      mountConfig.LazyUnmount = true;
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
      # Read-only to the network (see seedAddr); garbage collection is
      # offline and needs no delete API.
      enableDelete = false;
      extraConfig.storage.maintenance.readonly.enabled = true;
      enableGarbageCollect = true;
      garbageCollectDates = "weekly";
      # openFirewall NOT used: the source-scoped rule below is the access control.
    };
    systemd.services.docker-registry = {
      wants = [ "ax-fleet-dirs.service" ];
      after = [ "ax-fleet-dirs.service" ];
      unitConfig.RequiresMountsFor = [ cfg.registryRoot ];
      # The explicit ${registryHost} bind races NetworkManager at boot: the
      # static address reaches ${cfg.lan.interface} seconds after
      # network(-online).target (MEASURED on the NAS, 2026-09-23; the same race
      # hosts/nas/headscale.nix and modules/adguardhome.nix already guard).
      # Wait up to 30 s for the address, then start anyway and let Restart
      # cover a genuinely late interface.
      serviceConfig = {
        ExecStartPre = waitLanAddr;
        Restart = "on-failure";
        RestartSec = 5;
      };
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
      # wants, not requires: a registry that fails its first start (late LAN
      # address) must not fail the seed on dependency, which Restart= would
      # never retry. The script itself waits for /v2/, and Restart retries.
      wants = [ "docker-registry.service" ];
      after = [ "docker-registry.service" ];
      path = [
        pkgs.skopeo
        pkgs.curl
        pkgs.coreutils
        pkgs.util-linux
      ];
      environment.HOME = "/var/lib/ax-fleet";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "ax-fleet";
        Restart = "on-failure";
        RestartSec = 15;
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
  })
  ];
}
