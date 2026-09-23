{
  lib,
  inputs,
  ...
}:
# ax on the fleet: the options, and nothing else.
#
# Design: ~/today/evals-2026-09-23/ax-fleet/DESIGN.md section 5. Tom's ruling
# (2026-09-23, verbatim): "this is a dotfiles task to do on my nixos fleet. the
# decisions there were already made: hypervisor on NAS, agent harnesses on
# coordinator, halogen inference mainly on worker (can also run on coordinator
# if we need redundancy or a second parallel halogen task)."
#
# `enable` is THE kill switch. Its default is false, so a host that imports
# this module and says nothing renders nothing from it. The substrate and ax
# tracks write only the three extension points at the bottom (`manifests`,
# `registrySeed`, `bootstrap`); everything above them is read by the cluster
# modules next to this file.
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.myAxFleet = {
    enable = mkEnableOption "this host's part of ax on the fleet (k3s, Substrate, ax). THE kill switch";

    role = mkOption {
      type = types.enum [
        "control"
        "harness"
        "inference"
      ];
      description = ''
        control = the NAS (k3s server, Substrate and ax control planes, the
        registry). harness = the coordinator (k3s agent, gVisor sandboxes).
        inference = the worker (Halogen as a host service; nothing from this
        PR at runtime). Asserted against the hostname in ./default.nix.
      '';
    };

    lan = {
      interface = mkOption {
        type = types.str;
        example = "enp1s0";
        description = "The LAN leg: enp1s0 (nas), wlp192s0 (coordinator), enp191s0 (worker). Tests use eth1.";
      };
      address = mkOption {
        type = types.str;
        example = "10.42.0.1";
        description = "This host's address on the LAN leg.";
      };
      cidr = mkOption {
        type = types.str;
        default = "10.42.0.0/24";
      };
      extraInterfaces = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "enp191s0" ];
        description = ''
          Other NICs that can reach the house LAN (fix round 3): the
          coordinator's wired port enp191s0 has an autoconnecting DHCP profile.
          On the harness role the guard chain treats them as LAN legs, and a
          NetworkManager drop-in gives them `extraRouteMetric`, so the LAN
          routes stay on `interface` while it is up. Tests use [ "eth3" ].
        '';
      };
      extraRouteMetric = mkOption {
        type = types.int;
        default = 700;
        description = "Route metric for `extraInterfaces` (NetworkManager's wifi default is 600, ethernet 100).";
      };
    };

    apiListen = mkOption {
      type = types.str;
      default = "127.0.0.1:8099";
      description = ''
        Loopback address of ax-server-proxy.socket on the harness (fix round 3:
        not 127.0.0.1:8080, which ax-conwip's default and ax-mockstack own).
        AX_SERVER points here.
      '';
    };
    apiUsers = mkOption {
      type = types.listOf types.str;
      default = [ "tom" ];
      description = ''
        Local users (besides root) that may open connections to `apiListen`
        and to the cluster ranges from the harness host (fix round 3). The ax
        API has no authentication (upstream #376); everyone else is refused by
        an owner match in OUTPUT.
      '';
    };

    guardInterfaces = mkOption {
      type = types.listOf types.str;
      default = [ "tailscale0" ];
      description = "Interfaces the coordinator guard chain isolates from pods and from the LAN leg (the tailnet). Tests use [ \"eth2\" ].";
    };

    serverAddress = mkOption {
      type = types.str;
      default = "10.42.0.1";
      description = "The k3s server the harness agent dials: the IP, never the name.";
    };
    harnessAddresses = mkOption {
      type = types.listOf types.str;
      default = [ "10.42.0.2" ];
      description = "LAN addresses of harness nodes: the only sources the NAS admits to 6443, the registry and VXLAN.";
    };
    podCidr = mkOption {
      type = types.str;
      default = "10.200.0.0/16";
    };
    serviceCidr = mkOption {
      type = types.str;
      default = "10.201.0.0/16";
    };
    clusterDns = mkOption {
      type = types.str;
      default = "10.201.0.10";
    };
    axServerClusterIP = mkOption {
      type = types.str;
      default = "10.201.0.80";
    };
    nodePortRange = mkOption {
      type = types.str;
      default = "30000-30999";
      description = "Kept below 32400 (Plex on the NAS, a listener on the coordinator).";
    };

    k3sPackage = mkOption {
      type = types.package;
      default = inputs.nixpkgs.legacyPackages.x86_64-linux.k3s_1_36;
      defaultText = lib.literalExpression "inputs.nixpkgs.legacyPackages.x86_64-linux.k3s_1_36";
      description = "One k3s derivation for every node: the one the 2026-09-23 probe ran (1.36.2+k3s1 from the dotfiles nixpkgs pin, not stable's).";
    };

    k3sTokenFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        null (the default) means the agenix secret secrets/k3s-token.age,
        declared by ./k3s.nix. Tests set a path to a plain file instead.
      '';
    };

    k3sAgentTokenFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        The agent join credential (server --agent-token-file, agent
        --token-file). null (the default) means the agenix secret
        secrets/k3s-agent-token.age, declared by ./k3s.nix. Tests set a path
        to a plain file instead.
      '';
    };

    stateRoot = mkOption {
      type = types.str;
      default = "/mnt/fast";
      description = "The NAS's fast tier. k3s hot state (/var/lib/rancher, /var/lib/kubelet, /var/log/pods) is bind-mounted from <stateRoot>/k3s.";
    };
    localPathRoot = mkOption {
      type = types.str;
      default = "/mnt/nas/services/ax-fleet/local-path";
      description = "Every PersistentVolume (k3s local-path), on the data pool.";
    };
    registryRoot = mkOption {
      type = types.str;
      default = "/mnt/nas/services/ax-fleet/registry";
    };
    registry = mkOption {
      type = types.str;
      default = "10.42.0.1:5000";
      description = "The NAS registry, plain HTTP, LAN only, scoped to the coordinator by nftables.";
    };

    substrateVersion = mkOption {
      type = types.str;
      default = "d277088b";
      description = "One string: the harness node label value, the component image tag and ate-setup's VERSION.";
    };
    harnessTaint = mkOption {
      type = types.str;
      default = "ate.dev/sandboxClass=gvisor:NoSchedule";
      description = "Upstream Substrate's own taint key (atelet tolerates it).";
    };

    kubelet = {
      systemReserved = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "kubelet --system-reserved. Defaults per role in control.nix / harness.nix; tests shrink it.";
      };
      kubeReserved = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      evictionHard = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      deskCpuWeight = mkOption {
        type = types.ints.between 1 10000;
        default = 10000;
        description = ''
          Harness role: cpu.weight for user.slice and system.slice, against
          kubepods.slice's kubelet-computed weight (INFERRED 899 on the desk).
          The desk wins CPU contention; idle CPU still goes to the sandboxes.
        '';
      };
      keepHostKernelTunables = mkOption {
        type = types.bool;
        default = true;
        description = ''
          kubelet sets kernel.panic=10, kernel.panic_on_oops=1 and
          vm.overcommit_memory=1 when it starts (REPORTED by the VM receipt).
          On the desk that turns any kernel oops into a reboot 10 s later,
          dropping herdr and every seat. true: ax-fleet-kernel-tunables puts
          the three keys back to the values recorded before k3s first ran,
          after every kubelet start. false: kubelet's values stay. Tom's
          ruling is pending (Waiting on you, 2026-09-23); true is the default
          because it changes nothing for Tom at switch.
        '';
      };
    };

    workerPool = {
      replicas = mkOption {
        type = types.ints.positive;
        default = 2;
      };
      memoryLimit = mkOption {
        type = types.str;
        default = "16Gi";
      };
      unreachableTolerationSeconds = mkOption {
        type = types.ints.unsigned;
        default = 3600;
        description = "A configuration value, not an estimate: how long worker pods tolerate an unreachable or not-ready coordinator.";
      };
    };

    halogenEndpoint = mkOption {
      type = types.str;
      default = "10.42.0.5:8731";
    };

    # ── Extension points. The substrate and ax tracks write ONLY these. ──
    manifests = mkOption {
      type = types.attrsOf (
        types.submodule {
          options.source = mkOption {
            type = types.path;
            description = "A YAML file; linked into k3s's auto-deploy directory on the NAS as <name>.yaml.";
          };
        }
      );
      default = { };
      description = "Our own ax-system objects, auto-deployed by k3s on the NAS. Substrate itself is installed by ate-setup (bootstrap), not here.";
    };

    registrySeed = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            oci = mkOption {
              type = types.package;
              description = "An OCI image layout at the output root (oci-layout, index.json, blobs/) plus a `digest` file holding the manifest digest (sha256:...).";
            };
            repo = mkOption { type = types.str; };
            tag = mkOption { type = types.str; };
          };
        }
      );
      default = { };
      description = "Images the NAS copies into its own registry (skopeo --preserve-digests) before the bootstrap runs.";
    };

    bootstrap = mkOption {
      type = types.attrsOf types.lines;
      default = { };
      description = ''
        "NN-name" -> idempotent bash, run by ax-fleet-bootstrap.service on the
        NAS in name order, with KUBECONFIG set to the k3s admin kubeconfig.
        The cluster track owns 10-api and 60-kubeconfig.
      '';
    };
  };
}
