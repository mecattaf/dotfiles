{
  config,
  lib,
  pkgs,
  ...
}:
# Native llama-swap control plane for the Strix Halo coordinator.
#
# This module owns only the proxy package, lifecycle, state, and network
# boundary. local-models.nix owns the typed roster, backend commands, and
# guarded weight materialization. Runtime appliances such as FastFlowLM stay
# outside this control plane. The proxy itself is a small, always-on Go
# process and consumes no GPU. Tally remains the admission controller for the
# coordinator GPU pool; llama-swap supplies the one stable API door and load/unload
# mechanism.
let
  cfg = config.services.llama-swap;

  # Explicit "stop using it now", separate from the roster's idle ttl (#149):
  # unload one model by id, or everything when called bare.
  llamaSwapUnload = pkgs.writeShellApplication {
    name = "llama-swap-unload";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      exec curl -fsS -X POST "http://localhost:${toString cfg.port}/api/models/unload''${1:+/$1}"
    '';
  };
in
{
  services.llama-swap = {
    enable = true;
    package = pkgs.llama-swap;

    # One conventional endpoint on coordinator. Binding all IPv4 interfaces makes
    # it reachable over Tailscale; the interface-scoped firewall below keeps it
    # closed on raw LAN/wifi.
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

      # Fallback only: every roster deployment carries a per-model idle ttl
      # (lib/local-models.nix, #149) which overrides this. Tally admission is
      # orthogonal — it leases job dispatch, not backend residency, and the
      # ttl timer never fires with a request in flight.
      globalTTL = 0;
      unloadTimeout = 60;
    };
  };

  # Keep the operator CLI on PATH as well as in the service closure.
  environment.systemPackages = [
    cfg.package
    llamaSwapUnload
  ];

  # Two remote doors, both interface-scoped; nothing on raw LAN/wifi.
  #
  # tailnet: roaming clients (zenbook, phone), matching the fleet's VNC/media/
  # ASR posture.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ cfg.port ];
  # private /30 cable to the NAS: the NAS has NO tailnet identity by design
  # (services.tailscale.enable = mkForce false, hosts/nas/default.nix), so its
  # only path to this endpoint is the Ethernet cable the coordinator owns
  # (hosts/coordinator/uplink-nas.nix). This is a first-class door, not a
  # fallback — NAS-side consumers such as the Paperless AI phase (#136) depend
  # on it, and nothing about the LLM endpoint should require Tailscale.
  # (+ wlp192s0 since the 2026-08-20 rewire: NAS-side consumers dial from the
  # BE550 LAN once the /30 cable retires. Inert where the interface is absent.)
  networking.firewall.interfaces.wlp192s0.allowedTCPPorts = [ cfg.port ];

  systemd.services.llama-swap = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    # Backend children inherit one stable multimodal placeholder. This keeps
    # OpenAI embedding clients from having to discover llama.cpp's otherwise
    # randomized marker through each transient backend's /props endpoint.
    environment = {
      LLAMA_MEDIA_MARKER = "<__media__>";
      # DynamicUser has no ordinary home. Point Mesa/RADV at the writable
      # systemd-managed cache below so Vulkan pipelines survive model swaps.
      XDG_CACHE_HOME = "/var/cache/llama-swap";
    };
    serviceConfig = {
      # The upstream NixOS module uses DynamicUser + ProtectSystem=strict. Add
      # systemd-managed writable paths for v240's activity store and backend
      # scratch state. Model weights are immutable store paths; runtime downloads
      # are forbidden by modules/local-models.nix.
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
