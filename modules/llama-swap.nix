{
  config,
  lib,
  pkgs,
  ...
}:
# Native llama-swap control plane for the two Strix Halo nodes.
#
# Part 1 of 2: this module owns only the proxy package, lifecycle, state, and
# network boundary. The next session owns the model roster, backend commands,
# groups, and weight materialization. The proxy itself is a small, always-on Go
# process and consumes no GPU. Tally remains the admission controller for the
# per-box GPU pools; llama-swap supplies the stable API door and load/unload
# mechanism.
let
  cfg = config.services.llama-swap;
in
{
  services.llama-swap = {
    enable = true;
    package = pkgs.llama-swap;

    # One conventional endpoint on both nodes. Binding all IPv4 interfaces makes
    # it reachable over Tailscale and the direct TB link; the interface-scoped
    # firewall below keeps it closed on raw LAN/wifi.
    listenAddress = "0.0.0.0";
    port = 9292;
    openFirewall = false;

    # NixOS renders this attrset to an immutable YAML store path and changes the
    # unit's ExecStart when it changes, so --watch-config is unnecessary.
    settings = {
      healthCheckTimeout = 900; # large Strix models can take minutes to cold-load
      logLevel = "info";
      logTimeFormat = "rfc3339";
      logToStdout = "both"; # proxy + backend output in journalctl -u llama-swap

      # Keep the UI useful across proxy restarts without retaining prompt/response
      # bodies. StateDirectory below supplies the only writable service path.
      store.path = "/var/lib/llama-swap/activity.sqlite";
      captureBuffer = 0;

      # No host ROCm userspace is installed by design; backends carry their own.
      # Avoid futile rocm-smi/LACT probing from the proxy.
      performance.disabled = true;

      startPort = 10001;
      sendLoadingState = true;

      # Tally owns residency and the explicit unload boundary. Do not let an
      # independent global timer evict a model during an admitted batch job.
      globalTTL = 0;
      unloadTimeout = 60;

      # The serving plane is live now; declarative per-role model definitions land
      # here as their backend/weight choices are promoted from the loadout plan.
      models = { };
    };
  };

  # Keep the operator CLI on PATH as well as in the service closure.
  environment.systemPackages = [ cfg.package ];

  # Tailnet-only remote API, matching the fleet's VNC/media/ASR posture. The
  # direct thunderbolt0 interface is already trusted in modules/strix.nix.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ cfg.port ];

  systemd.services.llama-swap = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    environment.LLAMA_CACHE = "/var/cache/llama-swap";
    serviceConfig = {
      # The upstream NixOS module uses DynamicUser + ProtectSystem=strict. Add
      # systemd-managed writable paths for v240's activity store and llama.cpp's
      # on-demand `-hf` downloads (the same LLAMA_CACHE seam qmx's module uses).
      StateDirectory = "llama-swap";
      StateDirectoryMode = "0750";
      CacheDirectory = "llama-swap";
      CacheDirectoryMode = "0750";
      WorkingDirectory = lib.mkForce "/var/lib/llama-swap";
      UMask = "0077";

      # Inherited by native GPU backend children when models are added.
      LimitMEMLOCK = "infinity";
      TimeoutStopSec = "2min";
    };
  };
}
