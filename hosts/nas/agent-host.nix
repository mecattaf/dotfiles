{ lib, unstablePkgs, ... }:
{
  imports = [
    ../../modules/herdr-web-ui.nix
    ../../modules/atuin.nix
  ];

  services.herdr-web-ui.enable = true;

  # Preserve both Atuin database schemas across the home/server migration.
  # Stable is 18.15.2; the existing strix server and client are 18.17.0.
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
