# dotfiles

One flake for the whole distribution. NixOS + home-manager for every personal
machine, superseding the previous four-repo stack — harness (bootc Fedora
image), harnessRPM (COPR packages), chezmoi-templated dotfiles, and zirconium.

## Hosts

The flake exports exactly two NixOS host configurations:

| Host | Hardware | Role |
|---|---|---|
| `coordinator` | Framework Desktop, AMD Strix Halo | controller node, daily driver |
| `zenbook-duo` | ASUS Zenbook Duo, Intel | thin-client laptop (historical first-flash runbook: [docs/old/zenbook-duo-flash.md](docs/old/zenbook-duo-flash.md)) |
| `tom@bridge` | standalone Home Manager profile | transition profile for a live Fedora host |

`tom@bridge` is a separate standalone Home Manager output for a live Fedora
host, not a third NixOS host.

```
flake.nix        two NixOS hosts wired through one mkHost; tom@bridge =
                 home-manager-only bridge for a live Fedora host (Phase 0)
modules/         common.nix (every host) + strix.nix (AMD Strix Halo coordinator)
hosts/           one module per machine
home/            home-manager: typed nix (home.nix, nvim.nix) + RAW out-of-store
                 configs (niri KDL, kitty, fish, nvim lua) linked via mkOutOfStoreSymlink
overlays/ pkgs/  custom packages (mactahoe themes, backlog-md, …)
docs/local-ai/  current local-AI appliance docs, model roster, monthly tallies
docs/old/       reference-only documentation retained for later mining
```

## Branches

- **`main`** — canonical (this branch, the default; named `nix` until the
  2026-07-05 consolidation).
- **`archive/*`** — everything else, read-only: `archive/chezmoi/main` is the
  retired Fedora-era world (bootc + COPR + chezmoi templating, the pre-Nix
  `main`); the rest are the old per-device image repos and stray PR branches.

## Usage

```sh
# on a NixOS host
sudo nixos-rebuild switch --flake .#<host>

# Phase-0 bridge on a live Fedora host
nix run home-manager -- switch --flake .#tom@bridge
```
