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
# What must NOT change for Tom at switch, and how the fleet modules keep it:
#   - NetworkManager is not restarted. `networking.networkmanager.unmanaged`
#     rewrites NetworkManager.conf, NetworkManager's restart trigger with
#     stopIfChanged = true (MEASURED nix eval), which would drop the desk's
#     wifi. A conf.d drop-in plus `nmcli general reload conf` instead
#     (./agent.nix; the extra-LAN section below).
#   - the tailnet: flannel and kube-proxy bind the LAN leg only, nothing is
#     published, and the guard chain keeps pods, wifi and the tailnet apart
#     even though k3s turns ip_forward on (judge 1's second risk). The guard
#     chain polices FORWARD only; pods reaching the coordinator HOST (sshd,
#     which accepts passwords) go through INPUT, so pod interfaces get their
#     own refusal at the head of nixos-fw (fix round 2). The chain covers the
#     direct path; the path routed through the NAS into VXLAN is closed twice,
#     by the NAS's prerouting range guard (control.nix) and by the flannel.1
#     source rule. Plain VXLAN on the wifi leg is accepted by source address
#     only (spoofable over wifi); see DESIGN.md Unknowns. All of these are
#     every agent's, not the desk's, and live in ./agent.nix, byte-identical
#     on this host.
#   - the kernel's panic behaviour: kubelet's kernel.panic / panic_on_oops /
#     overcommit values are put back after it starts
#     (myAxFleet.kubelet.keepHostKernelTunables, k3s.nix).
#   - herdr and every user unit: only system units are added.
#   - no containerd template, no runsc on PATH, no RuntimeClass (Substrate
#     runs its own runsc in the worker pods).
#
# What stays here, the desk's alone: the ax-server-proxy user, socket and
# service (AX_SERVER points at it), the kubeconfig fetcher, the desk's CPU
# slices, the extra-LAN route metric, proxy ARP for the gVisor pods, the
# harness taint and labels, and the harness kubelet reservations.
let
  cfg = config.myAxFleet;
  # The ax-server-proxy user is rendered for the harness ROLE, whatever
  # `enable` says: the role's owner match in ./agent.nix names it, and
  # iptables resolves the name whenever the firewall starts.
  roleOn = cfg.role == "harness";
  on = cfg.enable && roleOn;

  # (fix round 3) The desk's other LAN-capable NICs never take the house
  # routes from lan.interface while it is up: a profile that leaves
  # ipv4.route-metric at -1 (the desk's "Wired connection 1", MEASURED) takes
  # this default instead of ethernet's 100, which beat the wifi's 600. The NAS
  # admits the harness to 6443, the registry and VXLAN by lan.interface's
  # address only. Appended to ./agent.nix's drop-in (a lines option; mkAfter
  # keeps it after the [keyfile] half, byte-identical to the file before the
  # split).
  nmExtraLan = ''
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
      # A fixed uid for the proxy, so the owner match (./agent.nix) can name
      # it (DynamicUser allocates from a range any other DynamicUser unit
      # shares).
      users.users.ax-server-proxy = {
        isSystemUser = true;
        group = "ax-server-proxy";
      };
      users.groups.ax-server-proxy = { };
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

      # The guard chain, the pod-input refusal, the owner match, the VXLAN
      # accepts, ip_forward and the NetworkManager drop-in are every agent's:
      # ./agent.nix. What follows is the desk's alone.

      # Proxy ARP on the pod interfaces only (fix round 3), for the gVisor
      # worker pods. Round 2 set `conf.default`, but every NIC created after
      # systemd-sysctl copies `default`, and the desk's NICs are renamed after
      # it runs (MEASURED boot journal: sysctl 6.356 s, enp191s0 6.497 s,
      # wlp192s0 7.493 s), so wlp192s0 would have answered ARP for the whole
      # LAN after a reboot. systemd's udev rule (99-systemd.rules) runs
      # systemd-sysctl for each new interface, which applies these by name and
      # glob as each one appears. `flannel/1` is sysctl.d's spelling of
      # flannel.1.
      boot.kernel.sysctl."net.ipv4.conf.cni0.proxy_arp" = 1;
      boot.kernel.sysctl."net.ipv4.conf.flannel/1.proxy_arp" = 1;
      boot.kernel.sysctl."net.ipv4.conf.veth*.proxy_arp" = 1;

      # The desk's second LAN leg keeps its route metric (nmExtraLan above).
      environment.etc."NetworkManager/conf.d/90-ax-fleet.conf".text = lib.mkIf (
        cfg.lan.extraInterfaces != [ ]
      ) (lib.mkAfter nmExtraLan);

      # ── ax-server on ${cfg.apiListen}, through kube-proxy's OUTPUT rules ──
      # The ClusterIP is never a NodePort: ax's API has no authentication
      # (upstream #376). Loopback only, and only root, apiUsers and this proxy
      # may connect (apiRules in ./agent.nix). Not 127.0.0.1:8080 (fix round
      # 3): that is ax-conwip's default and ax-mockstack's, which must reach
      # nothing live.
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
