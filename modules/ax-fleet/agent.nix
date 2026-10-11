{
  config,
  lib,
  pkgs,
  ...
}:
# Shared guard rules for the Strix k3s agent. NAS is the only peer. Pods may
# reach the declared Halogen endpoint, registry and cluster APIs, but must not
# inherit the host's SSH, storage or tailnet authority. Keep guards active
# across a kill-switch transition until the explicit teardown removes pods.
let
  cfg = config.myAxFleet;
  # The firewall half (guard chain, pod-input refusal, API owner match) is
  # rendered for the agent ROLE, whatever `enable` says (fix round 3): the
  # kill switch stops k3s with KillMode=process, so pods, cni0 and flannel.1
  # outlive the switch until ax-fleet-teardown runs. The rules are inert once
  # those interfaces are gone.
  roleOn = cfg.role == "harness";
  on = cfg.enable && roleOn;
  isHarness = cfg.role == "harness";

  lan = cfg.lan.interface;
  # Every NIC that can reach the house LAN (fix round 3): the desk's wired
  # port enp191s0 has an autoconnecting DHCP profile (MEASURED nmcli). The
  # worker has one leg (no wifi profile, no tailnet).
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
  # traffic RETURNs. Without it the "LAN into pods only from the NAS" line
  # also drops every REPLY to a pod's own outbound connection (atelet's
  # anonymous GCS fetch, a worker pod reaching the LAN), because the reply
  # arrives on the LAN leg from a source that is not the NAS. Only NEW flows
  # are policed, which is the property the guard exists for.
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
    # host's address and would inherit every NAS rule that trusts this host
    # (the strix's ssh, NFS, media, paperless; the worker's journal
    # upload and models export). From pods, the LAN gets only the apiserver
    # and the registry on the NAS; the internet (atelet's GCS fetch) is
    # unaffected. Everything else in-cluster rides flannel.1.
    "-i cni0 -d ${cfg.serverAddress} -p tcp -m multiport --dports 6443,${registryPort} -j RETURN"
  ]
  # Every private range, not only the house /24 (fix round 1), on ANY output
  # interface (fix round 3): when NetworkManager falls back to the Freebox
  # profile (hosts/strix/uplink-nas.nix) the leg is a DHCP subnet this
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

  # ── pods never open a connection to the agent host (fix round 2) ──
  # MEASURED by the round-2 review on the strix: from a pod,
  # `nc 10.200.0.1 22` and the node's LAN address answered SSH-2.0-OpenSSH,
  # because nixos-fw accepts 22 on every interface and the guard chain above
  # sees FORWARD only. Nothing on the Substrate path needs a NEW pod-to-host
  # flow: hostPorts and ClusterIPs are DNATed through FORWARD, kubelet reaches
  # pods (OUTPUT, replies are ESTABLISHED), atelet talks to kubelet and
  # containerd over unix sockets, and kubectl exec/logs ride the agent tunnel.
  # First rules of nixos-fw, so they run before its ESTABLISHED accept and
  # every port rule; IPv6 too (link-local addresses on cni0 and the veths).
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

  # ── the cluster ranges (and the harness's ax API): root and apiUsers only ──
  # (fix round 3) The round-3 review MEASURED an unprivileged user on the desk
  # applying a Gateway with host 0.0.0.0/0 through the loopback proxy (the API
  # has no authentication, upstream #376). The same user could reach the
  # ax-server ClusterIP or pod directly through kube-proxy's OUTPUT DNAT, so
  # the match covers the cluster ranges as well as the proxy's port. filter
  # OUTPUT sees the post-DNAT address. Packets without a full socket (kernel
  # replies, TIME_WAIT) pass. The proxy user and its port exist on the
  # harness only (./harness.nix); on the worker the chain is the cluster
  # ranges alone. The Halogen container is rootful podman with host
  # networking (modules/halogen.nix), so it passes the root match.
  apiUsersAll = [ "root" ] ++ cfg.apiUsers ++ lib.optional isHarness "ax-server-proxy";
  apiRules = [
    "-m owner ! --socket-exists -j RETURN"
  ]
  ++ map (u: "-m owner --uid-owner ${u} -j RETURN") apiUsersAll
  ++ lib.optional isHarness "-d 127.0.0.1 -p tcp --dport ${apiPort} -j REJECT --reject-with tcp-reset"
  ++ [
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
  guardApply = pkgs.writeShellScript "ax-fleet-guard-apply" (
    ''
      set -eu
    ''
    + guardStart
  );

  guardStop = ''
    while ${ipt} -t mangle -D FORWARD -j ax-fleet-guard 2>/dev/null; do :; done
    ${ipt} -t mangle -F ax-fleet-guard 2>/dev/null || true
    ${ipt} -t mangle -X ax-fleet-guard 2>/dev/null || true
    while ${ipt} -D OUTPUT -j ax-fleet-api 2>/dev/null; do :; done
    ${ipt} -F ax-fleet-api 2>/dev/null || true
    ${ipt} -X ax-fleet-api 2>/dev/null || true
  '';

  # ── flannel VXLAN: from the server and from every other agent ──
  # The NAS's LAN address and agentAddresses, minus this host's own. Source
  # address only, on the flannel leg; plain VXLAN over the desk's wifi leg is
  # spoofable (DESIGN.md Unknowns).
  vxlanPeers = lib.remove cfg.lan.address ([ cfg.serverAddress ] ++ cfg.agentAddresses);

  # The drop-in's [keyfile] half. The text still names harness.nix, where it
  # was written: any byte change here re-runs `nmcli general reload conf` on
  # the strix at its next switch (restartTriggers below), and the split
  # that moved it here changes nothing on the strix but the VXLAN peer
  # rule. ./harness.nix appends the desk's extra-LAN section (lines merge).
  nmDropIn = ''
    # ax-fleet (modules/ax-fleet/harness.nix): k3s's own interfaces are never
    # NetworkManager's. Appended (+=) to whatever NetworkManager.conf lists.
    [keyfile]
    unmanaged-devices+=interface-name:cni0;interface-name:flannel*;interface-name:veth*
  '';
  nmDropInPath = "NetworkManager/conf.d/90-ax-fleet.conf";
in
{
  config = lib.mkMerge [
    (lib.mkIf roleOn {
      networking.firewall.extraCommands = guardStart;
      networking.firewall.extraStopCommands = guardStop;
      # The teardown leaves a guard the generation declares (see pkgs/ax-fleet-teardown).
      environment.etc."ax-fleet/guard-declared".text = "${cfg.role}\n";
      environment.etc."ax-fleet/guard-apply".source = guardApply;
      assertions = [
        {
          assertion = builtins.all (u: config.users.users ? ${u}) cfg.apiUsers;
          message = "modules/ax-fleet/agent.nix: every myAxFleet.apiUsers entry must be a declared user (iptables resolves the name when the firewall starts).";
        }
        {
          assertion = !(builtins.elem lan cfg.lan.extraInterfaces);
          message = "modules/ax-fleet/agent.nix: myAxFleet.lan.extraInterfaces must not repeat lan.interface.";
        }
      ];
    })
    (lib.mkIf on {
      # k3s turns ip_forward on at start anyway; the guard chain is what keeps
      # it safe. IPv6 forwarding stays 0. No TCP port is opened. With the
      # switch on only: an accept, unlike the guards above.
      networking.firewall.extraCommands = lib.concatMapStrings (p: ''
        ${ipt} -A nixos-fw -i ${lan} -s ${p} -p udp --dport 8472 -j nixos-fw-accept
      '') vxlanPeers;

      boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

      # ── NetworkManager: a drop-in and a config reload, never a restart ──
      # `networking.networkmanager.unmanaged` rewrites NetworkManager.conf,
      # NetworkManager's restart trigger with stopIfChanged = true (MEASURED
      # nix eval on the desk), which would drop the desk's wifi. A conf.d
      # drop-in plus `nmcli general reload conf` instead.
      environment.etc.${nmDropInPath}.text = nmDropIn;
      systemd.services.ax-fleet-nm-unmanaged = {
        description = "ax-fleet: make NetworkManager re-read its conf.d (k3s interfaces unmanaged)";
        wantedBy = [ "multi-user.target" ];
        after = [ "NetworkManager.service" ];
        before = [ "k3s.service" ];
        # The whole drop-in, the harness's extra-LAN section included.
        restartTriggers = [ config.environment.etc.${nmDropInPath}.text ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # Tolerated: with NetworkManager down there is nothing to reload.
          ExecStart = "-${pkgs.networkmanager}/bin/nmcli general reload conf";
        };
      };
      systemd.services.k3s.wants = [ "ax-fleet-nm-unmanaged.service" ];
    })
  ];
}
