# agenix recipients — the crypto-enforced ACL (analogue of sops .sops.yaml
# creation_rules). Read ONLY by the `agenix` CLI, never imported into a NixOS eval.
#
# Public keys come from the mesh registry (single source of truth); the admin key is
# the portable age key kept on a USB stick (its private half lets you edit any secret
# from anywhere). Tiers are enforced by cryptography — a host not listed for a secret
# holds no key that can decrypt it.
#
# Edit a secret:   nix develop -c agenix -e secrets/<name>.age   (needs the admin key)
# Rekey after a registry change:   nix develop -c agenix -r
let
  registry = import ./modules/mesh-registry.nix;
  names = builtins.attrNames registry;
  nonEmpty = builtins.filter (k: k != "");

  # Portable USB age key — always a recipient so editing works before/after any flash.
  admin = "age159pyyqqnrxwv3d7f758u5xtzv53fu2nwc85x3sur63g3p29jnegq9tf47w";

  hostKeys = nonEmpty (map (h: registry.${h}.hostKey) names);
  userKeys = nonEmpty (map (h: registry.${h}.userKey) names);
  editors = [ admin ] ++ userKeys;

  laptops = nonEmpty [
    registry.dell-xps.hostKey
    registry.zenbook-duo.hostKey
  ];
  coordinatorOnly = nonEmpty [ registry.coordinator.hostKey ];
in
{
  # --- common tier (every host may decrypt) ---
  "secrets/claude-credentials.age".publicKeys = editors ++ hostKeys;
  "secrets/tailscale-authkey.age".publicKeys = editors ++ hostKeys;
  "secrets/env.age".publicKeys = editors ++ hostKeys;

  # --- laptop tier (wifi PSK) ---
  "secrets/wifi.age".publicKeys = editors ++ laptops;

  # --- coordinator-only tier (quadlet service creds; worker deliberately excluded) ---
  "secrets/immich-db.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/cloudflare-tunnel.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/nas-credentials.age".publicKeys = editors ++ coordinatorOnly;
}
