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
  # The one embedding route behind llama-swap, loaded on demand and swapped
  # like every other route (Tom, 2026-11-10). Coordinator only.
  services.gufo-embedding.enable = true;
  services.superroc.enable = true;
  # Hy-Memory stays served while its role is undecided (Tom, 2026-11-12, #603):
  # one demand-loaded llama-server route behind the same llama-swap.
  services.hy-memory.enable = true;
  services.gufo.models."qwen3.8-27b-ara" = {
    artifact = "qwen38-27b-heretic-ara-q8-gguf";
    # The ARA checkpoint has no matching vision or speculative sidecar.
    # Keep one session and a bounded prefix cache for the shared GPU.
    serve = {
      sessions = 1;
      context = 102400;
      think = "on";
      maxTokens = 16384;
      extraArgs = [
        "--cache-ram-bytes"
        "1073741824"
        "--max-pending"
        "8"
        "--request-timeout-ms"
        "1200000"
        "--stall-timeout-ms"
        "180000"
      ];
    };
  };
  # The one selected D3 runtime is native vllm-srun, alongside Gufo behind
  # llama-swap. The BF16 snapshot uses the same NAS Library/explicit loan path.
  # Declaring its loan set starts no worker and moves no model bytes.
  services.d3-decision = {
    enable = true;
    wanted = true;
    demand.enable = true;
  };
  # Compute holds no operator credentials. Existing state is retired separately
  # after NAS session continuity and the sealed backup have been verified.
  mySecrets.enable = false;

}
