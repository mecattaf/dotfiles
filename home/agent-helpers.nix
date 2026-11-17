{
  inputs,
  lib,
  pkgs,
  osConfig,
  ...
}:
{
  # The wrappers themselves are filtered in home.nix's binDir (#552).
  # Own the formerly hand-made Node/Projects GC roots. Mail/CRM bundles and
  # utility auth remain mutable home data included in the cutover copy.
  # The crm and mail wrappers now run the Communications CLIs
  # (./communications.nix); the two node roots stay only so the old bundles
  # can still be run by hand until those checkouts are retired.
  home.file = lib.mkIf (osConfig.myFleet.has "brain") {
    ".local/state/agency/mail/node".source = pkgs.nodejs_24;
    ".local/state/agency/crm/node".source = pkgs.nodejs_24;
    ".local/state/agency/project/cli".source =
      inputs.project-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };
}
