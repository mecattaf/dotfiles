{ config, lib, ... }:
# Distributed builds — offload heavy compilation to the worker (the designated
# builder, a Strix Halo). Imported by the coordinator and zenbook-duo; NOT the
# worker itself (it builds locally). This is the COMPILE-PLACEMENT half of the
# story whose STORAGE half is the fleet binary cache: `nix.buildMachines` decides
# WHERE a derivation is built, attic (hosts/coordinator/attic.nix) stores the
# result so it is built once and pulled everywhere, and the worker's
# post-build-hook (hosts/worker/cache-push.nix) pushes every offloaded build
# straight into that cache. Net effect: run `nixos-rebuild` on the weak zenbook
# or the always-on coordinator and the actual `gcc`/`rustc` work lands on the
# worker, then the closure is cached for the next host. refs #42.
#
# Transport: the coordinator reaches the worker over the always-on TB5 fast lane
# (worker-tb → 10.77.0.2, modules/strix.nix); the zenbook over the tailscale mesh
# (worker, MagicDNS). Root's nix-daemon authenticates with the shared tom@mesh
# key as `tom` — a trusted Nix user on the worker (@wheel), so it may run
# `nix-store --serve --write`. known_hosts is pre-seeded fleet-wide
# (modules/mesh.nix), so there is no TOFU prompt.
#
# Gated on mySecrets.enable because it needs the decrypted tom@mesh private key
# (delivered by agenix). It is ON for the coordinator, so coordinator→worker
# offloading is live. It is OFF for the zenbook today, so this is INERT there
# until that one flag is flipped in hosts/zenbook-duo/default.nix (same post-flash
# two-step the Strix pair went through) — until then the zenbook just builds
# locally, no error.
#
# Graceful fallback by design: if the worker is unreachable (zenbook off-tailnet,
# worker powered down) nix falls back to building locally. The remote is a
# PREFERENCE (speedFactor), never a hard dependency — so a travelling laptop can
# always still rebuild itself.
let
  # coordinator↔worker is the direct Thunderbolt cable (worker-tb resolves only on
  # the Strix pair, via networking.hosts in modules/strix.nix); every other client
  # routes to the worker over the tailnet.
  builderHost = if config.networking.hostName == "coordinator" then "worker-tb" else "worker";
in
{
  config = lib.mkIf (config.mySecrets.enable && config.networking.hostName != "worker") {
    nix.distributedBuilds = true;

    # The worker pulls each derivation's inputs from the substituters (incl. the
    # fleet cache) ITSELF, instead of the client uploading the whole closure over
    # SSH. Far less traffic, and it means a cold client offloads work it does not
    # even have the sources for.
    nix.settings.builders-use-substitutes = true;

    nix.buildMachines = [
      {
        hostName = builderHost;
        sshUser = "tom";
        sshKey = config.age.secrets.ssh-root-key.path; # root's outbound mesh key (modules/secrets.nix)
        systems = [ "x86_64-linux" ];
        # Match the worker daemon's four-job ceiling. ROCm derivations use eight
        # cores each, filling the 16C/32T CPU without recreating the 2026-07-22
        # Composable Kernel OOM through nested derivation/compiler parallelism.
        # speedFactor > 1 makes nix prefer it over the local (weaker) builder.
        maxJobs = 4;
        speedFactor = 2;
        # kvm: the worker is the microvm host (modules/microvm-host.nix), so it can
        # take derivations that need /dev/kvm. big-parallel: heavy multi-core builds.
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];
      }
    ];
  };
}
