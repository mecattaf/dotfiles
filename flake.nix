{
  description = "mecattaf — one flake for the whole distribution (NixOS + home-manager). Coordinator/worker AMD Strix Halo cluster + Intel laptops. Supersedes harness(bootc) + harnessRPM(copr) + dotfiles(chezmoi).";

  # NOTE: nix branch only. `main` stays chezmoi until this is fully validated.
  # Scoping/decisions live in ~/mecattaf/*.md (nix-decisions.md is the system of record).

  inputs = {
    # Unstable: Strix Halo (gfx1151) wants fresh kernels + Mesa. Revisit pinning later.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Per-device hardware quirks. No nixpkgs.follows — it's just module files.
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # DEFERRED inputs (add incrementally, each evaluated):
    #   niri-flake (sodiboo)      — bundled with the niri nixification (post-first-boot)
    #   sops-nix                  — secrets is its own dedicated session
    #   pi.nix (lukasl-dev)       — pi coding-agent module
    #   llm-agents.nix (numtide)  — agent binaries (claude-code, codex, …)
    #   quadlet-nix, disko, lanzaboote — later phases
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

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
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
              nixpkgs.overlays = [ self.overlays.default ];
              nixpkgs.config.allowUnfree = true;
            }
            ./modules/common.nix
            hostModule
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
        dell-xps = mkHost ./hosts/dell-xps;
        zenbook-duo = mkHost ./hosts/zenbook-duo;
      };

      # Phase-0 standalone bridge for the live Fedora host (coexists with Fedora):
      #   nix run home-manager -- switch --flake .#tom@bridge
      homeConfigurations."tom@bridge" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit inputs; };
        modules = [ ./home/home.nix ];
      };

      packages.${system} = {
        inherit (pkgs) mactahoe-gtk-theme mactahoe-icon-theme;
      };

      formatter.${system} = pkgs.nixfmt-rfc-style;

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nixfmt-rfc-style
          deadnix
          statix
          nil
          git
        ];
      };

      # Self-validating CI (lifted from nix-test, the one good idea there):
      # the RAW out-of-store dotfiles are never checked at switch, so check them here.
      checks.${system} = {
        deadnix = pkgs.runCommand "deadnix" { } ''
          ${pkgs.deadnix}/bin/deadnix --fail --no-lambda-pattern-names \
            ${./flake.nix} ${./modules} ${./hosts} ${./overlays} ${./home} > $out 2>&1 \
            || (cat $out; exit 1)
        '';
        # niri-config + shellcheck-bin checks are added once the home bridge + bin/ land.
      };
    };
}
