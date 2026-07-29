# dotfiles

One flake for the whole distribution. NixOS + home-manager for every personal
machine, superseding the previous four-repo stack — harness (bootc Fedora
image), harnessRPM (COPR packages), chezmoi-templated dotfiles, and zirconium.

## Hosts

The flake exports exactly three NixOS host configurations:

| Host | Hardware | Role |
|---|---|---|
| `coordinator` | Framework Desktop, AMD Strix Halo | controller node, daily driver |
| `worker` | Framework Desktop, AMD Strix Halo | soft-retired tailnet worker; optional LLM and microVM capacity |
| `zenbook-duo` | ASUS Zenbook Duo, Intel | thin-client laptop (historical first-flash runbook: [docs/old/zenbook-duo-flash.md](docs/old/zenbook-duo-flash.md)) |

The two Framework desktops have a direct TB5 link; active fleet routing uses
their tailnet hostnames. `tom@bridge` is a separate standalone Home Manager
output for a live Fedora host, not a fourth NixOS host.

```
flake.nix        three NixOS hosts wired through one mkHost; tom@bridge is a
                 separate standalone Home Manager output for live Fedora
modules/         common.nix (every host) + strix.nix (AMD Strix Halo pair)
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
