{
  config,
  lib,
  pkgs,
  ...
}:
# ─── k3s on this fleet: one module, three roles, one set of numbers ─────────
#
# Tom, 2026-09-20: "kubernetes is world-class for that ... they each stay in
# their lane. Effects ts handles the ultracode-level json dag specification
# and kubernetes schedules it on the right machines."
#
# The shape (Appendix J section 9): server on the NAS with disableAgent, so
# the appliance holds the control plane and schedules nothing; agents on the
# two Strix boxes, which have the cores, the memory and /dev/kvm. State on the
# NAS, machines on the twins. That split is the whole design and it is the
# same split hosts/nas/state-services.nix makes for PostgreSQL and the object
# store.
#
# ── THE NUMBERS, AND WHY THE ASSERTION IS NOT INSIDE THE GATE ─────────────
# k3s defaults to 10.42.0.0/16 for pods and 10.43.0.0/16 for services. THE
# HOUSE LAN IS 10.42.0.0/24 (hosts/nas/network.nix, hosts/nas/router.nix:23's
# pool, modules/fleet-hosts.nix). Taking k3s's default would put every pod on
# an address range that contains the NAS, the coordinator, the worker, the
# printer and the router, and the failure would be a same-day whole-house
# outage on the box that is also the DNS server.
#
# Tom's own 2026-09-09 research already chose the replacement: pods
# 10.200.0.0/16, services 10.201.0.0/16. Those numbers are kept exactly, and
# the overlap check below is a REAL EVALUATED ASSERTION rather than a comment,
# placed OUTSIDE the `enable` gate on purpose. It costs nothing when k3s is
# off, and it means that the day somebody edits a CIDR the flake refuses to
# evaluate rather than the house losing DNS. An assertion in the flake is the
# only thing that makes this non-forgettable.
#
# ── WHAT IS NEVER REACHABLE FROM OUTSIDE THIS HOUSE ──────────────────────
# The kube API on :6443 is the cluster's root credential surface. It is opened
# on the NAS's LAN leg (`iifname "enp1s0"`) and on nothing else, and it is on
# hosts/nas/cloudflared.nix's never-routed list, which that file enforces with
# its own assertion. A tunnel ingress bypasses every nftables rule on the
# appliance, so "not in the tunnel" is a separate guarantee from "firewalled",
# and both are needed. Same for ateapi and ax-server when they land: neither
# implements authorization at all, so reachability IS full control.
#
# ── TRACK K AND TRACK S ARE THE SAME FILE ────────────────────────────────
# Design K is plain k3s with Cilium and a gVisor RuntimeClass, no Substrate
# and no ax. Design S adds Substrate on top of exactly this. The only thing
# Design S needs from the bottom layer that K does not is four feature-gate
# settings, and a feature gate that nothing asks for is inert: it changes no
# scheduling, admits no new controller, and costs no memory. So the gates are
# included unconditionally and this one module is both tracks. If Substrate is
# never installed, nothing here was wasted; if it is, nothing here has to
# change.
#
# ── THE FEATURE GATES, AND WHAT IS NOW MEASURED ──────────────────────────
# MEASURED from ~/Downloads/substrate, hack/create-kind-cluster.sh:104-112,
# which is upstream's own comment on why they are not optional:
#
#   # cmd/podcertcontroller depends on ClusterTrustBundle & PodCertificateRequest.
#   # They are not enabled by default as of Kubernetes v1.36
#   featureGates:
#     ClusterTrustBundle: true
#     ClusterTrustBundleProjection: true
#     PodCertificateRequest: true
#   runtimeConfig:
#     "certificates.k8s.io/v1beta1": "true"
#
# atelet's own pod mounts a projected podCertificate volume and a
# clusterTrustBundle volume (manifests/ate-install/atelet.yaml:271-289), and
# every Substrate component's mTLS identity comes from that signer.
#
# U9 IS ANSWERED, AND THE ANSWER IS YES. The first draft of this file said the
# opposite: that nothing about these gates was measured and that the first
# switch would tell us. A5a measured it the same night, inside a k3s
# 1.35.6+k3s1 guest built from this exact pin, and the answer is that the
# pinned k3s serves the group. MEASURED there:
#
#   kubectl get --raw /apis/certificates.k8s.io/v1beta1 | jq -r .resources[].name
#     clustertrustbundles
#     podcertificaterequests
#     podcertificaterequests/status
#   kubectl api-resources | grep -i "trustbundle\|podcertificate"
#     clustertrustbundles     certificates.k8s.io/v1beta1  false  ClusterTrustBundle
#     podcertificaterequests  certificates.k8s.io/v1beta1  true   PodCertificateRequest
#
# So Appendix J section 9's step 1 success criterion is met on the pin, its
# fallback paragraph does not have to be taken, and no newer k3s is needed for
# this reason. k3s_1_36 (1.36.2+k3s1) is in both stable and unstable if one is
# ever wanted for another.
#
# TWO THINGS THAT WOULD HAVE BEEN WRONG WITHOUT THAT MEASUREMENT, both fixed
# in this file and both worth knowing before editing it:
#   1. The three gates ALONE serve nothing. See runtimeConfigFlag below: the
#      metrics read 1 while the group version stays unserved, so a check that
#      read only the metric would have reported a false pass.
#   2. kubelet accepts all three gate names, including ClusterTrustBundle.
#      This file used to hand kubelet a subset out of caution. It no longer
#      needs to.
#
# ── GATE OFF ─────────────────────────────────────────────────────────────
# Every host lands with `enable = false`. secrets/k3s-token.age does not exist
# in the tree: minting it needs Tom's admin age key, and the overnight spike
# that opened this PR has none. Runbook in the header of each host's gate.
let
  cfg = config.myK3sFleet;

  # ── The numbers. One definition, three hosts. ──
  podCidr = "10.200.0.0/16";
  serviceCidr = "10.201.0.0/16";
  lanCidr = "10.42.0.0/24";

  nasLanInterface = "enp1s0";
  nasLanAddress = "10.42.0.1";
  apiPort = 6443;
  serverAddr = "https://nas:${toString apiPort}";

  # hosts/nas/state-services.nix's registry, same box, plain HTTP on the LAN.
  registryEndpoint = "${nasLanAddress}:5000";

  # ── CIDR arithmetic, so the overlap check is arithmetic and not a wish ──
  ipToInt =
    s:
    let
      o = map lib.toInt (lib.splitString "." s);
      at = builtins.elemAt o;
    in
    (at 0) * 16777216 + (at 1) * 65536 + (at 2) * 256 + (at 3);

  cidrRange =
    c:
    let
      parts = lib.splitString "/" c;
      base = ipToInt (builtins.head parts);
      bits = lib.toInt (builtins.elemAt parts 1);
      # 2 ^ (32 - bits), without a pow in lib.
      size = builtins.foldl' (a: _: a * 2) 1 (lib.range 1 (32 - bits));
    in
    {
      lo = base;
      hi = base + size - 1;
    };

  overlaps =
    a: b:
    let
      x = cidrRange a;
      y = cidrRange b;
    in
    x.lo <= y.hi && y.lo <= x.hi;

  # ── The feature gates Substrate needs (see the header) ──
  # All three, on all three components. The earlier draft of this file gave
  # kubelet only two of them, on the reasoning that ClusterTrustBundle is
  # apiserver-side and an unrecognised gate name is fatal to kubelet. A5a
  # MEASURED otherwise on 2026-09-20, inside a k3s 1.35.6+k3s1 guest built from
  # this exact pin: "the apiserver, the controller manager and the kubelet all
  # accept all three gate names. None of the three components refused an
  # unknown gate, and the node reached Ready in about ten seconds."
  substrateGates = [
    "ClusterTrustBundle=true"
    "ClusterTrustBundleProjection=true"
    "PodCertificateRequest=true"
  ];

  # ── THE FLAG THAT ACTUALLY DECIDES IT ─────────────────────────────────
  # The three gates alone serve NOTHING. A5a's boot 5 held the gates on and
  # dropped this line; MEASURED result:
  #
  #   kubernetes_feature_enabled{name="ClusterTrustBundle",stage="BETA"} 1
  #   kubernetes_feature_enabled{name="ClusterTrustBundleProjection"...} 1
  #   kubernetes_feature_enabled{name="PodCertificateRequest",stage="BETA"} 1
  #   kubectl get --raw /apis/certificates.k8s.io | jq -c .versions
  #     -> [{"groupVersion":"certificates.k8s.io/v1","version":"v1"}]
  #   kubectl api-resources | grep -i "trustbundle\|podcertificate"
  #     -> NO_RESOURCES
  #
  # So the gates flip to 1 while the group version stays unserved, and a check
  # that read only the metric would have reported a false pass. The group
  # version is turned on separately, by this flag, and podcertcontroller has
  # nothing to talk to without it. It is quoted straight out of upstream's own
  # kind config (hack/create-kind-cluster.sh:111-112, the `runtimeConfig`
  # block, which is the part a reader skips).
  runtimeConfigFlag = "runtime-config=certificates.k8s.io/v1beta1=true";

  serverFlags = [
    "--cluster-cidr=${podCidr}"
    "--service-cidr=${serviceCidr}"
    # Cilium is the CNI (autoDeployCharts below). flannel off and k3s's own
    # network policy controller off, because Cilium owns both.
    "--flannel-backend=none"
    "--disable-network-policy"
    # The API certificate has to be valid for the name the agents dial. They
    # dial `nas`, resolved by the static pins in modules/common.nix:130 and
    # modules/fleet-hosts.nix, not by DNS.
    "--tls-san=nas"
    # A5a's MEASURED working form: the value inside a `-arg=` carries NO leading
    # dashes of its own. Both flag families are required and neither is
    # sufficient alone; see runtimeConfigFlag above.
    "--kube-apiserver-arg=feature-gates=${lib.concatStringsSep "," substrateGates}"
    "--kube-apiserver-arg=${runtimeConfigFlag}"
    "--kube-controller-manager-arg=feature-gates=${lib.concatStringsSep "," substrateGates}"
    "--kubelet-arg=feature-gates=${lib.concatStringsSep "," substrateGates}"
  ];

  agentFlags = [
    "--kubelet-arg=feature-gates=${lib.concatStringsSep "," substrateGates}"
  ];

  # ── containerd: add runsc WITHOUT losing the stock config ──────────────
  # `{{ template "base" . }}` is the module's own documented way to keep k3s's
  # generated containerd configuration and append to it. Dropping that line
  # replaces the whole config and the node loses its CNI, its snapshotter and
  # its registry mirrors at once. It is one line and it is load-bearing.
  #
  # ── THE KEY PATH BELOW IS NOT THE ONE THE NIXPKGS EXAMPLE SHOWS ───────
  # The option's example (nixos/modules/services/cluster/rancher/default.nix
  # 628-646) documents
  #   [plugins."io.containerd.grpc.v1.cri".containerd.runtimes."custom"]
  # and that path is WRONG for this k3s. A5a MEASURED, 2026-09-20, reading the
  # config that k3s 1.35.6+k3s1 actually generates at
  # /var/lib/rancher/k3s/agent/etc/containerd/config.toml: the file starts
  # `version = 3` and its runtime table is
  #   [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]
  # That is containerd 2.x config v3 (the node reports containerd://2.2.5-k3s2).
  # A `grpc.v1.cri` block would be parsed, accepted and silently ignored, which
  # is the worst of the three outcomes. Use the path below, and check it again
  # the day the k3s pin moves a major version.
  #
  # ── AND runtime_path, NOT options.BinaryName ─────────────────────────
  # The first draft of this file used runtime_type "io.containerd.runc.v2" with
  # options.BinaryName pointing at an absolute runsc, which is the shape the
  # nixpkgs example suggests and which looks right. A5a MEASURED it and it is a
  # trap: a pod under that RuntimeClass reaches Running and STAYS "1/1 Running"
  # in kubelet's view, produces NO LOGS AT ALL, and `kubectl exec` into it
  # fails with `cannot execute in container ...: in state stopped`. The generic
  # runc shim starts runsc but carries neither its stdio nor its state. Do not
  # use BinaryName for gVisor. The nixpkgs gvisor package builds
  # containerd-shim-runsc-v1 beside runsc, and that shim is what goes here.
  containerdTemplate = ''
    {{ template "base" . }}

    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runsc]
      runtime_type = "io.containerd.runsc.v1"
      runtime_path = "${pkgs.gvisor}/bin/containerd-shim-runsc-v1"
  '';

  # The NAS registry is plain HTTP on the LAN (hosts/nas/state-services.nix
  # explains why: this segment never leaves enp1s0 and a self-signed layer
  # here adds a certificate to rotate and excludes no attacker). containerd
  # will not talk to an HTTP registry unless told, and this is how it is told.
  registriesYaml = ''
    mirrors:
      "${registryEndpoint}":
        endpoint:
          - "http://${registryEndpoint}"
    configs:
      "${registryEndpoint}":
        tls:
          insecure_skip_verify: true
  '';
in
{
  options.myK3sFleet = {
    enable = lib.mkEnableOption "this host's membership in the fleet k3s cluster (2026-09-20 sandbox spike; Appendix J section 9)";

    role = lib.mkOption {
      type = lib.types.enum [
        "server"
        "agent"
      ];
      default = "agent";
      description = ''
        server on the NAS (control plane only, schedules nothing); agent on
        the Strix boxes (where the machines are). The default is the safe one:
        an agent that dials a server it is not. The assertion below refuses a
        host whose role and hostname disagree, so a forgotten `role` on the
        appliance is an evaluation error and not a second control plane.
      '';
    };

    nodeLabels = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "fleet/role" = "desk";
        "fleet/kvm" = "true";
      };
      description = ''
        Declarative node labels, applied by kubelet at registration so a node
        that reboots comes back schedulable AND labelled. This is the whole
        reason the labels are here and not in a `kubectl label` someone has to
        remember.
      '';
    };

    ciliumVersion = lib.mkOption {
      type = lib.types.str;
      default = "1.18.14";
      description = "Cilium chart version. 1.18.14 is the latest of the 1.18 line; 1.19.8 exists and is the next step up.";
    };

    ciliumHash = lib.mkOption {
      type = lib.types.str;
      # MEASURED 2026-09-20 on the coordinator: built the chart's
      # fixed-output derivation with lib.fakeHash and took the hash the
      # mismatch reported, then rebuilt clean. Not guessed, and not left as
      # fakeHash -- so the first switch does not fail on it.
      default = "sha256-js/NLsDWeV+xlcrBc3giFaXltFTE5gey8Zaet5cqTWk=";
      description = ''
        Hash of the packaged Cilium chart. The module fetches the chart at
        build time as a fixed-output derivation, so a wrong hash fails the
        build with the right one in the message.
      '';
    };
  };

  config = lib.mkMerge [
    {
      # ── OUTSIDE THE GATE, ON PURPOSE ────────────────────────────────────
      # These evaluate on every host whether or not k3s is enabled, so an edit
      # to the CIDRs is caught at `nix eval` time rather than at outage time.
      assertions = [
        {
          assertion = !(overlaps podCidr lanCidr);
          message = "modules/k3s-fleet.nix: the pod CIDR ${podCidr} overlaps the house LAN ${lanCidr}. k3s's own default (10.42.0.0/16) does exactly this and would take the NAS, the coordinator, the worker, the printer and the router with it. Pick a range outside the LAN.";
        }
        {
          assertion = !(overlaps serviceCidr lanCidr);
          message = "modules/k3s-fleet.nix: the service CIDR ${serviceCidr} overlaps the house LAN ${lanCidr}. Pick a range outside the LAN.";
        }
        {
          assertion = !(overlaps podCidr serviceCidr);
          message = "modules/k3s-fleet.nix: the pod CIDR ${podCidr} and the service CIDR ${serviceCidr} overlap each other.";
        }
      ];
    }

    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.mySecrets.enable;
          message = "myK3sFleet needs agenix delivery for secrets/k3s-token.age on this host.";
        }
        {
          # The appliance is the only server, and the only server is the
          # appliance. Mechanical, because `role` has a default and a
          # forgotten one would otherwise be silent.
          assertion = (config.networking.hostName == "nas") == (cfg.role == "server");
          message = "modules/k3s-fleet.nix: ${config.networking.hostName} has role \"${cfg.role}\". The NAS is the server and nothing else is; the Strix boxes are agents and nothing else is.";
        }
      ];

      age.secrets.k3s-token = {
        file = ../secrets/k3s-token.age;
        mode = "0400";
      };

      services.k3s = {
        enable = true;
        inherit (cfg) role;
        tokenFile = config.age.secrets.k3s-token.path;
        nodeLabel = lib.mapAttrsToList (k: v: "${k}=${v}") cfg.nodeLabels;
        extraFlags = if cfg.role == "server" then serverFlags else agentFlags;
      };

      # Both sides of the cluster need to pull from the NAS registry.
      environment.etc."rancher/k3s/registries.yaml".text = registriesYaml;
    })

    # ── THE SERVER: the NAS ───────────────────────────────────────────────
    (lib.mkIf (cfg.enable && cfg.role == "server") {
      services.k3s = {
        # Embedded etcd rather than the stock sqlite. One server today and one
        # server for the foreseeable future, so this buys nothing operational;
        # it buys the ability to add a second server later without a datastore
        # migration on the box that is also the house router.
        clusterInit = true;
        # THE APPLIANCE SCHEDULES NOTHING. 8 threads and 22 GiB, running DNS,
        # DHCP, the binary cache, Paperless, Immich and headscale. Control
        # plane only; the machines are on the twins.
        disableAgent = true;
        disable = [
          "traefik"
          "servicelb"
        ];

        # Cilium as CNI, in the generation rather than in a `cilium install`
        # somebody has to remember after every reprovision. cilium-cli 0.19.6
        # is in the pin and stays in the toolbox for `cilium status` and
        # `cilium connectivity test`, which are read verbs.
        #
        # kubeProxyReplacement with k8sServiceHost/k8sServicePort is what lets
        # Cilium reach the API server before there is a CNI to reach it
        # through: the chicken-and-egg that makes a half-configured cluster
        # sit at "0/1 nodes ready" with no useful log line.
        autoDeployCharts.cilium = {
          name = "cilium";
          repo = "https://helm.cilium.io";
          version = cfg.ciliumVersion;
          hash = cfg.ciliumHash;
          values = {
            ipam.mode = "kubernetes";
            kubeProxyReplacement = true;
            k8sServiceHost = "nas";
            k8sServicePort = apiPort;
          };
        };

        manifests = {
          # The gVisor class. Handler "runsc" matches the containerd runtime
          # name added by containerdTemplate above on each AGENT -- a
          # RuntimeClass is a cluster-scoped name for a per-node containerd
          # runtime, so both halves have to agree and they are written in the
          # same file for that reason.
          gvisor-runtimeclass.content = {
            apiVersion = "node.k8s.io/v1";
            kind = "RuntimeClass";
            metadata.name = "gvisor";
            handler = "runsc";
          };

          # ── kata: DELIBERATELY NOT ENABLED ─────────────────────────────
          # The pin has kata-runtime 3.32.0, which builds
          # containerd-shim-kata-v2 with DEFAULT_HYPERVISOR=qemu and
          # HYPERVISORS=qemu, so Kata on QEMU is available from the pin today
          # and Kata on cloud-hypervisor is a makeFlags override rather than a
          # new package (Appendix J section 9). What is NOT known is whether a
          # Kata class under k3s's containerd actually runs the /process image
          # as a micro-VM on Strix silicon. That is U14, measured tonight; its
          # report is at
          # ~/today/review/2026-09-20/sandbox-spike/ (the U14 agent's file).
          # Read that before uncommenting. gVisor is the fallback class and is
          # the one enabled above.
          #
          # kata-runtimeclass.content = {
          #   apiVersion = "node.k8s.io/v1";
          #   kind = "RuntimeClass";
          #   metadata.name = "kata";
          #   handler = "kata-qemu";
          # };
        };
      };

      # ── THE KUBE API IS LAN-ONLY, AND IS NEVER IN THE TUNNEL ───────────
      # Interface-scoped, same shape as every other door on this box. :6443 is
      # the cluster's root credential surface; anything that can reach it can
      # schedule a privileged pod on either Strix box. hosts/nas/cloudflared.nix
      # carries the matching doctrine block and an assertion that refuses to
      # route it, because a tunnel ingress bypasses this rule entirely.
      networking.firewall.extraInputRules = ''
        iifname "${nasLanInterface}" tcp dport ${toString apiPort} accept comment "kube API, LAN leg only, NEVER in the tunnel"
      '';
    })

    # ── THE AGENTS: coordinator and worker ───────────────────────────────
    (lib.mkIf (cfg.enable && cfg.role == "agent") {
      services.k3s = {
        inherit serverAddr;
        containerdConfigTemplate = containerdTemplate;
      };

      # ── runsc ON THE k3s UNIT'S PATH: REQUIRED, NOT A CONVENIENCE ──────
      # `runtime_path` above tells containerd where the SHIM is. The shim then
      # execs `runsc` from its OWN $PATH, and the k3s unit has essentially
      # none: A5a MEASURED that the nixpkgs rancher module sets
      # `path = lib.optional config.boot.zfs.enabled config.boot.zfs.package`
      # and nothing else (default.nix:918), so the unit PATH is empty by
      # default and k3s relies on its own wrapper for iptables and friends.
      # Without this line every sandbox fails at creation, MEASURED:
      #
      #   Failed to create pod sandbox: rpc error: code = Unknown desc =
      #   failed to start sandbox "...": failed to create containerd task:
      #   failed to create shim task: OCI runtime create failed:
      #   exec: "runsc": executable file not found in $PATH
      #
      # Note also that gVisor is NOT auto-detected. A5a MEASURED that with
      # `gvisor` in environment.systemPackages and runsc resolvable at
      # /run/current-system/sw/bin/runsc, the generated containerd config
      # still contained only `runc` and `runhcs-wcow-process`. k3s ships
      # RuntimeClasses for crun, lunatic, nvidia, slight, spin, wasmedge,
      # wasmer, wasmtime and wws out of the box, and none for gVisor. The
      # runtime has to be declared, which is what this module does.
      #
      # CAUTION FOR THE NEXT EDITOR: this assignment REPLACES the unit PATH
      # rather than extending a populated one. A5a MEASURED `systemctl show
      # k3s -p Environment` afterwards containing only the two gvisor
      # directories. It did not break kube-proxy or flannel there because the
      # nixpkgs k3s package wraps its own binary with the tools it needs, but
      # anyone adding a second entry should append rather than assume.
      systemd.services.k3s.path = [ pkgs.gvisor ];
    })
  ];
}
