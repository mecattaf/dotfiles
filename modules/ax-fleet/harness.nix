{
  config,
  lib,
  pkgs,
  ...
}:
# The harness node: the coordinator. "Agent harnesses on coordinator" (Tom,
# 2026-09-23). A k3s agent tainted with upstream Substrate's own key, so only
# atelet and the WorkerPool's gVisor worker pods land here; nothing that
# schedules or remembers does (the wifi leg is the least available link).
# DESIGN.md sections 6.2, 6.4, 6.5, 6.6, 9.
#
# What must NOT change for Tom at switch, and how this file keeps it:
#   - NetworkManager is not restarted. `networking.networkmanager.unmanaged`
#     rewrites NetworkManager.conf, NetworkManager's restart trigger with
#     stopIfChanged = true (MEASURED nix eval), which would drop the desk's
#     wifi. A conf.d drop-in plus `nmcli general reload conf` instead.
#   - the tailnet: flannel and kube-proxy bind the LAN leg only, nothing is
#     published, and the guard chain below keeps pods, wifi and the tailnet
#     apart even though k3s turns ip_forward on (judge 1's second risk). The
#     guard chain polices FORWARD only; pods reaching the coordinator HOST
#     (sshd, which accepts passwords) go through INPUT, so pod interfaces get
#     their own refusal at the head of nixos-fw (fix round 2, see podInput). The
#     chain covers the direct path; the path routed through the NAS into
#     VXLAN is closed twice, by the NAS's prerouting range guard
#     (control.nix) and by the flannel.1 source rule here. Plain VXLAN on the
#     wifi leg is accepted by source address only (spoofable over wifi); see
#     DESIGN.md Unknowns.
#   - the kernel's panic behaviour: kubelet's kernel.panic / panic_on_oops /
#     overcommit values are put back after it starts
#     (myAxFleet.kubelet.keepHostKernelTunables, k3s.nix).
#   - herdr and every user unit: only system units are added.
#   - no containerd template, no runsc on PATH, no RuntimeClass (Substrate
#     runs its own runsc in the worker pods).
let
  cfg = config.myAxFleet;
  # The firewall half (guard chain, pod-input refusal, API owner match) is
  # rendered for the harness ROLE, whatever `enable` says (fix round 3): the
  # kill switch stops k3s with KillMode=process, so gVisor pods, cni0 and
  # flannel.1 outlive the switch until ax-fleet-teardown runs. The rules are
  # inert once those interfaces are gone.
  roleOn = cfg.role == "harness";
  on = cfg.enable && roleOn;

  lan = cfg.lan.interface;
  # Every NIC that can reach the house LAN (fix round 3): the desk's wired
  # port enp191s0 has an autoconnecting DHCP profile (MEASURED nmcli).
  lans = [ lan ] ++ cfg.lan.extraInterfaces;
  apiPort = lib.last (lib.splitString ":" cfg.apiListen);
  podIfs = [
    "cni0"
    "flannel.1"
  ];

  ipt = "${pkgs.iptables}/bin/iptables -w";
  ip6t = "${pkgs.iptables}/bin/ip6tables -w";
  registryPort = lib.last (lib.splitString ":" cfg.registry);

  # ── the guard chain (DESIGN 6.4), in mangle FORWARD, position 1 ──
  # It runs before the filter rules kube-proxy and flannel insert.
  #
  # First line, a correction to the design's list: established and related
  # traffic RETURNs. Without it the "wifi into pods only from the NAS" line
  # also drops every REPLY to a coordinator pod's own outbound connection
  # (atelet's anonymous GCS fetch, a worker pod reaching the LAN), because the
  # reply arrives on the LAN leg from a source that is not the NAS. Only NEW
  # flows are policed, which is the property the guard exists for.
  #
  # Deny by default (fix round 3). Round 2 listed interfaces (`-o ${lan}`),
  # so a second LAN leg (the wired port, a podman bridge) matched no DROP.
  # Now: pod egress is policed by DESTINATION on every output interface, and
  # nothing enters a pod interface unless a rule below lets it.
  guardRules = [
    "-m conntrack --ctstate ESTABLISHED,RELATED -j RETURN"
    # Into pods over VXLAN only from the pod network (fix round 1). Real
    # peers, the NAS host included (its flannel.1 address), are sourced
    # from the pod CIDR. Defence in depth, not the fix: LAN traffic the NAS
    # routes into VXLAN (MEASURED bypass, worker -> nas -> flannel.1 ->
    # harness pod, rc=0) is likely masqueraded by flannel's own rule to the
    # NAS's flannel.1 address (INFERRED), so the NAS's prerouting range
    # guard (control.nix) is what closes that path. This rule drops VXLAN
    # payloads whose inner source is outside the pod CIDR.
    "-i flannel.1 ! -s ${cfg.podCidr} -j DROP"
    # In-cluster: bridge-local and across nodes.
    "-i cni0 -o cni0 -j RETURN"
    "-i cni0 -o flannel.1 -j RETURN"
    "-i flannel.1 -o cni0 -j RETURN"
  ]
  # Into pods from outside the cluster: only the NAS host (hostPorts, the
  # apiserver), on a LAN leg. Everything else, any interface, is dropped.
  ++ map (l: "-i ${l} -o cni0 -s ${cfg.serverAddress} -j RETURN") lans
  ++ [
    "-o cni0 -j DROP"
    "-o flannel.1 -j DROP"
    "-i flannel.1 -j DROP"
    # Out of pods. Pod traffic leaving a LAN leg is masqueraded to this
    # host's address and would inherit every NAS rule that trusts the
    # coordinator (ssh, NFS, media, paperless). From pods, the LAN gets only
    # the apiserver and the registry on the NAS; the internet (atelet's GCS
    # fetch) is unaffected. Everything else in-cluster rides flannel.1.
    "-i cni0 -d ${cfg.serverAddress} -p tcp -m multiport --dports 6443,${registryPort} -j RETURN"
  ]
  # Every private range, not only the house /24 (fix round 1), on ANY output
  # interface (fix round 3): when NetworkManager falls back to the Freebox
  # profile (hosts/coordinator/uplink-nas.nix) the leg is a DHCP subnet this
  # module does not know, and 100.64/10 is the tailnet's range.
  ++ map (r: "-i cni0 -d ${r} -j DROP") privateRanges
  # The internet, over a LAN leg only; tailscale0, podman0 and anything else
  # a pod could be routed to are dropped.
  ++ map (l: "-i cni0 -o ${l} -j RETURN") lans
  ++ [ "-i cni0 -j DROP" ]
  # The tailnet and the house LAN never forward into each other, on any leg.
  ++ lib.concatMap (
    g:
    lib.concatMap (l: [
      "-i ${l} -o ${g} -j DROP"
      "-i ${g} -o ${l} -j DROP"
    ]) lans
  ) cfg.guardInterfaces;

  privateRanges = lib.unique [
    cfg.lan.cidr
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "100.64.0.0/10"
  ];

  # ── pods never open a connection to the coordinator host (fix round 2) ──
  # MEASURED by the round-2 review: from a pod, `nc 10.200.0.1 22` and the
  # node's LAN address answered SSH-2.0-OpenSSH, because nixos-fw accepts 22 on
  # every interface and the guard chain above sees FORWARD only. Nothing on
  # the Substrate path needs a NEW pod-to-host flow: hostPorts and ClusterIPs
  # are DNATed through FORWARD, kubelet reaches pods (OUTPUT, replies are
  # ESTABLISHED), atelet talks to kubelet and containerd over unix sockets, and
  # kubectl exec/logs ride the agent tunnel. First rules of nixos-fw, so they
  # run before its ESTABLISHED accept and every port rule; IPv6 too (link-local
  # addresses on cni0 and the veths).
  # Idempotent (fix round 4): deleted, then inserted, so guardApply can re-run
  # it over a live nixos-fw without duplicating a rule.
  podInputSpecs = map (
    p: "-i ${p} -m conntrack --ctstate NEW -m comment --comment ax-fleet-pod-input -j nixos-fw-refuse"
  ) podIfs;
  podInputCmds =
    t:
    lib.concatMapStringsSep "\n" (spec: ''
      while ${t} -D nixos-fw ${spec} 2>/dev/null; do :; done
      ${t} -I nixos-fw 1 ${spec}'') podInputSpecs;

  # ── the ax API and the cluster ranges: root, apiUsers and the proxy only ──
  # (fix round 3) The round-3 review MEASURED an unprivileged user applying a
  # Gateway with host 0.0.0.0/0 through the loopback proxy (the API has no
  # authentication, upstream #376). The same user could reach the ax-server
  # ClusterIP or pod directly through kube-proxy's OUTPUT DNAT, so the match
  # covers the cluster ranges as well as the proxy's port. filter OUTPUT sees
  # the post-DNAT address. Packets without a full socket (kernel replies,
  # TIME_WAIT) pass.
  apiUsersAll = [ "root" ] ++ cfg.apiUsers ++ [ "ax-server-proxy" ];
  apiRules = [
    "-m owner ! --socket-exists -j RETURN"
  ]
  ++ map (u: "-m owner --uid-owner ${u} -j RETURN") apiUsersAll
  ++ [
    "-d 127.0.0.1 -p tcp --dport ${apiPort} -j REJECT --reject-with tcp-reset"
    "-d ${cfg.podCidr} -j REJECT"
    "-d ${cfg.serviceCidr} -j REJECT"
  ];

  guardStart = ''
    # ax-fleet guard chain (idempotent)
    ${ipt} -t mangle -N ax-fleet-guard 2>/dev/null || true
    ${ipt} -t mangle -F ax-fleet-guard
    while ${ipt} -t mangle -D FORWARD -j ax-fleet-guard 2>/dev/null; do :; done
    ${ipt} -t mangle -I FORWARD 1 -j ax-fleet-guard
    ${lib.concatMapStringsSep "\n" (r: "${ipt} -t mangle -A ax-fleet-guard ${r}") guardRules}
    # pods to the host: refused (podInputSpecs)
    ${podInputCmds ipt}
    ${lib.optionalString config.networking.enableIPv6 (podInputCmds ip6t)}
    # the ax API and the cluster ranges from this host: owner match (fix round 3)
    ${ipt} -N ax-fleet-api 2>/dev/null || true
    ${ipt} -F ax-fleet-api
    while ${ipt} -D OUTPUT -j ax-fleet-api 2>/dev/null; do :; done
    ${ipt} -I OUTPUT 1 -j ax-fleet-api
    ${lib.concatMapStringsSep "\n" (r: "${ipt} -A ax-fleet-api ${r}") apiRules}
  '';

  # (fix round 4) The same rules as a script the teardown runs after
  # k3s-killall.sh: the killall's `iptables-save | grep -iv flannel |
  # iptables-restore` (REPORTED k3s-killall.sh:90 in the pinned k3s) deletes
  # every rule naming flannel.1, the guard's and the pod-input refusal's
  # included, and nothing reloads the firewall before k3s starts again.
  guardApply = pkgs.writeShellScript "ax-fleet-guard-apply" (''
    set -eu
  '' + guardStart);

  guardStop = ''
    while ${ipt} -t mangle -D FORWARD -j ax-fleet-guard 2>/dev/null; do :; done
    ${ipt} -t mangle -F ax-fleet-guard 2>/dev/null || true
    ${ipt} -t mangle -X ax-fleet-guard 2>/dev/null || true
    while ${ipt} -D OUTPUT -j ax-fleet-api 2>/dev/null; do :; done
    ${ipt} -F ax-fleet-api 2>/dev/null || true
    ${ipt} -X ax-fleet-api 2>/dev/null || true
  '';

  nmDropIn = ''
    # ax-fleet (modules/ax-fleet/harness.nix): k3s's own interfaces are never
    # NetworkManager's. Appended (+=) to whatever NetworkManager.conf lists.
    [keyfile]
    unmanaged-devices+=interface-name:cni0;interface-name:flannel*;interface-name:veth*
  ''
  # (fix round 3) The other LAN-capable NICs never take the house routes from
  # ${lan} while it is up: a profile that leaves ipv4.route-metric at -1 (the
  # desk's "Wired connection 1", MEASURED) takes this default instead of
  # ethernet's 100, which beat the wifi's 600. The NAS admits the harness to
  # 6443, the registry and VXLAN by ${lan}'s address only.
  + lib.optionalString (cfg.lan.extraInterfaces != [ ]) ''

    [connection-ax-fleet-extra-lan]
    match-device=${lib.concatMapStringsSep ";" (i: "interface-name:${i}") cfg.lan.extraInterfaces}
    ipv4.route-metric=${toString cfg.lan.extraRouteMetric}
    ipv6.route-metric=${toString cfg.lan.extraRouteMetric}
  '';

  kubeconfigScript = pkgs.writeShellApplication {
    name = "ax-fleet-kubeconfig";
    runtimeInputs = [
      pkgs.openssh
      pkgs.coreutils
    ];
    text = ''
      # Fetch the cluster admin kubeconfig from the NAS over the existing ssh
      # trust into ~/.kube/config (0600). The content is never printed.
      umask 077
      mkdir -p "$HOME/.kube"
      tmp=$(mktemp "$HOME/.kube/.config.XXXXXX")
      trap 'rm -f "$tmp"' EXIT
      ssh "''${AX_FLEET_NAS:-nas}" cat /etc/ax-fleet/admin.kubeconfig > "$tmp"
      [ -s "$tmp" ] || { echo "ax-fleet-kubeconfig: empty kubeconfig from the NAS" >&2; exit 1; }
      mv "$tmp" "$HOME/.kube/config"
      trap - EXIT
      echo "wrote $HOME/.kube/config"
    '';
  };
in
{
  config = lib.mkMerge [
  (lib.mkIf roleOn {
    networking.firewall.extraCommands = guardStart;
    networking.firewall.extraStopCommands = guardStop;
    # A fixed uid for the proxy, so the owner match can name it (DynamicUser
    # allocates from a range any other DynamicUser unit shares).
    users.users.ax-server-proxy = {
      isSystemUser = true;
      group = "ax-server-proxy";
    };
    users.groups.ax-server-proxy = { };
    # The teardown leaves a guard the generation declares (see pkgs/ax-fleet-teardown).
    environment.etc."ax-fleet/guard-declared".text = "harness\n";
    environment.etc."ax-fleet/guard-apply".source = guardApply;
    assertions = [
      {
        assertion = builtins.all (u: config.users.users ? ${u}) cfg.apiUsers;
        message = "modules/ax-fleet/harness.nix: every myAxFleet.apiUsers entry must be a declared user (iptables resolves the name when the firewall starts).";
      }
      {
        assertion = !(builtins.elem lan cfg.lan.extraInterfaces);
        message = "modules/ax-fleet/harness.nix: myAxFleet.lan.extraInterfaces must not repeat lan.interface.";
      }
    ];
  })
  (lib.mkIf on {
    myAxFleet.kubelet = {
      # Memory: Tom's seats, Chrome and a coordinator Halogen feel pressure
      # after the sandboxes are evicted, never before. CPU is the slices below:
      # system-reserved only shrinks kubepods.slice's weight, it protects
      # nothing.
      systemReserved = lib.mkDefault "cpu=8,memory=32Gi";
      kubeReserved = lib.mkDefault "cpu=1,memory=2Gi";
      # Every signal, not only memory (fix round 4): a set --eviction-hard
      # REPLACES kubelet's whole default map (MEASURED in the round-3 VM log:
      # HardEvictionThresholds=[memory.available] only), which dropped k3s's
      # nodefs/imagefs defaults. / here is also /nix/store, journald and the
      # coordinator's postgres (MEASURED findmnt: one nvme partition), so a
      # sandbox filling its writable layer must be evicted before they ENOSPC.
      evictionHard = lib.mkDefault "memory.available<8Gi,nodefs.available<10%,nodefs.inodesFree<5%,imagefs.available<15%,imagefs.inodesFree<5%";
    };

    # ── CPU: the desk outweighs the sandboxes (fix round 2) ──
    # kubelet gives kubepods.slice cpu.weight = 1 + ((allocatable_mcpu * 1024
    # / 1000 - 2) * 9999) / 262142: MEASURED 274 for 7 allocatable CPUs in the
    # review VM, INFERRED 899 for the desk's 32 - 8 - 1 = 23. user.slice and
    # system.slice are 100 on the live box (MEASURED), so under contention the
    # gVisor workers (no CPU limit, substrate.nix) would take about 90 % of the
    # CPU from niri, herdr, the seats and Chrome. Weights are work-conserving:
    # idle desk CPU still goes to the sandboxes. Both slices get the same
    # weight, so their ratio to each other is unchanged. switch-to-configuration
    # never restarts a slice; daemon-reload applies the property.
    systemd.slices.user.sliceConfig.CPUWeight = lib.mkDefault cfg.kubelet.deskCpuWeight;
    systemd.slices.system.sliceConfig.CPUWeight = lib.mkDefault cfg.kubelet.deskCpuWeight;

    services.k3s = {
      role = "agent";
      # The IP, not the name `nas`.
      serverAddr = "https://${cfg.serverAddress}:6443";
      nodeTaint = [ cfg.harnessTaint ];
      # Registered WITH the version label: ate-setup only labels nodes that
      # exist when it runs (MEASURED version.go:113-131), and the coordinator
      # joins after the NAS. Without it atelet (version-keyed) never lands.
      nodeLabel = [
        "ax.mecattaf.dev/role=harness"
        "ate.dev/substrate-version=${cfg.substrateVersion}"
      ];
    };

    # k3s turns ip_forward on at start anyway; the guard chain is what keeps
    # it safe. IPv6 forwarding stays 0 (the wifi leg keeps accepting RAs).
    # flannel VXLAN from the NAS only; no TCP port is opened. With the switch
    # on only: an accept, unlike the guards above.
    networking.firewall.extraCommands = ''
      ${ipt} -A nixos-fw -i ${lan} -s ${cfg.serverAddress} -p udp --dport 8472 -j nixos-fw-accept
    '';

    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    # Proxy ARP on the pod interfaces only (fix round 3). Round 2 set
    # `conf.default`, but every NIC created after systemd-sysctl copies
    # `default`, and the desk's NICs are renamed after it runs (MEASURED boot
    # journal: sysctl 6.356 s, enp191s0 6.497 s, wlp192s0 7.493 s), so
    # wlp192s0 would have answered ARP for the whole LAN after a reboot.
    # systemd's udev rule (99-systemd.rules) runs systemd-sysctl for each new
    # interface, which applies these by name and glob as each one appears.
    # `flannel/1` is sysctl.d's spelling of flannel.1.
    boot.kernel.sysctl."net.ipv4.conf.cni0.proxy_arp" = 1;
    boot.kernel.sysctl."net.ipv4.conf.flannel/1.proxy_arp" = 1;
    boot.kernel.sysctl."net.ipv4.conf.veth*.proxy_arp" = 1;

    # ── NetworkManager: a drop-in and a config reload, never a restart ──
    environment.etc."NetworkManager/conf.d/90-ax-fleet.conf".text = nmDropIn;
    systemd.services.ax-fleet-nm-unmanaged = {
      description = "ax-fleet: make NetworkManager re-read its conf.d (k3s interfaces unmanaged)";
      wantedBy = [ "multi-user.target" ];
      after = [ "NetworkManager.service" ];
      before = [ "k3s.service" ];
      restartTriggers = [ nmDropIn ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Tolerated: with NetworkManager down there is nothing to reload.
        ExecStart = "-${pkgs.networkmanager}/bin/nmcli general reload conf";
      };
    };
    systemd.services.k3s.wants = [ "ax-fleet-nm-unmanaged.service" ];

    # ── ax-server on ${cfg.apiListen}, through kube-proxy's OUTPUT rules ──
    # The ClusterIP is never a NodePort: ax's API has no authentication
    # (upstream #376). Loopback only, and only root, apiUsers and this proxy
    # may connect (apiRules). Not 127.0.0.1:8080 (fix round 3): that is
    # ax-conwip's default and ax-mockstack's, which must reach nothing live.
    systemd.sockets.ax-server-proxy = {
      description = "ax-fleet: ax-server on ${cfg.apiListen}";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ cfg.apiListen ];
    };
    systemd.services.ax-server-proxy = {
      description = "ax-fleet: proxy ${cfg.apiListen} to the ax-server ClusterIP";
      requires = [ "ax-server-proxy.socket" ];
      after = [ "ax-server-proxy.socket" ];
      serviceConfig = {
        ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd ${cfg.axServerClusterIP}:8080";
        User = "ax-server-proxy";
        Group = "ax-server-proxy";
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    environment.systemPackages = [ kubeconfigScript ];
  })
  ];
}
