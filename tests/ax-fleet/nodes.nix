{
  pkgs,
  lib,
  inputs,
}:
# The four VMs of checks.x86_64-linux.ax-fleet (DESIGN.md 12.1), shared with
# checks.x86_64-linux.ax-fleet-boot. They carry the fleet's real hostnames and
# LAN addresses, so every manifest and firewall rule the modules render is the
# production one; only interface names (eth1, eth2), the token and the kubelet
# reservations differ, and ax-fleet-topology pins that parity.
#
# Each base config is "today": it does NOT import modules/ax-fleet at all, as
# origin/main's hosts/{nas,coordinator} do not (fix round 4: the round-3 base
# carried the role, so every role-scoped guard was already in place before the
# switch). Two specialisations import the fleet module:
#   ax-on   myAxFleet.enable = true; the test switches to it live, NAS first,
#           exactly as Tom will.
#   ax-off  the role declared, enable = false: the kill switch (DESIGN 13).
# 90-rollback runs the kill switch on the coordinator, and the generation
# rollback (back to this base) on both hosts.
#
# The worker is different, as on the fleet, where it has imported the module
# since 2026-09-23: its base carries the inference role with enable = false,
# so the role's guards render from boot (modules/ax-fleet/agent.nix) and it
# serves the earlier phases as the plain LAN host and internet stand-in. Its
# ax-on specialisation joins the cluster as the tainted inference agent
# (2026-09-25: "the amd strix halo worker SHOULD be available in the cluster
# (not just halogen inference)"); 38-worker-join switches to it after
# 35-lan-guard, whose negative probes need a worker that is not a node.
# Its kill switch is the base itself.
let
  # A plain file, test-only, not a secret: the fleet reads agenix instead.
  token = pkgs.writeText "ax-fleet-vm-token" "ax-fleet-vm-test-token-0123456789abcdef";
  # The agent credential, distinct from the server token as on the fleet.
  agentToken = pkgs.writeText "ax-fleet-vm-agent-token" "ax-fleet-vm-agent-token-fedcba9876543210";

  # busybox (httpd, nslookup) plus curl, imported by k3s from the images
  # directory on both nodes, so probe pods need no registry and no network.
  probeImage = pkgs.dockerTools.buildImage {
    name = "ax-fleet-probe";
    tag = "test";
    copyToRoot = pkgs.buildEnv {
      name = "ax-fleet-probe-root";
      paths = [
        pkgs.busybox
        pkgs.curl
        pkgs.cacert
      ];
      pathsToLink = [
        "/bin"
        "/etc"
      ];
    };
    config.Cmd = [
      "/bin/sh"
      "-c"
      "sleep 1000000"
    ];
  };

  # Test-only: the fleet task image (pkgs/ax-agent-image, the same ax and pi
  # the fleet seeds) plus claude-code, for 25-harness-probe's `claude
  # --version`. No credential exists in it or in any Task. The fleet image
  # itself stays pi-only on day one (DESIGN.md 10.2 and 11); only the NAS test
  # node seeds this variant, from its ax-on specialisation.
  claudeProbeImage =
    inputs.nixpkgs.legacyPackages.x86_64-linux.callPackage ../../pkgs/ax-agent-image
      {
        ax = inputs.self.packages.x86_64-linux.ax;
        pi = inputs.llm-agents.packages.x86_64-linux.pi;
        extraPaths = [ inputs.llm-agents.packages.x86_64-linux.claude-code ];
        variant = "-claude-probe";
      };

  # probe/ax-fleet-nop1, test-only: Substrate's own kubectl plugin from the
  # same pinned source, so the no-P1 phase can list actors, templates and
  # workers (leak and worker-freed checks). Not in any host closure.
  kubectlAte =
    (pkgs.callPackage ../../pkgs/substrate {
      go_1_27 = inputs.nixpkgs-go.legacyPackages.x86_64-linux.go_1_27;
    }).ate-setup.overrideAttrs
      (o: {
        pname = "kubectl-ate";
        subPackages = [ "cmd/kubectl-ate" ];
        meta = o.meta // {
          mainProgram = "kubectl-ate";
        };
      });

  lanAddr = address: {
    interface = "eth1";
    inherit address;
  };

  setAddr = iface: address: prefixLength: {
    networking.interfaces.${iface}.ipv4.addresses = lib.mkForce [ { inherit address prefixLength; } ];
  };

  # Everything that makes a node a fleet node in the test (the ax-on and
  # ax-off specialisations import it; the base does not, except the worker's).
  fleetNode =
    {
      role,
      address,
      # The coordinator's stand-in tailnet; the worker has none, as on the fleet.
      guardInterfaces ? [ "eth2" ],
    }:
    {
      imports = [
        ../../modules/ax-fleet
        # As on the real hosts (hosts/{coordinator,worker,client}): the harness
        # role turns myAxClient on by mkDefault, which puts `ax` and `kubectl`
        # on the coordinator's PATH for the Task phases.
        ../../modules/ax-client.nix
        inputs.agenix.nixosModules.default
      ];
      myAxFleet = {
        inherit role;
        lan = lanAddr address;
        k3sTokenFile = "${token}";
        k3sAgentTokenFile = "${agentToken}";
        inherit guardInterfaces;
      };
    };

  # The test tools, in the base: identical in every state.
  testBase = {
    system.switch.enable = true;
    environment.systemPackages = [
      pkgs.jq
      pkgs.curl
      pkgs.iptables
      pkgs.nftables
      pkgs.iproute2
      pkgs.dnsutils
    ];
  };

  # fleet: the host's fleet module (fleetNode plus host-specific settings).
  # extra: ax-on only (test images, reservations).
  axStates = fleet: extra: {
    specialisation.ax-on.configuration = {
      imports = [
        fleet
        extra
      ];
      myAxFleet.enable = true;
      services.k3s.images = [ probeImage ];
    };
    specialisation.ax-off.configuration = {
      imports = [ fleet ];
    };
  };

  nasFleet = fleetNode {
    role = "control";
    address = "10.42.0.1";
  };

  coordinatorFleet = {
    imports = [
      (fleetNode {
        role = "harness";
        address = "10.42.0.2";
      })
    ];
    # The desk's wired port (fix round 3): eth3, NetworkManager-managed,
    # DHCP from the worker's second leg, as enp191s0's "Wired connection 1".
    myAxFleet.lan.extraInterfaces = [ "eth3" ];
  };

  # The NAS as it is today, before ax (shared with ax-fleet-boot, which adds
  # nasFleet in its base and boots it).
  nasBase =
    { ... }:
    {
      imports = [
        testBase
        (setAddr "eth1" "10.42.0.1" 24)
      ];
      networking.hostName = "nas";
      # The internet stand-in (fix round 4): TEST-NET-2 lives on the worker.
      networking.interfaces.eth1.ipv4.routes = [
        {
          address = "198.51.100.0";
          prefixLength = 24;
          via = "10.42.0.5";
        }
      ];
      virtualisation = {
        vlans = [ 1 ];
        memorySize = 10240;
        cores = 6;
        diskSize = 8192;
        emptyDiskImages = [
          8192
          16384
        ];
        fileSystems = {
          "/mnt/fast" = {
            device = "/dev/vdb";
            fsType = "ext4";
            autoFormat = true;
          };
          "/mnt/nas" = {
            device = "/dev/vdc";
            fsType = "btrfs";
            autoFormat = true;
          };
        };
      };
      boot.supportedFilesystems = [ "btrfs" ];
      # The house router, as hosts/nas/router.nix declares it (fix round 2):
      # the snapshot and the teardown must keep it.
      boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

      # The NAS firewall as the real one is shaped: nftables, interface-scoped
      # extraInputRules, filterForward off, strict rpfilter, and a reload that
      # keeps other tables (flushRuleset = false).
      networking.nftables.enable = true;
      networking.nftables.flushRuleset = false;
      networking.firewall = {
        enable = true;
        filterForward = false;
        checkReversePath = "strict";
        extraInputRules = ''
          iifname "eth1" udp dport 53 accept comment "stand-in AdGuard"
          iifname "eth1" tcp dport 53 accept comment "stand-in AdGuard"
        '';
      };

      # AdGuard stand-in: answers one record nobody else serves.
      services.dnsmasq = {
        enable = true;
        resolveLocalQueries = false;
        settings = {
          listen-address = [ "10.42.0.1" ];
          bind-interfaces = true;
          no-resolv = true;
          address = [ "/only-nas.test/10.42.0.77" ];
        };
      };

      # A recording `tailscale` on the system PATH, as the real NAS has one:
      # k3s-killall.sh's remove_interfaces runs `tailscale set
      # --advertise-routes=` whenever the binary is reachable, which would
      # withdraw the house subnet route. 90-rollback asserts the teardown
      # never calls it.
      environment.systemPackages = [
        kubectlAte
        (pkgs.writeShellScriptBin "tailscale" ''
          echo "$*" >> /var/log/tailscale-stub.log
        '')
      ];

      # The bystander: the NAS's shared PostgreSQL (Paperless, Immich) must
      # not restart and must not change.
      services.postgresql = {
        enable = true;
        ensureDatabases = [ "paperless" ];
      };
    };

  vmReservations = {
    systemReserved = "cpu=500m,memory=512Mi";
    kubeReserved = "cpu=250m,memory=256Mi";
    # The full signal set, as harness.nix renders it (fix round 4): a set flag
    # replaces every kubelet default.
    evictionHard = "memory.available<256Mi,nodefs.available<10%,nodefs.inodesFree<5%,imagefs.available<15%,imagefs.inodesFree<5%";
  };
in
{
  inherit
    probeImage
    token
    agentToken
    claudeProbeImage
    kubectlAte
    nasBase
    nasFleet
    ;

  nas =
    { ... }:
    {
      imports = [
        nasBase
        (axStates nasFleet {
          myAxFleet.kubelet = {
            systemReserved = "cpu=1,memory=1Gi";
          };
          myAxFleet.registrySeed.ax-agent-claude-probe = {
            oci = claudeProbeImage;
            repo = "ax/ax-agent-claude-probe";
            inherit (claudeProbeImage.passthru) tag;
          };
        })
      ];
    };

  coordinator =
    { ... }:
    {
      imports = [
        testBase
        (axStates coordinatorFleet { myAxFleet.kubelet = vmReservations; })
        (setAddr "eth1" "10.42.0.2" 24)
        (setAddr "eth2" "100.105.121.73" 10)
      ];
      networking.hostName = "coordinator";
      # myAxFleet.apiUsers defaults to [ "tom" ]; alice is the other local user.
      users.users.tom.isNormalUser = true;
      virtualisation = {
        vlans = [
          1
          2
          3
        ];
        memorySize = 8192;
        cores = 4;
        diskSize = 8192;
        podman.enable = true;
      };
      # The desk's shape: iptables firewall, strict rpfilter, NetworkManager
      # running (its InvocationID must not change at switch), zram swap.
      networking.nftables.enable = false;
      networking.firewall = {
        enable = true;
        checkReversePath = "strict";
        allowedTCPPorts = [ 80 ];
      };
      networking.networkmanager.enable = true;
      # eth1/eth2 are the test driver's static addresses; identical in base
      # and specialisation, so NetworkManager.conf does not change at switch.
      networking.networkmanager.unmanaged = [
        "eth1"
        "eth2"
      ];
      zramSwap.enable = true;
      # The desk's kernel, where runsc runs (fix round 2: the VM had run the
      # pin's default kernel). The same expression as modules/strix.nix, so
      # the same derivation; ax-fleet-topology asserts it.
      boot.kernelPackages =
        (import inputs.nixpkgs-fresh {
          system = "x86_64-linux";
          config.allowUnfree = true;
        }).linuxPackages_7_2;
      # The desk's sshd as modules/common.nix renders it: port 22 open on every
      # interface, passwords accepted (fix round 2). Pods must not reach it.
      services.openssh = {
        enable = true;
        openFirewall = true;
        settings.PasswordAuthentication = true;
        settings.KbdInteractiveAuthentication = true;
      };

      services.caddy = {
        enable = true;
        virtualHosts.":80".extraConfig = ''
          respond "caddy-ok"
        '';
      };

      # herdr stand-in: a lingering user's long-lived user unit with the same
      # X-SwitchMethod herdr has. Its MainPID must survive switch and rollback.
      users.users.alice = {
        isNormalUser = true;
        linger = true;
      };
      systemd.user.services.herdr-standin = {
        wantedBy = [ "default.target" ];
        unitConfig."X-SwitchMethod" = "keep-old";
        serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep 1000000";
      };
    };

  worker =
    { ... }:
    {
      imports = [
        testBase
        (fleetNode {
          role = "inference";
          address = "10.42.0.5";
          guardInterfaces = [ ];
        })
        # 198.51.100.5 (TEST-NET-2): a public address for the egress tests
        # (fix round 4), routed to the worker by the NAS.
        {
          networking.interfaces.eth1.ipv4.addresses = lib.mkForce [
            {
              address = "10.42.0.5";
              prefixLength = 24;
            }
            {
              address = "198.51.100.5";
              prefixLength = 32;
            }
          ];
        }
        (setAddr "eth2" "192.168.43.5" 24)
      ];
      networking.hostName = "worker";
      virtualisation = {
        vlans = [
          1
          3
        ];
        # A k3s agent from 38-worker-join on: containerd, the airgap images,
        # the kubelet's reservations (vmReservations) and a probe pod.
        memorySize = 4096;
        cores = 2;
        diskSize = 8192;
      };
      # myAxFleet.apiUsers defaults to [ "tom" ], as on the real worker.
      users.users.tom.isNormalUser = true;
      # sshd on port 22, open on every interface as on the real worker
      # (hosts/worker/default.nix), passwords on as in the coordinator
      # stand-in: the worst case. Pods on the worker must not reach it
      # (38-worker-join).
      services.openssh = {
        enable = true;
        openFirewall = true;
        settings.PasswordAuthentication = true;
        settings.KbdInteractiveAuthentication = true;
      };
      # vlan 3: a second LAN segment for the coordinator's wired leg (fix
      # round 3). DHCP with no router option, so no default route moves.
      services.dnsmasq = {
        enable = true;
        resolveLocalQueries = false;
        settings = {
          port = 0;
          interface = [ "eth2" ];
          bind-interfaces = true;
          dhcp-range = [ "192.168.43.100,192.168.43.150,1h" ];
          dhcp-option = [ "3" ];
        };
      };
      # Another worker port (fix round 3): the real worker opens 22 with
      # passwords on every interface; pods and the egress gateway must reach
      # 8731 and nothing else.
      # The public target (fix round 4): what a Task with no Gateway must not
      # reach, while the NAS host does.
      systemd.services.public-8000 = {
        wantedBy = [ "multi-user.target" ];
        # All addresses: binding 198.51.100.5 raced its assignment (MEASURED,
        # fix-round-4 run 1: the unit exited 1 before network-addresses-eth1
        # added the address).
        serviceConfig = {
          ExecStart = "${pkgs.busybox}/bin/httpd -f -p 8000 -h ${pkgs.writeTextDir "index.html" "public-reached\n"}";
          Restart = "always";
        };
      };
      systemd.services.worker-2222 = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = "${pkgs.busybox}/bin/httpd -f -p 2222 -h ${pkgs.writeTextDir "index.html" "worker-port-2222-reached\n"}";
      };
      # The base is the kill switch: the role declared, `enable` left at its
      # default (false; ax-on inherits the base, so the base must not define
      # it). The guards render, k3s does not. 38-worker-join switches to
      # ax-on, as Tom will, after the NAS and the coordinator.
      specialisation.ax-on.configuration = {
        myAxFleet.enable = true;
        myAxFleet.kubelet = vmReservations;
        services.k3s.images = [ probeImage ];
      };
      networking.firewall = {
        enable = true;
        interfaces.eth1.allowedTCPPorts = [
          8731
          2222
          8000
        ];
        interfaces.eth2.allowedTCPPorts = [ 8731 ];
        interfaces.eth2.allowedUDPPorts = [ 67 ];
      };
      systemd.services.halogen-stub = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.python3}/bin/python3 ${./halogen_stub.py} --port 8731 --log /var/lib/halogen-stub/requests.jsonl";
          StateDirectory = "halogen-stub";
        };
      };
    };

  peer =
    { ... }:
    {
      imports = [ (setAddr "eth1" "100.64.0.9" 10) ];
      networking.hostName = "peer";
      virtualisation.vlans = [ 2 ];
      networking.firewall.enable = false;
      environment.systemPackages = [ pkgs.curl ];
      # Something to reach: the guard must stop pods from getting here.
      systemd.services.peer-http = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.ExecStart = "${pkgs.busybox}/bin/httpd -f -p 8000 -h /etc";
      };
    };
}
