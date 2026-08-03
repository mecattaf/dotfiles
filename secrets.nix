# agenix recipients — the crypto-enforced ACL (analogue of sops .sops.yaml
# creation_rules). Read ONLY by the `agenix` CLI, never imported into a NixOS eval.
#
# Host public keys come from the mesh registry (single source of truth); the admin key's
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
  # Editing authority is deliberately operator-only. Fleet-delivered SSH user
  # keys must never be recipients: compromise of one host must not unlock Git
  # history or future ciphertext.
  editors = [ admin ];

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
  # Rotated fleet SSH user key — delivered only to the remaining hosts so mutual
  # SSH works. It is not an editor recipient for itself or any other ciphertext.
  "secrets/ssh-user-key.age".publicKeys = editors ++ hostKeys;
  # atuin's shared encryption key — every host needs it to decrypt each other's
  # synced history against the self-hosted server (hosts/coordinator/services.nix).
  # Minted once from the coordinator's pre-existing local key (it already had one
  # from ordinary local use, predating this sync setup); force-copied on every
  # activation, not seed-once — see modules/secrets.nix.
  "secrets/atuin-key.age".publicKeys = editors ++ hostKeys;
  # tom's login password, as a yescrypt hash from `mkpasswd -m yescrypt` — never
  # the password itself, and never in git in plaintext. Consumed as
  # `users.users.tom.hashedPasswordFile` by modules/user-password.nix (#54).
  # Common tier: any host that creates the account needs to read it, and a
  # reflash of any box should restore the login without operator intervention.
  # The rule is declared now; the ciphertext is created with agenix only when
  # Tom supplies the hash (the module is gated on the file existing).
  "secrets/tom-password-hash.age".publicKeys = editors ++ hostKeys;

  # --- per-host tier (tailscale pre-auth keys: single-use, non-ephemeral,
  # preauthorized, tag:mesh — minted 2026-07-05 via the fleet OAuth client;
  # only the owning host can decrypt its key) ---
  "secrets/tailscale-authkey-coordinator.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/tailscale-authkey-zenbook-duo.age".publicKeys =
    editors ++ nonEmpty [ registry.zenbook-duo.hostKey ];

  # --- wifi PSK tier: the laptops PLUS the coordinator, whose Freebox uplink
  # (wlp192s0) is now declarative too (migrated from an imperative profile on
  # flash night — refs #37). Rekey after this change:  nix develop -c agenix -r
  "secrets/wifi.age".publicKeys = editors ++ laptops ++ coordinatorOnly;

  # --- operator vault (admin key ONLY — a tar.gz of everything that is not
  # otherwise in git: pre-generated host keys + wifi profiles (staging), tom's ssh
  # private keys, the tailscale OAuth client. Disaster-recovery bundle; NEVER
  # declared in modules/secrets.nix, no host can decrypt it. Regenerate + re-commit
  # when staging changes:  tar czf - --exclude=nix-secrets-staging/installer-iso \
  #   nix-secrets-staging -C ~ .ssh tailscale.md | age -r <admin> -o <this file> ---
  "secrets/vault/operator-vault-20260705.age".publicKeys = [ admin ];

  # --- coordinator-only tier (service credentials) ---
  # (cloudflare-tunnel + twenty/openwebui slots removed 2026-07-05 — deprecated per Tom.
  # immich-db removed 2026-07-13: services.immich now uses a unix-socket postgres
  # with peer auth, so no DB password secret is needed. nas-credentials removed
  # with the BE550 (SMB share retired for the direct-USB LaCie).)
  # atticd RS256 JWT signing secret — the fleet binary-cache server runs on the
  # coordinator only (hosts/coordinator/attic.nix), so only it may decrypt (#42).
  "secrets/atticd-server-token.age".publicKeys = editors ++ coordinatorOnly;

  # cliamp (client) needs this on both boxes it runs from — coordinator (where
  # navidrome itself lives) and zenbook-duo (laptops tier).
  "secrets/navidrome-credentials.age".publicKeys = editors ++ coordinatorOnly ++ laptops;

  # Operator CLI credentials (Tom's ruling: the coordinator is the fleet's only
  # authenticated operator box — gh + wrangler stay off the laptops).
  "secrets/gh-hosts.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/wrangler-config.age".publicKeys = editors ++ coordinatorOnly;
  # Optional Hugging Face read token. The rule is declared now; ciphertext is
  # created with agenix only when Tom supplies the credential.
  "secrets/huggingface-token.age".publicKeys = editors ++ coordinatorOnly;
  # Borg passphrase for the coordinator's push job to the NAS append-only repo
  # (#130 ws2b, hosts/coordinator/backups.nix). Rule declared now; ciphertext
  # lands via the runbook before myCoordinatorBackups.enable flips.
  "secrets/borg-passphrase.age".publicKeys = editors ++ coordinatorOnly;

  # gws (Google Workspace CLI, personal account thomasmecattaf@gmail.com) — same
  # operator-box ruling as gh/wrangler above. client_secret identifies the OAuth
  # app; credentials.enc + .encryption_key + token_cache.json are the actual
  # logged-in state (see ~/.config/gws/HANDOFF.md for full provenance, 2026-07-10).
  "secrets/gws-client-secret.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/gws-credentials.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/gws-encryption-key.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/gws-token-cache.age".publicKeys = editors ++ coordinatorOnly;
}
