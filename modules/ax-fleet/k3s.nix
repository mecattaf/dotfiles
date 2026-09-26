{
  config,
  lib,
  pkgs,
  options,
  ...
}:
# k3s, common to the cluster nodes (control = nas, harness = coordinator,
# inference = worker since 2026-09-25).
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
  # Every role is a cluster node (2026-09-25, Tom: "the amd strix halo worker
  # SHOULD be available in the cluster (not just halogen inference)"). The
  # role, not a second switch, says so: `enable` stays the one kill switch.
  clusterRole =
    options.myAxFleet.role.isDefined
    && builtins.elem cfg.role [
      "control"
      "harness"
      "inference"
    ];
  cluster = cfg.enable && clusterRole;

  teardown = pkgs.callPackage ../../pkgs/ax-fleet-teardown { k3s = cfg.k3sPackage; };

  # The feature gates Substrate's podcertcontroller needs, on all three
  # components (A5a and the probe MEASURED that kubelet accepts all three).
  gates = "ClusterTrustBundle=true,ClusterTrustBundleProjection=true,PodCertificateRequest=true";

  kubeletArgs = [
    "feature-gates=${gates}"
  ]
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
    # kube-proxy leaves the host's conntrack table alone (fix round 2). Its
    # defaults set nf_conntrack_tcp_timeout_established to 86400 and
    # close_wait to 3600 (MEASURED in the review VM; the live NAS and desk
    # read 432000 and 60), which on the house router would drop the SNAT
    # entry of any NATed flow idle for a day. 0 = do not touch.
    "--kube-proxy-arg=conntrack-tcp-timeout-established=0s"
    "--kube-proxy-arg=conntrack-tcp-timeout-close-wait=0s"
    "--kube-proxy-arg=conntrack-max-per-core=0"
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
    # kube-proxy's conntrack keys (fix round 2): the args above leave them,
    # the snapshot and the teardown make sure. Absent when nf_conntrack is
    # not loaded yet (boot), then simply not recorded.
    "net.netfilter.nf_conntrack_max"
    "net.netfilter.nf_conntrack_tcp_timeout_established"
    "net.netfilter.nf_conntrack_tcp_timeout_close_wait"
  ];

  # kubelet's values for the three kernel keys (upstream kubelet
  # setupKernelTunables; MEASURED 10 1 1 in the VM tests).
  kubeletKernel = {
    "kernel.panic" = "10";
    "kernel.panic_on_oops" = "1";
    "vm.overcommit_memory" = "1";
  };

  # ── the host's own declared value for a snapshot key (fix round 2) ──
  # At boot the activation script runs before systemd-sysctl, so /proc holds
  # kernel defaults, not the generation's values: the round-2 review MEASURED
  # a snapshot of ip_forward = 0 on a NAS that declares 1 (the house router),
  # which the teardown would then have applied. So at boot, a key some module
  # OUTSIDE modules/ax-fleet declares is recorded from that declaration; the
  # keys only this module declares (the harness's ip_forward and proxy_arp)
  # and the undeclared ones are read from /proc, where they still hold the
  # pre-ax value. null = no non-ax declaration, or conflicting ones.
  unwrap =
    v:
    if builtins.isAttrs v && (v._type or null) == "override" then
      unwrap v.content
    else if builtins.isAttrs v && (v._type or null) == "if" then
      (if v.condition then unwrap v.content else null)
    else
      v;
  sysctlString =
    v:
    if builtins.isBool v then
      (if v then "1" else "0")
    else if v == null then
      null
    else
      toString v;
  hostDeclared =
    k:
    let
      defs = lib.filter (
        d: !(lib.hasInfix "/modules/ax-fleet/" (toString d.file))
      ) options.boot.kernel.sysctl.definitionsWithLocations;
      vals = lib.unique (
        lib.filter (v: v != null) (
          map (d: sysctlString (unwrap (d.value.${k} or null))) (
            lib.filter (d: builtins.isAttrs d.value) defs
          )
        )
      );
    in
    if builtins.length vals == 1 then builtins.head vals else null;

  serverToken =
    if cfg.k3sTokenFile != null then cfg.k3sTokenFile else config.age.secrets.k3s-token.path;
  agentToken =
    if cfg.k3sAgentTokenFile != null then
      cfg.k3sAgentTokenFile
    else
      config.age.secrets.k3s-agent-token.path;
in
{
  config = lib.mkMerge [
    # The kill switch's second half stays on the host whatever the switch says
    # (fix round 2): the documented rollback is `enable = false`, switch, then
    # `sudo ax-fleet-teardown` ON the host, and the NAS holds no dotfiles
    # checkout (MEASURED). Inert until run by hand. `KillMode=process` means
    # pods and shims outlive k3s, so the teardown is a real step.
    (lib.mkIf clusterRole { environment.systemPackages = [ teardown ]; })

    (lib.mkIf cluster (
      lib.mkMerge [
        {
          services.k3s = {
            enable = true;
            package = cfg.k3sPackage;
            # Two credentials (fix round 2). The server token is the NAS's
            # alone; with no agent token k3s gives agents the server password
            # (MEASURED deps.go getNodePass), i.e. the k3s:server role on
            # /v1-k3s/token, /cacerts and /encrypt/config. The agents (the
            # coordinator, the worker) join with the agent token only.
            tokenFile = if cfg.role == "control" then serverToken else agentToken;
            agentTokenFile = if cfg.role == "control" then agentToken else null;
            nodeIP = cfg.lan.address;
            # k3s core images (pause, coredns, local-path and its helper) come
            # from the pinned airgap tarball, never from the network.
            images = [ cfg.k3sPackage.airgap-images ];
            extraFlags = commonFlags;
          };

          # services.k3s.role defaults to "server" (MEASURED on the worker,
          # 2026-09-25: nix eval ...services.k3s.role -> "server"). A cluster
          # role that forgot to say "agent" would start a cluster of its own on
          # k3s's default pod range 10.42.0.0/16, the house LAN, on a host
          # whose only way in is that LAN (the worker). Evaluation fails
          # instead.
          assertions = [
            {
              assertion = cfg.role == "control" || config.services.k3s.role == "agent";
              message = "modules/ax-fleet/k3s.nix: only the control role may run a k3s server; ${config.networking.hostName} has role \"${cfg.role}\" and services.k3s.role \"${config.services.k3s.role}\" (set role = \"agent\" in the role's module).";
            }
          ];

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

          systemd.services.k3s = {
            # Re-create the manifest and image links AFTER the bind mounts are
            # up, whatever order a live switch ran tmpfiles and mounts in.
            serviceConfig.ExecStartPre = [
              "${config.systemd.package}/bin/systemd-tmpfiles --create --prefix=/var/lib/rancher/k3s"
              # --node-ip and --flannel-iface name the LAN address, which
              # NetworkManager adds after network.target at boot (MEASURED on the
              # NAS). Bounded wait, then start anyway (k3s's Restart covers it).
              "${pkgs.writeShellScript "ax-fleet-k3s-wait-lan-addr" ''
                for _ in $(${pkgs.coreutils}/bin/seq 30); do
                  ${pkgs.iproute2}/bin/ip -4 addr show dev ${cfg.lan.interface} 2>/dev/null \
                    | ${pkgs.gnugrep}/bin/grep -qF 'inet ${cfg.lan.address}/' && exit 0
                  ${pkgs.coreutils}/bin/sleep 1
                done
                echo "ax-fleet: ${cfg.lan.address} not on ${cfg.lan.interface} after 30 s; starting anyway" >&2
                exit 0
              ''}"
            ];
          };

          # ── kubelet's kernel tunables, put back (myAxFleet.kubelet.keepHostKernelTunables) ──
          # kubelet sets these whenever its container manager starts, which is
          # NOT tied to a k3s restart: an agent whose server is unreachable is
          # `active` and runs no kubelet, and sets 10 1 1 whenever the server
          # answers, with NRestarts 0 (MEASURED by the round-2 review). So a
          # watcher, bound to k3s, not a one-shot after it (the round-1 unit gave
          # up after 900 s). Per key: only a value equal to kubelet's that differs
          # from the snapshot is put back, so a deliberate host change to any
          # other value is left alone.
          systemd.services.ax-fleet-kernel-tunables = lib.mkIf cfg.kubelet.keepHostKernelTunables {
            description = "ax-fleet: keep the host's kernel.panic, kernel.panic_on_oops, vm.overcommit_memory against kubelet";
            wantedBy = [ "k3s.service" ];
            after = [ "k3s.service" ];
            partOf = [ "k3s.service" ];
            path = [
              pkgs.procps
              pkgs.coreutils
              pkgs.gnugrep
            ];
            serviceConfig = {
              Type = "simple";
              Restart = "always";
              RestartSec = 5;
            };
            script = ''
              snap=/var/lib/ax-fleet/sysctl-before.conf
              [ -s "$snap" ] || { echo "no $snap; leaving kernel tunables as they are"; exec sleep infinity; }
              while :; do
                ${lib.concatStrings (
                  lib.mapAttrsToList (k: kv: ''
                    want=$(grep -E '^${k} = ' "$snap" | cut -d' ' -f3)
                    cur=$(sysctl -n ${k})
                    if [ -n "$want" ] && [ "$cur" = ${kv} ] && [ "$cur" != "$want" ]; then
                      sysctl -w "${k}=$want"
                    fi
                  '') kubeletKernel
                )}
                sleep 5
              done
            '';
          };

          # ── sysctl snapshot, taken BEFORE this generation's sysctls apply ──
          # An activation snippet, not a unit: at a live switch the activation
          # script runs before systemd-sysctl is restarted with the new values;
          # a unit ordered before k3s would record the ip_forward=1 this very
          # generation just set on the harness. switch-to-configuration exports
          # NIXOS_ACTION (switch, test) to the activation; the boot activation
          # (initrd-nixos-activation on the systemd-initrd hosts, stage 2
          # otherwise) does not, and there /proc holds kernel defaults, so
          # declared keys come from hostDeclared (fix round 2). /run/systemd/system
          # is no signal: it exists in the systemd initrd. Written once; later
          # generations never overwrite it.
          system.activationScripts.ax-fleet-sysctl-snapshot = {
            text = ''
              if [ ! -e /var/lib/ax-fleet/sysctl-before.conf ]; then
                mkdir -p /var/lib/ax-fleet
                {
                  ${lib.concatMapStringsSep "\n" (
                    k:
                    let
                      proc = "/proc/sys/${lib.replaceStrings [ "." ] [ "/" ] k}";
                      d = hostDeclared k;
                    in
                    if d == null then
                      "v=$(cat ${proc} 2>/dev/null) && echo \"${k} = $v\" || true"
                    else
                      ''
                        if [ -n "''${NIXOS_ACTION:-}" ]; then
                          v=$(cat ${proc} 2>/dev/null) && echo "${k} = $v" || true
                        else
                          echo "${k} = ${d}"
                        fi''
                  ) snapshotKeys}
                } > /var/lib/ax-fleet/sysctl-before.conf.tmp
                mv /var/lib/ax-fleet/sysctl-before.conf.tmp /var/lib/ax-fleet/sysctl-before.conf
              fi
            '';
          };
        }

        # The tokens: agenix secrets, never printed. k3s-token.age is the
        # server's (recipients editors ++ nasOnly); k3s-agent-token.age is the
        # agent credential (editors ++ coordinatorOnly ++ nasOnly ++
        # workerOnly, secrets.nix). Only declared where agenix is imported and
        # no test token is given.
        (lib.optionalAttrs (options ? age) {
          age.secrets = lib.mkMerge [
            (lib.mkIf (cfg.role == "control" && cfg.k3sTokenFile == null) {
              k3s-token = {
                file = ../../secrets/k3s-token.age;
                mode = "0400";
              };
            })
            (lib.mkIf (cfg.k3sAgentTokenFile == null) {
              k3s-agent-token = {
                file = ../../secrets/k3s-agent-token.age;
                mode = "0400";
              };
            })
          ];
          assertions = [
            {
              assertion =
                (cfg.k3sAgentTokenFile != null && (cfg.role != "control" || cfg.k3sTokenFile != null))
                || config.mySecrets.enable or false;
              message = "myAxFleet needs agenix delivery (mySecrets.enable) for secrets/k3s-token.age and secrets/k3s-agent-token.age on ${config.networking.hostName}.";
            }
          ];
        })
      ]
    ))
  ];
}
