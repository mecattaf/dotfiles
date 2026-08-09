{
  description = "crm — personal git-backed CRM";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      forAllLinux = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      packages = forAllLinux (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        rec {
          crm = pkgs.callPackage ./nix/package.nix { };
          default = crm;
        }
      );
    };
}
