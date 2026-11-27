{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myPs4;
in
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    ./hardware.nix
  ];

  options.myPs4 = {
    kernelVariant = lib.mkOption {
      type = lib.types.enum [
        "baikal"
        "universal"
      ];
      default = "baikal";
      description = "Explicit source-pinned southbridge kernel candidate; selected during the attended hardware audit.";
    };
    gpuBackingLimitMiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 7424;
      description = ''
        Requested TTM GPU-backing limit in MiB. The external PS4 loader's
        bootargs must set ttm.pages_limit to MiB * 256 (4 KiB pages) before
        amdgpu initializes. This is
        a capacity ceiling, not proof of allocation, bandwidth or Bonsai fit.
      '';
    };
    fleetSuite = {
      enable = lib.mkEnableOption "the optional PS4 Kitty/Domicile fleet applications";
      includeSpecialisation = lib.mkEnableOption "an additional fleet-suite generation in the USB closure";
    };
  };

  config = lib.mkMerge [
    {
      networking.hostName = "ps4-dummy";
      myFleet.roles = [ "compute" ];
      myHeadless.enable = true;
      mySecrets.enable = false;
      myFleetTransport.enable = true;

      # Jaguar supports AVX but not AVX2. Keep generic x86-64 packages; neither
      # the Strix host profile nor its -march=native/ROCm packages belong here.
      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

      users.users.tom.uid = 1000;
      # No private operator SSH key, harness token, history or canonical home
      # is provisioned. Public login keys come from modules/mesh.nix.
      services.openssh.settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "prohibit-password";
      };
      services.openssh.startWhenNeeded = lib.mkForce false;
      # DHCP is deliberately independent of a guessed southbridge, NIC MAC or
      # persistent interface name. The router's lease table gives the address.
      networking.networkmanager.ensureProfiles.profiles.ps4-wired = {
        connection = {
          id = "ps4-dummy-wired";
          type = "ethernet";
          autoconnect = true;
          autoconnect-priority = 100;
        };
        ethernet.cloned-mac-address = "preserve";
        ipv4 = {
          method = "auto";
          route-metric = 100;
        };
        ipv6.method = "auto";
      };
      networking.nftables.enable = true;
      networking.firewall = {
        # First-boot SSH on the home LAN, then the box's own tailnet identity.
        # No inference listener is opened before a real runtime is qualified.
        allowedTCPPorts = lib.mkForce [ ];
        interfaces.tailscale0.allowedTCPPorts = [ 22 ];
        extraInputRules = ''
          ip saddr 10.42.0.0/24 tcp dport 22 accept comment "PS4 attended LAN bootstrap"
        '';
      };
      # psX disables unqualified suspend/hibernate and display power/profile
      # operations. Keep a permanent inference node awake by policy.
      systemd.sleep.settings.Sleep = {
        AllowSuspend = false;
        AllowHibernation = false;
        AllowHybridSleep = false;
        AllowSuspendThenHibernate = false;
      };
      services.avahi.enable = lib.mkForce false;
      networking.networkmanager.unmanaged = [ "type:wifi" ];
      services.tailscale.authKeyFile = null;
      # Pinned Tailscale 1.98.8 otherwise defaults to iptables even while the
      # host firewall uses nftables. Select its supported native nft backend.
      systemd.services.tailscaled.environment.TS_DEBUG_FIREWALL_MODE = "nftables";

      # Build and deploy from the NAS/Strix fleet path. No PS4 local build
      # fallback and no copied builder private key.
      nix.settings.max-jobs = lib.mkForce 0;
      nix.distributedBuilds = false;
      nix.buildMachines = [ ];

      # Memory qualification must measure physical pages. A swap capacity is
      # not GPU memory, and a framebuffer/desktop must not quietly take it.
      zramSwap.enable = lib.mkForce false;
      swapDevices = [ ];
      services.journald.extraConfig = ''
        Storage=persistent
        SystemMaxUse=256M
        RuntimeMaxUse=16M
      '';
      systemd.services."serial-getty@ttyS0".enable = false;

      # Use the same source-pinned fleet packages with a focused home profile,
      # without home/home.nix's NAS/seat services or a checkout on the PS4.
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = { inherit inputs; };
        backupFileExtension = "hm-bak";
        users.tom = import ../../home/ps4-dummy.nix;
      };

      environment.systemPackages = with pkgs; [
        curl
        htop
        jq
        libdrm
        (pkgs.callPackage ../../pkgs/ps4-host-check { })
        (pkgs.callPackage ../../pkgs/ps4-memory-probe { })
      ];
      environment.etc."ps4/appliance.json".text = builtins.toJSON {
        host = "ps4-dummy";
        lineage = "linux-psx";
        inherit (cfg) kernelVariant;
        rootLabel = "ps4-nixos";
        bootLabel = "PS4BOOT";
        gpuCompilerTarget = "bonaire/gfx704";
        kernelRelease = config.system.build.ps4BootFiles.kernel.kernelRelease;
        inherit (cfg) gpuBackingLimitMiB;
        inferenceQualified = false;
        modelPolicy = {
          discovery = "plugins";
          weightsInNixStore = false;
          extraQuantization = false;
          minimumContextTokens = 16384;
        };
      };

      assertions = [
        {
          assertion = !(config.myFleet.has "brain") && !(config.myFleet.has "seat");
          message = "ps4-dummy remains a headless compute host; installing the optional suite does not assign NAS or physical-seat roles.";
        }
        {
          assertion = !config.boot.loader.systemd-boot.enable && !config.boot.loader.grub.enable;
          message = "PS4 boot uses the external psX loader and /sbin/init bridge, never PC UEFI/GRUB.";
        }
        {
          assertion = config.networking.firewall.enable && config.networking.nftables.enable;
          message = "The PS4 production kernel must support the fleet firewall; do not solve a missing netfilter kernel by disabling the firewall.";
        }
        {
          assertion = config.hardware.graphics.enable;
          message = "Keep the PS4 render-node/GPU userspace path available for the custom inference runtime.";
        }
      ];
    }
    (lib.mkIf cfg.fleetSuite.enable {
      # Headless normally disables user linger on compute. Persistent local
      # stations are explicit in this optional suite, while hc itself remains
      # hand-started from the clean user-manager environment.
      users.users.tom.linger = lib.mkOverride 40 true;
      # Reuse upstream's CPU-only loader compatibility check without enabling
      # its desktop services. This tests the PS4 driver with Domicile's own
      # glibc before an optional suite image is accepted.
      system.checks = [
        (pkgs.runCommand "ps4-domicile-loads-graphics-driver" { } ''
          ${
            inputs.domicile.packages.${pkgs.stdenv.hostPlatform.system}.domicile
          }/libexec/domicile/graphics-probe \
            ${config.hardware.graphics.package}/lib/libEGL_mesa.so.0 \
            ${config.hardware.graphics.package}/lib/gbm/dri_gbm.so
          touch "$out"
        '')
      ];
    })
    (lib.mkIf cfg.fleetSuite.includeSpecialisation {
      specialisation.fleet-suite.configuration.myPs4.fleetSuite = {
        enable = true;
        includeSpecialisation = lib.mkForce false;
      };
    })
  ];
}
