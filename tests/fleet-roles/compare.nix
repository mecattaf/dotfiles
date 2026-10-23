# Evaluation only: nix eval --impure --json --expr '
#   import ./tests/fleet-roles/compare.nix {
#     base = "git+file:///path/to/repo?rev=<base-sha>";
#     candidate = "/path/to/worktree";
#   }' --option allow-import-from-derivation false
{ base, candidate }:
let
  baseFlake = builtins.getFlake base;
  candidateFlake = builtins.getFlake candidate;
  pinned =
    flake: host:
    if !(builtins.hasAttr host flake.nixosConfigurations) then
      null
    else
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
  map (
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
  ) (builtins.attrNames candidateFlake.nixosConfigurations)
)
