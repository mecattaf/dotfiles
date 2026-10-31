{ config, lib, ... }:
{
  # Public certificate only. The private CA stays in Caddy's state on the NAS.
  security.pki.certificateFiles = lib.mkIf (builtins.elem config.networking.hostName [
    "client"
    "strix"
  ]) [ ../certs/browser-root.crt ];
}
