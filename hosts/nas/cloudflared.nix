{
  config,
  lib,
  ...
}:
# ─── The NAS's own Cloudflare tunnel: inbound, and separate on purpose ──────
#
# Tom's ruling, 2026-09-20, on being asked where the tunnel belongs:
#   "i like having that separated from the coordinator's interaction with
#    cloudflare"
#
# So this is the NAS's tunnel, minted against the NAS's own credential, and it
# shares nothing with the coordinator's Wrangler OAuth blob
# (secrets/wrangler-config.age, coordinatorOnly) nor with the NAS's own two
# zone-limited DNS-01 ACME tokens (./personal-https.nix, ./headscale.nix).
# Three Cloudflare relationships on this fleet, three credentials, three
# blast radiuses:
#
#   coordinator  wrangler-config.age   Pages/R2/Workers control plane. Broad.
#   nas ACME     nas-cloudflare-dns    DNS-01 TXT only. Proves ownership.
#                                      Gives Cloudflare no route inward.
#   nas tunnel   THIS FILE             A route inward. One hostname. That is
#                                      the whole reason it is its own door.
#
# ── WHAT THIS DOES NOT DO ─────────────────────────────────────────────────
# It does not start the sink receiver. `ingress` below points at a loopback
# port on this box that NOTHING LISTENS ON TODAY. That is deliberate: the
# receiver is the sandbox spike's own work (U6, the JSONL-and-receipt sink)
# and lands in its own commit. Until it does, the hostname answers 502 from
# cloudflared, which is the correct and visible failure.
#
# ── THE NEVER-ROUTED LIST — read this before adding a second ingress ───────
# A tunnel is an inbound route that ignores the LAN firewall entirely: the
# daemon dials OUT to Cloudflare and Cloudflare dials back down the same
# connection. Every `iifname "enp1s0"` rule elsewhere in hosts/nas/ is
# bypassed for anything named here. So the list of what must NEVER appear in
# `ingress` is part of the module, not part of someone's memory:
#
#   ateapi / ate-api-server   Agent Substrate's API server. Authorization is
#                             UNIMPLEMENTED upstream. Reachability IS full
#                             control of every sandbox on the fleet.
#   ax-server                 Same property, same reason. LAN-only, forever.
#   the kube API (6443)       The cluster's root credential surface. It is
#                             opened on enp1s0 only; see modules/k3s-fleet.nix.
#   herdr sockets             The human surface and the agent signal plane.
#                             Unix sockets under /run/user, never a TCP port,
#                             and never reachable from outside this house.
#   attic's push endpoint     :8080 is `--public` for PULLS. Push is gated by
#                             the RS256 secret (./attic.nix). Exposing the
#                             endpoint publicly turns a signing-key theft into
#                             a fleet-wide supply chain, because every box on
#                             the LAN trusts `fleet:igImm/…` unconditionally.
#
# The assertion below enforces the hostname half of that mechanically. The
# rest is doctrine, because a NixOS assertion cannot know which loopback port
# is ateapi's.
#
# ── RUNBOOK — walk this before flipping the gate ──────────────────────────
#   1. On a machine with `cloudflared` on PATH (it is fleet-wide,
#      home/home.nix), log in once against the mecattaf.dev zone:
#        cloudflared tunnel login
#   2. Create the tunnel. The name is the tunnel's identity, not a hostname:
#        cloudflared tunnel create nas-sink
#      It prints a tunnel UUID and writes a credentials JSON. Note the UUID.
#   3. Mint the agenix ciphertext from the credentials file, NOT from the
#      `tunnel token` base64 blob — `services.cloudflared` wants the JSON:
#        cloudflared tunnel token --cred-file /dev/stdout nas-sink \
#          | nix develop -c agenix -e secrets/nas-cloudflared-tunnel.age
#      (agenix opens $EDITOR; paste and save if the pipe form is refused by
#      your agenix version. The admin key is required, so this is Tom's step
#      and nobody else's.)
#   4. Route the hostname at the tunnel:
#        cloudflared tunnel route dns nas-sink sink.mecattaf.dev
#   5. Set myNas.cloudflared.tunnelId to the UUID from step 2, flip
#      myNas.cloudflared.enable, deploy the NAS.
#   6. Prove it: `systemctl status cloudflared-tunnel-<uuid>` on the NAS, and
#      `curl -sS https://sink.mecattaf.dev/` from off-LAN. 502 until the sink
#      receiver exists is SUCCESS at this stage.
#
# ── GATE OFF ──────────────────────────────────────────────────────────────
# Lands with `enable = false`, same as every #130 workstream did. The gate
# cannot be flipped before step 3, because secrets/nas-cloudflared-tunnel.age
# does not exist in the tree yet — agenix needs Tom's admin key and this PR
# was opened by the overnight spike, which has none and must never have one.
let
  cfg = config.myNas.cloudflared;

  # The one hostname this tunnel serves. Placeholder until the sink receiver
  # lands and Tom picks the final name; the ZONE is not a placeholder, it is
  # the zone this repo already owns (modules/artifacts-defaults.nix).
  sinkHostname = "sink.mecattaf.dev";

  # Loopback only. A tunnel origin that binds 0.0.0.0 is a LAN service with
  # extra steps; this one is reachable from the tunnel and from nothing else.
  sinkOrigin = "http://127.0.0.1:8799";

  # Hostnames that must never be routed, matched against the ingress keys.
  # Mechanical half of the doctrine block above.
  forbiddenPrefixes = [
    "ateapi"
    "ate-api"
    "ax"
    "ax-server"
    "kube"
    "k8s"
    "herdr"
    "attic"
    "cache"
  ];
  ingressHostnames = builtins.attrNames cfg.tunnelIngress;
  offenders = builtins.filter (
    h: builtins.any (p: lib.hasPrefix "${p}." h) forbiddenPrefixes
  ) ingressHostnames;
in
{
  options.myNas.cloudflared = {
    enable = lib.mkEnableOption "the NAS's own inbound Cloudflare tunnel (separate from the coordinator's Cloudflare authority, Tom 2026-09-20)";

    tunnelId = lib.mkOption {
      type = lib.types.str;
      default = "00000000-0000-0000-0000-000000000000";
      description = ''
        The tunnel UUID printed by `cloudflared tunnel create nas-sink`
        (runbook step 2). The all-zeroes default is a tripwire, not a value:
        the assertion below refuses to evaluate with it once the gate is on.
      '';
    };

    tunnelIngress = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        ${sinkHostname} = sinkOrigin;
      };
      description = ''
        hostname -> origin URL. ONE entry today. Read the never-routed list in
        this file's header before adding a second, and understand that a
        tunnel ingress bypasses every nftables rule on this box.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.mySecrets.enable;
        message = "The NAS tunnel needs agenix delivery for its credentials file; see hosts/nas/default.nix.";
      }
      {
        assertion = cfg.tunnelId != "00000000-0000-0000-0000-000000000000";
        message = "myNas.cloudflared.tunnelId is still the all-zeroes tripwire. Walk the runbook in hosts/nas/cloudflared.nix (steps 2 and 5) before enabling.";
      }
      {
        assertion = offenders == [ ];
        message = "hosts/nas/cloudflared.nix: refusing to route ${toString offenders} through the tunnel. ateapi, ax-server, the kube API, herdr and attic's push endpoint are LAN-only by doctrine; see the never-routed list in that file's header.";
      }
      {
        # One hostname, one reviewer's attention. Growth is allowed, but only
        # by someone who edited this number and therefore read the header.
        assertion = builtins.length ingressHostnames == 1;
        message = "hosts/nas/cloudflared.nix expects exactly one tunnel hostname. Adding a second is a deliberate act: read the never-routed list, then raise this bound in the same commit.";
      }
    ];

    # The credentials JSON from runbook step 3. nasOnly in secrets.nix, the
    # same narrow tier nas-cloudflare-dns and huggingface-token sit in: the
    # appliance is a recipient of exactly the ciphertexts it consumes and no
    # others (the 2026-08-04 ruling, and hosts/nas/default.nix's note on it).
    age.secrets.nas-cloudflared-tunnel = {
      file = ../../secrets/nas-cloudflared-tunnel.age;
      mode = "0400";
      # cloudflared's NixOS module runs the tunnel as the `cloudflared` user.
      owner = "cloudflared";
      group = "cloudflared";
    };

    services.cloudflared = {
      enable = true;
      tunnels.${cfg.tunnelId} = {
        credentialsFile = config.age.secrets.nas-cloudflared-tunnel.path;
        ingress = lib.mapAttrs (_hostname: origin: { service = origin; }) cfg.tunnelIngress;
        # Everything not named above is a 404 from cloudflared itself, before
        # any origin is dialled. This is the catch-all, and it is the reason
        # a typo in the Cloudflare dashboard cannot accidentally publish a
        # service on this box.
        default = "http_status:404";
      };
    };

    # NO FIREWALL RULE HERE, AND THAT IS THE POINT. cloudflared makes an
    # OUTBOUND connection to Cloudflare's edge and inbound requests arrive
    # back down it. Nothing listens on a public interface, so there is nothing
    # to open — and nothing that `networking.firewall` can protect either,
    # which is exactly why the never-routed list is a doctrine block and an
    # assertion rather than an nftables rule.
  };
}
