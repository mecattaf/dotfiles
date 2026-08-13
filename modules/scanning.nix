{
  config,
  lib,
  pkgs,
  ...
}:

# Shared home-scanner plane (Brother ADS-1800W). common.nix imports it
# fleet-wide; headless.nix force-disables it on appliances such as `nas`.
lib.mkIf (!config.myHeadless.enable) {
  # The ADS-1800W is Wi-Fi-only (2.4 GHz) with no Ethernet port; it joined
  # Freebox-AB3ACE on 2026-08-13 as BRW5CF370D442D8.local. Its eSCL REST
  # endpoint lives on port 8080 (WBM on 80/443), and a direct-HTTP client
  # batch-scanned a 16-page ADF stack flawlessly on day one, so the paper
  # intake pipeline does not depend on SANE at all. SANE is still declared
  # for ad-hoc `scanimage` use and GUI apps.
  #
  # Backend order: sane-airscan (open, driverless eSCL) first. sane-backends
  # 1.4.0 carries live eSCL ADF regressions (sane-project/backends #806,
  # #814: duplex segfaults, dropped second sides), so Brother's proprietary
  # brscan5 stays declared as the pinned fallback; on this model brscan5
  # works in network mode only, never USB.
  hardware.sane = {
    enable = true;
    extraBackends = [ pkgs.sane-airscan ];
    brscan5 = {
      enable = true;
      netDevices.home = {
        model = "ADS-1800W";
        # mDNS nodename survives DHCP lease changes (was 192.168.1.36).
        nodename = "BRW5CF370D442D8";
      };
    };
  };

  # hardware.sane already creates the `scanner` group; membership merges
  # with the base list in common.nix.
  users.users.tom.extraGroups = [
    "scanner"
    "lp"
  ];

  # The ADS-1800W's embedded scan-to-SFTP client negotiates only legacy
  # ssh-rsa (SHA-1) signatures, both when verifying our RSA host key and
  # when signing with its own RSA client key. OpenSSH disables SHA-1
  # signatures by default, so every push died in KEX with "no matching
  # host key type found. Their offer: ssh-rsa" (coordinator journal,
  # 2026-08-13). Re-admit the signature scheme over the existing RSA keys.
  # HostKeyAlgorithms is negotiated before authentication, so neither knob
  # can live in a Match block; modern clients still prefer
  # ed25519/rsa-sha2 and are unaffected, and the scanner's key remains
  # `restrict`-prefixed in tom's authorized_keys.
  services.openssh.settings.HostKeyAlgorithms = "+ssh-rsa";
  services.openssh.settings.PubkeyAcceptedAlgorithms = "+ssh-rsa";
}
