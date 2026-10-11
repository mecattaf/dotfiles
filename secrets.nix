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

  # Editing authority is deliberately operator-only. Fleet-delivered SSH user
  # keys must never be recipients: compromise of one host must not unlock Git
  # history or future ciphertext.
  editors = [ admin ];

  delivered = nonEmpty (map (h: registry.${h}.hostKey) (builtins.filter (h: h != "nas") names));

  strixOnly = nonEmpty [ registry.strix.hostKey ];

  clientOnly = nonEmpty [ registry.client.hostKey ];
  # The appliance. It held NO agenix secret at all until 2026-08-28 (see the
  # `delivered` comment above). Tom's ruling that day, on being shown the
  # doctrine: "overrule that ruling if you found it too constraining." No
  # overrule was actually needed — the 2026-08-04 text already names this exact
  # door ("add its key back here for the SPECIFIC secrets it consumes, not
  # wholesale"), and this is the first walk through it. The nas is deliberately
  # NOT folded into `delivered`: it is a recipient of one ciphertext and no
  # other, and the standing authority the aug04 ruling withdrew stays withdrawn.
  nasOnly = nonEmpty [ registry.nas.hostKey ];
in
{
  # --- delivered tier (every host that runs agenix — i.e. all but the nas) ---
  # (hermes-credentials removed 2026-08-04: the Nous Research harness is no longer
  # in use anywhere in the fleet — no package, no service, no consumer left.)

  # Rotated fleet SSH user key — delivered only to the remaining hosts so mutual
  # SSH works. It is not an editor recipient for itself or any other ciphertext.
  "secrets/ssh-user-key.age".publicKeys = editors ++ delivered;
  # atuin's shared encryption key — every host with a shell history to sync needs
  # it to decrypt the others' against the self-hosted server
  # (hosts/strix/services.nix). Minted once from the strix's
  # pre-existing local key (it already had one from ordinary local use, predating
  # this sync setup); force-copied on every activation, not seed-once — see
  # modules/secrets.nix.
  "secrets/atuin-key.age".publicKeys = editors ++ delivered;
  # tom's login password, as a yescrypt hash from `mkpasswd -m yescrypt` — never
  # the password itself, and never in git in plaintext. Consumed as
  # `users.users.tom.hashedPasswordFile` by modules/user-password.nix (#54).
  # Delivered tier: any host that creates the account THROUGH agenix needs to read
  # it, and a reflash of those boxes should restore the login without operator
  # intervention. modules/user-password.nix is itself gated on mySecrets.enable,
  # so the nas never consumed this — it sets its account up without the hash.
  "secrets/tom-password-hash.age".publicKeys = editors ++ delivered;

  # --- per-host tier (tailscale pre-auth keys: single-use, non-ephemeral,
  # preauthorized, tag:mesh — minted 2026-07-05 via the fleet OAuth client;
  # only the owning host can decrypt its key) ---

  # NAS private media HTTPS: zone-limited DNS-01 token, no broad Wrangler OAuth
  # authority. Ciphertext is provisioned before enabling personal-https.nix.
  "secrets/nas-cloudflare-dns.age".publicKeys = editors ++ nasOnly;
  "secrets/k3s-token.age".publicKeys = editors ++ nasOnly;
  "secrets/k3s-agent-token.age".publicKeys = editors ++ strixOnly ++ nasOnly;
  "secrets/floor-link-token.age".publicKeys = editors ++ nasOnly;
  # --- wifi PSK tier: the strix, whose Freebox uplink
  # (wlp192s0) is now declarative too (migrated from an imperative profile on
  # flash night — refs #37). Rekey after this change:  nix develop -c agenix -r
  "secrets/wifi.age".publicKeys = editors;
  "secrets/wifi-lan.age".publicKeys = editors ++ clientOnly;

  # --- operator vault (admin key ONLY — a tar.gz of everything that is not
  # otherwise in git: pre-generated host keys + wifi profiles (staging), tom's ssh
  # private keys, the tailscale OAuth client. Disaster-recovery bundle; NEVER
  # declared in modules/secrets.nix, no host can decrypt it. Regenerate + re-commit
  # when staging changes:  tar czf - --exclude=nix-secrets-staging/installer-iso \
  #   nix-secrets-staging -C ~ .ssh tailscale.md | age -r <admin> -o <this file> ---
  "secrets/vault/operator-vault-20260705.age".publicKeys = [ admin ];

  # --- strix-only tier (service credentials) ---
  # (cloudflare-tunnel + twenty/openwebui slots removed 2026-07-05 — deprecated per Tom.
  # immich-db removed 2026-07-13: services.immich now uses a unix-socket postgres
  # with peer auth, so no DB password secret is needed. nas-credentials removed
  # with the BE550 (SMB share retired for the direct-USB LaCie).)
  # atticd RS256 JWT signing secret — the fleet binary-cache server runs on the
  # strix only (hosts/strix/attic.nix), so only it may decrypt (#42).
  "secrets/atticd-server-token.age".publicKeys = editors ++ strixOnly;

  "secrets/substrate-floor-token.age".publicKeys = editors ++ strixOnly;
  "secrets/substrate-link-token-strix.age".publicKeys = editors ++ strixOnly;

  # SoundCloud Go+ cookies.txt (Netscape format), consumed by the music-consolidation
  # drain's yt-dlp invocations (systemd user units on strix only — see that
  # repo's docs/SPEC-2026-07-06-original.md).
  "secrets/soundcloud-cookies.age".publicKeys = editors ++ strixOnly;

  # YouTube Music cookies.txt (Netscape format), exported same sitting as the
  # SoundCloud ones (2026-08-03) for the parked YouTube-Music-library issue in
  # music-consolidation — that repo's fallback for SoundCloud Go+ tracks blocked
  # by DRM. Coordinator-only, same reasoning as soundcloud-cookies.
  "secrets/youtube-music-cookies.age".publicKeys = editors ++ strixOnly;

  # Read client-side on the strix, where navidrome's relay lives, by the
  # navidrome-scan fish function (Subsonic API). Its first consumer, the cliamp
  # TUI client, was removed 2026-09-17; the zenbook left the fleet 2026-08-30.
  "secrets/navidrome-credentials.age".publicKeys = editors ++ strixOnly;

  # Immich full-permissions API key (photos.internal), read client-side by agent
  # sessions on the strix for indexing/dedup/library passes. Replaces the
  # loose ~/immichkey file, which was once world-readable and then lost in the
  # cleanup — as agenix ciphertext it survives reflash and never needs re-minting.
  "secrets/immich-api-key.age".publicKeys = editors ++ strixOnly;

  # (claude-credentials.age removed 2026-09-22: the seat logins are hand
  # `/login`s on the strix, never a delivered secret; see modules/secrets.nix.)

  # Brother HL-L2445DW Web Based Management admin password, set 2026-08-21 when
  # the printer's forced default-password change gated its move onto the thomas
  # LAN. Operator recall secret — no service consumes it; CUPS speaks IPP with
  # no auth. Minted with `age -R` directly (not agenix -e), same ciphertext
  # format. Recall on the strix without the admin key:
  #   sudo age -d -i /etc/ssh/ssh_host_ed25519_key secrets/printer-admin.age
  "secrets/printer-admin.age".publicKeys = editors ++ strixOnly;

  # Operator CLI credentials (Tom's ruling: the strix is the fleet's only
  # authenticated operator box — gh + wrangler stay off the laptops).
  "secrets/gh-hosts.age".publicKeys = editors ++ strixOnly;
  "secrets/wrangler-config.age".publicKeys = editors ++ strixOnly;
  # Cloudflare API token: ONE full-scope User API Token ("strix-full-2026-09-25",
  # minted 2026-09-25 through the dashboard plus the /user/tokens API: every account
  # and zone permission group except API-token management, plus user details and
  # memberships read/write). It replaces the wrangler OAuth session, whose refresh
  # token died on 2026-09-06 and left every agent deploy blocked. wrangler reads it
  # from CLOUDFLARE_API_TOKEN (exported by modules/secrets.nix); the crm/email/backlog
  # runbooks read ~/.local/state/cloudflare/api-token.
  "secrets/cloudflare-api-token.age".publicKeys = editors ++ strixOnly;
  # Hugging Face read token. Provisioned 2026-08-28 (fine-grained, HF display
  # name `nixOS`) after carrying a declaration with no ciphertext since the
  # declarative CLI landed — `builtins.pathExists` meant the strix simply
  # evaluated the delivery to nothing and `hf` ran unauthenticated.
  #
  # The nas joined the recipients the same day, and it is the ONLY secret the
  # appliance can decrypt. The consumer is not interactive `hf`: it is
  # hosts/nas/models.nix's library-fetch, the service its own header calls "the
  # ONLY thing that ever talks to Hugging Face", which curls catalog weights
  # anonymously and therefore 401s on anything gated. Coordinator keeps it for
  # the CLI.
  "secrets/huggingface-token.age".publicKeys = editors ++ strixOnly ++ nasOnly;

  # Qwen Token Plan API key (Alibaba MaaS, ap-southeast-1 — the OpenAI-compatible
  # subscription endpoint pi ships as the built-in `qwen-token-plan` provider).
  # Coordinator-only for the same reason as claude-credentials: it is a metered
  # subscription, not a per-token bill, so every box that can decrypt it can burn
  # the shared 7-day credit pool. The strix is the only agent host.
  "secrets/qwencloud-token.age".publicKeys = editors ++ strixOnly;
  # OpenRouter API key (created 2026-09-29, $40 of one-time credits, plus the
  # free-model daily allowance). Coordinator-only for the same reason as the
  # Qwen key: any box that can decrypt it can spend the prepaid balance, and the
  # strix is the only agent host.
  "secrets/openrouter-token.age".publicKeys = editors ++ strixOnly;
  # Codex CLI ChatGPT-subscription login (~/.codex/auth.json: id/access/refresh
  # tokens + account_id, auth_mode "chatgpt"). Re-logged 2026-10-04 onto the
  # Pro-plan account; this ciphertext is that session so a reflash restores
  # `codex` without a browser login. Coordinator-only for exactly the
  # claude-credentials reasons above: the strix is the only agent host,
  # and two devices refreshing one OAuth session sign each other out.
  # Delivered by modules/secrets.nix as a seed-once COPY (Codex rewrites the
  # file on token refresh). Re-mint after any re-login:
  #   age -R <(nix eval --raw --impure --expr 'builtins.concatStringsSep "\n" (import ./secrets.nix)."secrets/codex-auth.age".publicKeys') \
  #       -o secrets/codex-auth.age ~/.codex/auth.json
  # (no admin key needed — creating a ciphertext only uses public keys).
  "secrets/codex-auth.age".publicKeys = editors ++ strixOnly;
  # gws (Google Workspace CLI, personal account thomasmecattaf@gmail.com) — same
  # operator-box ruling as gh/wrangler above. client_secret identifies the OAuth
  # app; credentials.enc + .encryption_key + token_cache.json are the actual
  # logged-in state (see ~/.config/gws/HANDOFF.md for full provenance, 2026-07-10).
  "secrets/gws-client-secret.age".publicKeys = editors ++ strixOnly;
  "secrets/gws-credentials.age".publicKeys = editors ++ strixOnly;
  "secrets/gws-encryption-key.age".publicKeys = editors ++ strixOnly;
  "secrets/gws-token-cache.age".publicKeys = editors ++ strixOnly;
}
