{
  description = "mecattaf — one flake for the whole distribution (NixOS + home-manager). Coordinator/worker AMD Strix Halo cluster + Intel laptops.";

  inputs = {
    # Unstable: Strix Halo (gfx1151) wants fresh kernels + Mesa.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Per-device hardware quirks. No nixpkgs.follows — it's just module files.
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Secrets — agenix (host-level; SSH host key = decryption identity).
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Declarative disk partitioning (drives nixos-anywhere). Only hosts that define
    # disko.devices are partitioned; the module is inert elsewhere.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Apple SF/NY fonts (sf-pro, sf-compact, sf-mono, ny), built at nix-build
    # time from Apple's own CDN DMGs — nothing redistributed. Replaces the old
    # Fedora-image url-fonts Apple-SF zip (its mecattaf/San-Francisco-family
    # release no longer exists; repo deleted).
    apple-fonts = {
      url = "github:Lyndeno/apple-fonts.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # zmosh — terminal session persistence with encrypted-UDP auto-reconnect.
    # THE projector primitive (jul7 ruling, tally morning-annotation §12): every
    # kitty is a persistent zmosh session on the coordinator; any laptop on the
    # tailnet reattaches it via `zmosh attach -r`, surviving IP changes / sleep-
    # wake. Supersedes shpool fleet-wide. Fork of zmx; ships its own zig2nix flake
    # + build.zig.zon2json-lock, so we consume its package directly. Its only
    # input is zig2nix (no nixpkgs to follow).
    zmosh.url = "github:mmonad/zmosh";

    # Liga SF Mono: SF Mono ligaturized AND nerd-patched upstream — a different
    # derived font from apple-fonts' sf-mono-nerd (glyphs only, no ligatures).
    # Plain repo of OTFs, not a flake; consumed by pkgs/sfmono-liga.nix.
    sfmono-liga = {
      url = "github:shaunsingh/SFMono-Nerd-Font-Ligaturized";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nixos-hardware,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      # One overlay list everywhere (top-level pkgs + every host): bespoke pkgs,
      # the apple-fonts families, and sfmono-liga — wired inline because it
      # needs the flake input as src (overlays/default.nix has no inputs).
      overlays = [
        self.overlays.default
        inputs.apple-fonts.overlays.default
        (final: _prev: {
          sfmono-liga = final.callPackage ./pkgs/sfmono-liga.nix { src = inputs.sfmono-liga; };
          # zmosh's own flake builds the `zmosh` binary (zig2nix). Its package is
          # exposed as .default; pull it straight onto the fleet-wide pkgs set.
          zmosh = inputs.zmosh.packages.${system}.default;
        })
      ];

      pkgs = import nixpkgs {
        inherit system overlays;
        config.allowUnfree = true; # google-chrome
      };

      # Single host-wiring point. Every host = common.nix + its own module + HM.
      mkHost =
        hostModule:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            {
              nixpkgs.overlays = overlays;
              nixpkgs.config.allowUnfree = true;
            }
            ./modules/common.nix
            hostModule
            inputs.agenix.nixosModules.default
            inputs.disko.nixosModules.default
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs; };
              home-manager.users.tom = import ./home/home.nix;
            }
          ];
        };
    in
    {
      overlays.default = import ./overlays;

      nixosConfigurations = {
        coordinator = mkHost ./hosts/coordinator;
        worker = mkHost ./hosts/worker;
        zenbook-duo = mkHost ./hosts/zenbook-duo;
      };

      # Standalone home-manager bridge for the live Fedora host (coexists with Fedora):
      #   nix run home-manager -- switch --flake .#tom@bridge
      homeConfigurations."tom@bridge" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit inputs; };
        modules = [ ./home/home.nix ];
      };

      packages.${system} = {
        inherit (pkgs) mactahoe-gtk-theme mactahoe-icon-theme sfmono-liga;
      };

      formatter.${system} = pkgs.nixfmt-rfc-style;

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          inputs.agenix.packages.${system}.default # `agenix -e/-r`
        ]
        ++ (with pkgs; [
          nixfmt-rfc-style
          deadnix
          statix
          nil
          git
        ]);
      };

      # The RAW out-of-store dotfiles are never checked at switch, so check them here.
      checks.${system} = {
        deadnix = pkgs.runCommand "deadnix" { } ''
          ${pkgs.deadnix}/bin/deadnix --fail --no-lambda-pattern-names \
            ${./flake.nix} ${./modules} ${./hosts} ${./overlays} ${./home} > $out 2>&1 \
            || (cat $out; exit 1)
        '';
      };
    };
}
