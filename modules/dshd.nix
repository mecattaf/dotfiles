{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.dshd.nixosModules.default ];

  config = lib.mkIf (config.myFleet.has "brain") {
    dshd.enable = true;
    # Upstream reserves "default" for the link to the only declared release.
    dshd.releases.nas = {
      dsh = pkgs.llm-agents.dsh;
      # The NAS login shell exports this token; instance recipes must not save it.
      unsetEnvironment = [ "CLOUDFLARE_API_TOKEN" ];
    };
  };
}
