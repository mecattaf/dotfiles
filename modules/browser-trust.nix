{ config, lib, ... }:
{
  # Public certificate only. The private CA stays in Caddy's state on coordinator.
  security.pki.certificateFiles = lib.mkIf
    (builtins.elem config.networking.hostName [ "client" "coordinator" ])
    [ ../certs/browser-root.crt ];
}
