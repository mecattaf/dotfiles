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
#     apart even though k3s turns ip_forward on (judge 1's second risk).
#   - herdr and every user unit: only system units are added.
#   - no containerd template, no runsc on PATH, no RuntimeClass (Substrate
#     runs its own runsc in the worker pods).
let
  cfg = config.myAxFleet;
  on = cfg.enable && cfg.role == "harness";

  lan = cfg.lan.interface;
  podIfs = [
    "cni0"
    "flannel.1"
  ];

  ipt = "${pkgs.iptables}/bin/iptables -w";
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
  guardRules =
    [ "-m conntrack --ctstate ESTABLISHED,RELATED -j RETURN" ]
    ++ lib.concatMap (
      g:
      lib.concatMap (p: [
        "-i ${g} -o ${p} -j DROP"
        "-i ${p} -o ${g} -j DROP"
      ]) podIfs
      ++ [
        "-i ${lan} -o ${g} -j DROP"
        "-i ${g} -o ${lan} -j DROP"
      ]
    ) cfg.guardInterfaces
    ++ [
      "-i ${lan} -o cni0 ! -s ${cfg.serverAddress} -j DROP"
      # Pod traffic leaving on the LAN leg is masqueraded to this host's LAN
      # address and would inherit every NAS rule that trusts the coordinator
      # (ssh, NFS, media, paperless). From pods, the LAN gets only the
      # apiserver and the registry on the NAS; the internet (atelet's GCS
      # fetch) is unaffected. Everything else in-cluster rides flannel.1.
      "-i cni0 -o ${lan} -d ${cfg.serverAddress} -p tcp -m multiport --dports 6443,${registryPort} -j RETURN"
      "-i cni0 -o ${lan} -d ${cfg.lan.cidr} -j DROP"
    ];

  guardStart = ''
    # ax-fleet guard chain (idempotent)
    ${ipt} -t mangle -N ax-fleet-guard 2>/dev/null || true
    ${ipt} -t mangle -F ax-fleet-guard
    while ${ipt} -t mangle -D FORWARD -j ax-fleet-guard 2>/dev/null; do :; done
    ${ipt} -t mangle -I FORWARD 1 -j ax-fleet-guard
    ${lib.concatMapStringsSep "\n" (r: "${ipt} -t mangle -A ax-fleet-guard ${r}") guardRules}
    # flannel VXLAN from the NAS only; no TCP port is opened.
    ${ipt} -A nixos-fw -i ${lan} -s ${cfg.serverAddress} -p udp --dport 8472 -j nixos-fw-accept
  '';

  guardStop = ''
    while ${ipt} -t mangle -D FORWARD -j ax-fleet-guard 2>/dev/null; do :; done
    ${ipt} -t mangle -F ax-fleet-guard 2>/dev/null || true
    ${ipt} -t mangle -X ax-fleet-guard 2>/dev/null || true
  '';

  nmDropIn = ''
    # ax-fleet (modules/ax-fleet/harness.nix): k3s's own interfaces are never
    # NetworkManager's. Appended (+=) to whatever NetworkManager.conf lists.
    [keyfile]
    unmanaged-devices+=interface-name:cni0;interface-name:flannel*;interface-name:veth*
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
  config = lib.mkIf on {
    myAxFleet.kubelet = {
      # Tom's seats, Chrome and a coordinator Halogen feel pressure after the
      # sandboxes are evicted, never before.
      systemReserved = lib.mkDefault "cpu=8,memory=32Gi";
      kubeReserved = lib.mkDefault "cpu=1,memory=2Gi";
      evictionHard = lib.mkDefault "memory.available<8Gi";
    };

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
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    # `default`, not `all`: only interfaces created after this applies (cni0,
    # veth*, flannel.1) get proxy ARP; wlp192s0 never answers ARP for
    # addresses it routes elsewhere. `all` is Tom's call (DESIGN Unknowns 11).
    boot.kernel.sysctl."net.ipv4.conf.default.proxy_arp" = 1;

    networking.firewall.extraCommands = guardStart;
    networking.firewall.extraStopCommands = guardStop;

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

    # ── ax-server on 127.0.0.1:8080, through kube-proxy's OUTPUT rules ──
    # The ClusterIP is never a NodePort: ax's API has no authentication
    # (upstream #376). Loopback only.
    systemd.sockets.ax-server-proxy = {
      description = "ax-fleet: ax-server on 127.0.0.1:8080";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "127.0.0.1:8080" ];
    };
    systemd.services.ax-server-proxy = {
      description = "ax-fleet: proxy 127.0.0.1:8080 to the ax-server ClusterIP";
      requires = [ "ax-server-proxy.socket" ];
      after = [ "ax-server-proxy.socket" ];
      serviceConfig = {
        ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd ${cfg.axServerClusterIP}:8080";
        DynamicUser = true;
        PrivateTmp = true;
      };
    };

    environment.systemPackages = [ kubeconfigScript ];
  };
}
