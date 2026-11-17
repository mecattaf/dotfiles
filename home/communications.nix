{
  config,
  inputs,
  lib,
  osConfig,
  ...
}:
# Communications: the user service that runs `cordis` from the module's
# generated cordis.yml (crm and mail over one SQLite), on the brain host only.
# The module's defaults name no host. The host-local values (Worker URL, owner
# id, tailnet name, tokens, own addresses) live in the 0600 files under the
# module's configDir, outside this repository, and the service merges its host
# config over these settings at boot. Only the blob root is set here: it is
# the HDD subvolume hosts/nas/storage.nix declares. blobMount makes the service
# refuse to start, and refuse every blob write, when the nofail HDD is not
# mounted, so no blob lands on the root disk and is acked away.
let
  cfg = config.services.communications;
in
{
  imports = [ inputs.communications.homeManagerModules.default ];

  config = lib.mkIf (osConfig.myFleet.has "brain") {
    services.communications = {
      enable = true;
      blobRoot = "/mnt/nas/communications";
      blobMount = "/mnt/nas";
    };

    # The crm and mail wrappers (dot_local/bin) exec the CLIs through this GC
    # root, like project; home.nix's binDir keeps them off non-brain hosts.
    home.file.".local/state/agency/communications/cli".source = cfg.package;
  };
}
