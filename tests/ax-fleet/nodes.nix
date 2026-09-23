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
# Each base config is "today", with ax OFF. `specialisation.ax-on` sets
# myAxFleet.enable = true, and the test script switches to it live, NAS first,
# exactly as Tom will.
let
  # A plain file, test-only, not a secret: the fleet reads agenix instead.
  token = pkgs.writeText "ax-fleet-vm-token" "ax-fleet-vm-test-token-0123456789abcdef";

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

  lanAddr = address: {
    interface = "eth1";
    inherit address;
  };

  setAddr = iface: address: prefixLength: {
    networking.interfaces.${iface}.ipv4.addresses = lib.mkForce [ { inherit address prefixLength; } ];
  };

  # Everything that makes a node a fleet node in the test.
  fleetNode =
    { role, address }:
    {
      imports = [
        ../../modules/ax-fleet
        inputs.agenix.nixosModules.default
      ];
      system.switch.enable = true;
      myAxFleet = {
        inherit role;
        lan = lanAddr address;
        k3sTokenFile = "${token}";
        guardInterfaces = [ "eth2" ];
      };
      environment.systemPackages = [
        pkgs.jq
        pkgs.curl
        pkgs.iptables
        pkgs.nftables
        pkgs.iproute2
        pkgs.dnsutils
      ];
    };

  axOn = extra: {
    specialisation.ax-on.configuration = lib.mkMerge [
      {
        myAxFleet.enable = true;
        services.k3s.images = [ probeImage ];
      }
      extra
    ];
  };

  vmReservations = {
    systemReserved = "cpu=500m,memory=512Mi";
    kubeReserved = "cpu=250m,memory=256Mi";
    evictionHard = "memory.available<256Mi";
  };
in
{
  inherit probeImage token;

  nas =
    { ... }:
    {
      imports = [
        (fleetNode {
          role = "control";
          address = "10.42.0.1";
        })
        (axOn {
          myAxFleet.kubelet = {
            systemReserved = "cpu=1,memory=1Gi";
          };
        })
        (setAddr "eth1" "10.42.0.1" 24)
      ];
      networking.hostName = "nas";
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

      # The bystander: the NAS's shared PostgreSQL (Paperless, Immich) must
      # not restart and must not change.
      services.postgresql = {
        enable = true;
        ensureDatabases = [ "paperless" ];
      };
    };

  coordinator =
    { ... }:
    {
      imports = [
        (fleetNode {
          role = "harness";
          address = "10.42.0.2";
        })
        (axOn { myAxFleet.kubelet = vmReservations; })
        (setAddr "eth1" "10.42.0.2" 24)
        (setAddr "eth2" "100.105.121.73" 10)
      ];
      networking.hostName = "coordinator";
      virtualisation = {
        vlans = [
          1
          2
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
        (fleetNode {
          role = "inference";
          address = "10.42.0.5";
        })
        (setAddr "eth1" "10.42.0.5" 24)
      ];
      networking.hostName = "worker";
      virtualisation.vlans = [ 1 ];
      # The worker is not switched in the motion; its fleet role is ON from
      # boot and renders only the 8731 assertion, as on the real host.
      myAxFleet.enable = true;
      networking.firewall = {
        enable = true;
        interfaces.eth1.allowedTCPPorts = [ 8731 ];
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
