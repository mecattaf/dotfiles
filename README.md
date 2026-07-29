# dotfiles

One flake for the whole distribution. NixOS + Home Manager configure every
personal machine from one reviewed source of truth.

## Hosts

The flake exports exactly two NixOS host configurations:

| Host | Hardware | Role |
|---|---|---|
| `coordinator` | Framework Desktop, AMD Strix Halo | controller node, daily driver |
| `zenbook-duo` | ASUS Zenbook Duo, Intel | thin-client laptop |

```
flake.nix        two NixOS hosts wired through one mkHost
modules/         common.nix (every host) + strix.nix (AMD Strix Halo coordinator)
hosts/           one module per machine
home/            home-manager: typed nix (home.nix, nvim.nix) + RAW out-of-store
                 configs (niri KDL, kitty, fish, nvim lua) linked via mkOutOfStoreSymlink
overlays/ pkgs/  custom packages (mactahoe themes, backlog-md, …)
docs/local-ai/  current local-AI appliance docs, model roster, monthly tallies
docs/old/       reference-only documentation retained for later mining
```

## Branches

- **`main`** — canonical and NixOS-only.
- **`archive/*`** — read-only historical lineage; never used for deployment.

## Usage

```sh
# on a NixOS host
sudo nixos-rebuild switch --flake .#<host>
```
