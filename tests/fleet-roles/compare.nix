# Evaluation only: nix eval --impure --json --file tests/fleet-roles/compare.nix
# --argstr base 'git+file:///path/to/repo?rev=<base-sha>'
# --argstr candidate '/path/to/worktree' --option allow-import-from-derivation false
{ base, candidate }:
let
  baseFlake = builtins.getFlake base;
  candidateFlake = builtins.getFlake candidate;
  pinned =
    flake: host:
    (flake.nixosConfigurations.${host}.extendModules {
      specialArgs.inputs = flake.inputs // {
        self = flake // {
          rev = "fleet-roles-comparison";
          lastModified = 0;
        };
      };
    }).config.system.build.toplevel.drvPath;
in
builtins.listToAttrs (
  map
    (
      host:
      let
        a = pinned baseFlake host;
        b = pinned candidateFlake host;
      in
      {
        name = host;
        value = {
          base = a;
          candidate = b;
          equal = a == b;
        };
      }
    )
    [
      "strix"
      "nas"
      "client"
    ]
)
