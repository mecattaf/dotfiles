{
  lib,
  ...
}:
# Strix: permanent headless compute host, wired through BE550 to Freebox.
# Private DNS and storage use NAS; public routing is independent of NAS.
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ./uplink-nas.nix

    ./nas-client.nix # /mnt/nas NFS view and the NAS reachability tripwire
    ./atuin.nix # retained import; its brain role gate now disables the server
    ../client/audio.nix
    ../../modules/strix-compute.nix
    ../../modules/keyring-autounlock.nix
  ];

  networking.hostName = "strix-coordinator";
  myFleet.roles = [
    "compute"
  ];
  hardware.bluetooth.enable = lib.mkForce false;

  # No dotfiles checkout on the strix: raw dotfiles come from the Nix store.
  home-manager.users.tom.rawDotfiles.inStore = true;

  # No physical seat (headless in the closet); the Zenbook is the seat.
  # Agent services stay independent of any compositor.
  myDisplay.enable = false;
  myStrixCompute.immichMl.enable = true;

  # The NAS hosts Immich, Navidrome and every .internal front door (Caddy,
  # hosts/nas/front-door.nix). This host keeps its own enrolled Tailscale
  # identity as the independent recovery box (modules/fleet-transport.nix) and
  # the NFS client mount at the immutable /mnt/nas path.
  myNasClient.useRemoteStorage = true;

  services.utilityModel.enable = true;
  # Evaluation route for the paired memory-writer comparison: Hy keeps a role
  # only if it clearly beats well-prompted Flash-Next (Tom, 2026-11-09, #603).
  # The ARA and SuperROC routes left with their loans; bytes stay in the Library.
  services.hy-memory.enable = true;
  # The one selected D3 runtime is native vllm-srun, alongside Gufo behind
  # llama-swap. The BF16 snapshot uses the same NAS Library/explicit loan path.
  # Declaring its loan set starts no worker and moves no model bytes.
  services.d3-decision = {
    enable = true;
    wanted = true;
    demand.enable = true;
  };
  # The canceled second Strix leaves no coordinator DS4 TCP rank (#698).
  # Keep its historical model catalog; no single-host replacement is deployed.
  services.ds4.wanted = false;
  # Compute holds no operator credentials. Existing state is retired separately
  # after NAS session continuity and the sealed backup have been verified.
  mySecrets.enable = false;

}
