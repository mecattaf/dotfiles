{
  config,
  lib,
  pkgs,
  options,
  ...
}:
# k3s, common to the two cluster nodes (control = nas, harness = coordinator).
# DESIGN.md sections 6.2, 6.5 and 7. What the 2026-09-23 probe MEASURED
# working on k3s 1.36.2 (probe-build/vm/flake.nix) is the core: k3s_1_36 from
# the dotfiles nixpkgs pin, the three feature gates on every component, the
# certificates.k8s.io/v1beta1 runtime-config, overlay and br_netfilter, the
# inotify raises, a registry mirror in registries.yaml.
#
# What is deliberately NOT here (DESIGN.md D2, D4, 6.2):
#   - Cilium. flannel VXLAN plus kube-proxy (iptables), bound to the LAN leg
#     only. No BPF socket-LB next to tailscale0.
#   - a containerd template, runsc on the unit PATH, a RuntimeClass. Substrate
#     runs its own runsc inside the worker pods and uses no RuntimeClass
#     (MEASURED, read-substrate.md 2); containerd keeps k3s's generated config.
#   - --data-dir. The NixOS module links manifests and images into fixed
#     paths under /var/lib/rancher/k3s, so state moves by bind mount instead
#     (./control.nix).
let
  cfg = config.myAxFleet;
  cluster = cfg.enable && (cfg.role == "control" || cfg.role == "harness");

  # The feature gates Substrate's podcertcontroller needs, on all three
  # components (A5a and the probe MEASURED that kubelet accepts all three).
  gates = "ClusterTrustBundle=true,ClusterTrustBundleProjection=true,PodCertificateRequest=true";

  kubeletArgs =
    [ "feature-gates=${gates}" ]
    ++ lib.optional (cfg.kubelet.systemReserved != null) "system-reserved=${cfg.kubelet.systemReserved}"
    ++ lib.optional (cfg.kubelet.kubeReserved != null) "kube-reserved=${cfg.kubelet.kubeReserved}"
    ++ lib.optional (cfg.kubelet.evictionHard != null) "eviction-hard=${cfg.kubelet.evictionHard}";

  commonFlags = [
    "--resolv-conf=/etc/ax-fleet/resolv.conf"
    "--flannel-iface=${cfg.lan.interface}"
    # NodePorts (none are declared) could only ever bind the LAN /32, and
    # kube-proxy never sets route_localnet.
    "--kube-proxy-arg=nodeport-addresses=${cfg.lan.address}/32"
    "--kube-proxy-arg=iptables-localhost-nodeports=false"
  ]
  ++ map (a: "--kubelet-arg=${a}") kubeletArgs;

  # containerd pulls every pod image through the NAS registry; for anything
  # the mirror lacks it falls back to the upstream registry, so a missing
  # seed degrades rather than breaks on the fleet. The offline VM test is what
  # proves that nothing is missing.
  registriesYaml = ''
    mirrors:
      "${cfg.registry}":
        endpoint:
          - "http://${cfg.registry}"
      "docker.io":
        endpoint:
          - "http://${cfg.registry}"
      "registry.k8s.io":
        endpoint:
          - "http://${cfg.registry}"
  '';

  # Values recorded before k3s first runs on this host, restored by
  # ax-fleet-teardown. The kubelet sets the three kernel keys itself
  # (INFERRED from upstream kubelet behaviour; the VM test records them).
  snapshotKeys = [
    "net.ipv4.ip_forward"
    "net.ipv6.conf.all.forwarding"
    "net.ipv4.conf.all.proxy_arp"
    "net.ipv4.conf.default.proxy_arp"
    "kernel.panic"
    "kernel.panic_on_oops"
    "vm.overcommit_memory"
  ];
in
{
  config = lib.mkIf cluster (
    lib.mkMerge [
      {
        services.k3s = {
          enable = true;
          package = cfg.k3sPackage;
          tokenFile =
            if cfg.k3sTokenFile != null then cfg.k3sTokenFile else config.age.secrets.k3s-token.path;
          nodeIP = cfg.lan.address;
          # k3s core images (pause, coredns, local-path and its helper) come
          # from the pinned airgap tarball, never from the network.
          images = [ cfg.k3sPackage.airgap-images ];
          extraFlags = commonFlags;
        };

        environment.etc."rancher/k3s/registries.yaml".text = registriesYaml;
        # The kubelet's (and so CoreDNS's) upstream resolver: AdGuard on the
        # NAS, never the coordinator's systemd-resolved stub.
        environment.etc."ax-fleet/resolv.conf".text = "nameserver ${cfg.serverAddress}\n";

        boot.kernelModules = [
          "overlay"
          "br_netfilter"
        ];
        # Both hosts define 512 / 524288 today (modules/common.nix and the
        # nixpkgs default); a plain definition would be an evaluation
        # conflict. mkOverride 99 raises them to the probe recipe's values.
        boot.kernel.sysctl."fs.inotify.max_user_instances" = lib.mkOverride 99 8192;
        boot.kernel.sysctl."fs.inotify.max_user_watches" = lib.mkOverride 99 1048576;

        # The k3s package carries k3s-killall.sh; `KillMode=process` means
        # pods and shims outlive the unit, so teardown is a real step.
        environment.systemPackages = [ (pkgs.callPackage ../../pkgs/ax-fleet-teardown { k3s = cfg.k3sPackage; }) ];

        systemd.services.k3s = {
          # Re-create the manifest and image links AFTER the bind mounts are
          # up, whatever order a live switch ran tmpfiles and mounts in.
          serviceConfig.ExecStartPre = [
            "${config.systemd.package}/bin/systemd-tmpfiles --create --prefix=/var/lib/rancher/k3s"
          ];
        };

        # ── sysctl snapshot, taken BEFORE this generation's sysctls apply ──
        # An activation snippet, not a unit: at a live switch the activation
        # script runs before systemd-sysctl is restarted with the new values,
        # and at boot it runs before systemd starts. A unit ordered before
        # k3s would record ip_forward=1 that this very generation just set.
        # Written once; later generations never overwrite it.
        system.activationScripts.ax-fleet-sysctl-snapshot = {
          text = ''
            if [ ! -e /var/lib/ax-fleet/sysctl-before.conf ]; then
              mkdir -p /var/lib/ax-fleet
              {
                ${lib.concatMapStringsSep "\n" (
                  k: "v=$(cat /proc/sys/${lib.replaceStrings [ "." ] [ "/" ] k} 2>/dev/null) && echo \"${k} = $v\" || true"
                ) snapshotKeys}
              } > /var/lib/ax-fleet/sysctl-before.conf.tmp
              mv /var/lib/ax-fleet/sysctl-before.conf.tmp /var/lib/ax-fleet/sysctl-before.conf
            fi
          '';
        };
      }

      # The token: the existing agenix secret (commit 643a4196), recipients
      # editors ++ delivered ++ nasOnly. Never printed. Only declared where
      # agenix is imported and no test token is given.
      (lib.optionalAttrs (options ? age) {
        age.secrets = lib.mkIf (cfg.k3sTokenFile == null) {
          k3s-token = {
            file = ../../secrets/k3s-token.age;
            mode = "0400";
          };
        };
        assertions = [
          {
            assertion = cfg.k3sTokenFile != null || config.mySecrets.enable or false;
            message = "myAxFleet needs agenix delivery (mySecrets.enable) for secrets/k3s-token.age on ${config.networking.hostName}.";
          }
        ];
      })
    ]
  );
}
