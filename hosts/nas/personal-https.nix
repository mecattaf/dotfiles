{ config, lib, ... }:
let
  cfg = config.myNas.tailscalePersonal;
in
{
  # The network module owns private listeners; this reuses the NAS's existing
  # ACME/DNS-01 pattern. No certificate request or secret delivery until enabled.
  config = lib.mkIf (cfg.enable && cfg.media.https.enable) {
    assertions = [
      {
        assertion = config.mySecrets.enable;
        message = "Private NAS HTTPS requires agenix secret delivery.";
      }
    ];
    age.secrets.nas-cloudflare-dns = {
      file = ../../secrets/nas-cloudflare-dns.age;
      mode = "0400";
    };
    myNas.tailscalePersonal.media.https.acmeHost = cfg.media.https.musicHostname;
    security.acme = {
      acceptTerms = true;
      defaults.email = "thomas@mecattaf.dev";
      certs.${cfg.media.https.musicHostname} = {
        extraDomainNames = [ cfg.media.https.plexHostname ];
        dnsProvider = "cloudflare";
        environmentFile = config.age.secrets.nas-cloudflare-dns.path;
        dnsResolver = "1.1.1.1:53";
        group = "caddy";
        reloadServices = [ "caddy" ];
      };
    };
  };
}
