{ lib, unstablePkgs, ... }:
{
  imports = [
    ../../modules/agent-offload.nix
    ../../modules/substrate.nix
    ../../modules/herdr-web-ui.nix
    ../../modules/atuin.nix
  ];

  services.substrate = {
    floorUrl = "https://substrate.mecattaf.dev";
    pusher = {
      enable = true;
      owners.codex = "tom";
    };
    puller = {
      enable = true;
      maxRuns = 1;
      cap = 1;
      defaultModel = "qwen3.8-flash-next";
      # Keep the historical queues intact while commissioning only this work.
      sessionScope = [ { project = "dotfiles"; thread = "T-69"; } ];
      maintenance = [ {
        project = "dotfiles";
        thread = "T-69";
        command = [ "/run/current-system/sw/bin/fleet-update-start" "--json" ];
        status_command = [ "/run/current-system/sw/bin/fleet-update" "--status" "--json" ];
      } ];
      claudeSeat = "cc";
      claudeConfigDir = "/home/tom/.claude";
    };
  };

  services.herdr-web-ui = {
    enable = true;
    revision = "e85ffd1ff0402e3aee9c2df6ec47e7cafefe7d60"; # build/claude-morning
    sourceHash = "sha256-F/HeC2E4eIR4EOCMIpTbWTZWbD4DMBM5Biqrl4Vb2TQ=";
    depsHash = "sha256-2UG94F4KbSDNAMe18joBs9ehCs40ZRvLhMZrQ4cHZyw=";
  };

  # Preserve both Atuin database schemas across the home/server migration.
  # Stable is 18.15.2; the existing strix server and client are 18.17.0.
  # The home package pin stays for the version-match test; the NAS home itself
  # leaves programs.atuin disabled (home/home.nix, T-55).
  services.atuin.package = unstablePkgs.atuin;
  home-manager.users.tom.programs.atuin.package = unstablePkgs.atuin;

  # The router must stay reachable when an agent exhausts memory. Reserve
  # memory through the parent slice as well as at each essential service.
  systemd.slices.system.sliceConfig.MemoryMin = "512M";
  # NixOS uses Accept=yes SSH here, so protect the actual per-connection
  # template and its implicit parent slice, rather than an unused sshd unit.
  systemd.slices.system-sshd.sliceConfig.MemoryMin = "64M";
  systemd.services =
    lib.genAttrs [ "dnsmasq" "adguardhome" "tailscaled" "sshd@" ] (name: {
      serviceConfig = {
        OOMScoreAdjust = -900;
        MemoryAccounting = true;
        MemoryMin =
          if name == "adguardhome" then
            "128M"
          else if name == "sshd@" then
            "32M"
          else
            "64M";
      };
    })
    // {
      # A user-owned ManagedOOMPreference can be ignored by the system oomd
      # when it selects descendants of a root-owned ancestor. Protect the
      # root-owned manager too; kernel OOM still selects individual processes.
      "user@" = {
        overrideStrategy = "asDropin";
        serviceConfig.ManagedOOMPreference = "omit";
      };
    };
}
