# dotfiles

One flake for the whole distribution. NixOS + home-manager for every personal
machine, superseding the previous four-repo stack — harness (bootc Fedora
image), harnessRPM (COPR packages), chezmoi-templated dotfiles, and zirconium.

## Hosts

| Host | Hardware | Role |
|---|---|---|
| `coordinator` | Framework Desktop, AMD Strix Halo | controller node, daily driver |
| `worker` | Framework Desktop, AMD Strix Halo | headless LLM runner (TB4-linked to coordinator) |
| `dell-xps` | Dell XPS 13 (2022), Intel | thin-client laptop |
| `zenbook-duo` | ASUS Zenbook Duo, Intel | thin-client laptop (first flash — runbook: [docs/zenbook-duo-flash.md](docs/zenbook-duo-flash.md)) |

```
flake.nix        four hosts wired through one mkHost; tom@bridge = home-manager-only
                 bridge for a live Fedora host (Phase 0)
modules/         common.nix (every host) + strix.nix (AMD Strix Halo pair)
hosts/           one module per machine
home/            home-manager: typed nix (home.nix, nvim.nix) + RAW out-of-store
                 configs (niri KDL, kitty, fish, nvim lua) linked via mkOutOfStoreSymlink
overlays/ pkgs/  custom packages (mactahoe themes, backlog-md, …)
docs/migration-journal/   the working log: ratified decisions (nix-decisions.md is
                 the system of record), per-area sweeps, flash runbooks
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
