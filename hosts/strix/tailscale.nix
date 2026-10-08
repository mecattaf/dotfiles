{ ... }:
let
  preferences = [
    "--hostname=strix"
    "--accept-routes=false"
    "--accept-dns=false"
    "--ssh=false"
  ];
in
{
  # Tom's final closet decision: retain the already enrolled SaaS identity as
  # a direct fallback when NAS is down. Ordinary access still uses the LAN or
  # NAS subnet route. Reuse persistent state; no enrollment key is deployed.
  # OpenSSH uses the same fleet key on both paths, without a second SSH policy.
  services.tailscale = {
    enable = true;
    openFirewall = true;
    extraUpFlags = preferences;
    extraSetFlags = preferences;
  };
}
