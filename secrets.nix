# agenix recipients — the crypto-enforced ACL (analogue of sops .sops.yaml
# creation_rules). Read ONLY by the `agenix` CLI, never imported into a NixOS eval.
#
# Public keys come from the mesh registry (single source of truth); the admin key's
# private half (AGE-SECRET-KEY-1… line) lives in Tom's Google Password Manager —
# recovery on any machine is Google login + paste. It lets you edit any secret from
# anywhere. Tiers are enforced by cryptography — a host not listed for a secret
# holds no key that can decrypt it.
#
# Edit a secret:   nix develop -c agenix -e secrets/<name>.age   (needs the admin key)
# Rekey after a registry change:   nix develop -c agenix -r
let
  registry = import ./modules/mesh-registry.nix;
  names = builtins.attrNames registry;
  nonEmpty = builtins.filter (k: k != "");

  # Admin age key (private half in Google Password Manager) — always a recipient so
  # editing works before/after any flash.
  admin = "age159pyyqqnrxwv3d7f758u5xtzv53fu2nwc85x3sur63g3p29jnegq9tf47w";

  hostKeys = nonEmpty (map (h: registry.${h}.hostKey) names);
  userKeys = nonEmpty (map (h: registry.${h}.userKey) names);
  editors = [ admin ] ++ userKeys;

  laptops = nonEmpty [
    registry.zenbook-duo.hostKey
  ];
  coordinatorOnly = nonEmpty [ registry.coordinator.hostKey ];
in
{
  # --- common tier (every host may decrypt) ---
  "secrets/claude-credentials.age".publicKeys = editors ++ hostKeys;
  "secrets/hermes-credentials.age".publicKeys = editors ++ hostKeys;
  "secrets/env.age".publicKeys = editors ++ hostKeys;
  # Shared `tom@mesh` SSH user key — delivered to every host so mutual SSH works
  # both directions (mesh.nix wires the authorized_keys/known_hosts side).
  "secrets/ssh-user-key.age".publicKeys = editors ++ hostKeys;

  # --- per-host tier (tailscale pre-auth keys: single-use, non-ephemeral,
  # preauthorized, tag:mesh — minted 2026-07-05 via the fleet OAuth client;
  # only the owning host can decrypt its key) ---
  "secrets/tailscale-authkey-coordinator.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/tailscale-authkey-worker.age".publicKeys = editors ++ nonEmpty [ registry.worker.hostKey ];
  "secrets/tailscale-authkey-zenbook-duo.age".publicKeys = editors ++ nonEmpty [ registry.zenbook-duo.hostKey ];

  # --- laptop tier (wifi PSK) ---
  "secrets/wifi.age".publicKeys = editors ++ laptops;

  # --- operator vault (admin key ONLY — a tar.gz of everything that is not
  # otherwise in git: pre-generated host keys + wifi profiles (staging), tom's ssh
  # private keys, the tailscale OAuth client. Disaster-recovery bundle; NEVER
  # declared in modules/secrets.nix, no host can decrypt it. Regenerate + re-commit
  # when staging changes:  tar czf - --exclude=nix-secrets-staging/installer-iso \
  #   nix-secrets-staging -C ~ .ssh tailscale.md | age -r <admin> -o <this file> ---
  "secrets/vault/operator-vault-20260705.age".publicKeys = [ admin ];

  # --- coordinator-only tier (quadlet service creds; worker deliberately excluded) ---
  # (cloudflare-tunnel + twenty/openwebui slots removed 2026-07-05 — deprecated per Tom.
  # nas-credentials stays as the option for BE550 Secure Sharing, unused while the
  # share is guest-mode; moot entirely once the LaCie attaches directly via USB.)
  "secrets/immich-db.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/nas-credentials.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/navidrome-credentials.age".publicKeys = editors ++ coordinatorOnly;

  # Operator CLI credentials (Tom's ruling: the coordinator is the fleet's only
  # authenticated operator box — gh + wrangler stay off the worker/laptops).
  "secrets/gh-hosts.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/wrangler-config.age".publicKeys = editors ++ coordinatorOnly;

  # gws (Google Workspace CLI, personal account thomasmecattaf@gmail.com) — same
  # operator-box ruling as gh/wrangler above. client_secret identifies the OAuth
  # app; credentials.enc + .encryption_key + token_cache.json are the actual
  # logged-in state (see ~/.config/gws/HANDOFF.md for full provenance, 2026-07-10).
  "secrets/gws-client-secret.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/gws-credentials.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/gws-encryption-key.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/gws-token-cache.age".publicKeys = editors ++ coordinatorOnly;
}
