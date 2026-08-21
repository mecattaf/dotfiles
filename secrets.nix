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

  # Hosts that actually run agenix delivery, and therefore the widest tier any
  # secret gets. There is deliberately no every-host tier: hosts/nas/default.nix
  # sets `mySecrets.enable = false` ("NO SECRET LIVES ON THIS BOX" —
  # hosts/nas/backups.nix), so the appliance is delivered nothing and must not
  # hold standing decryption authority over ciphertext it never reads (2026-08-04
  # ruling — it had been a recipient of the whole common tier, including tom's
  # password hash and the fleet SSH private key). If the nas ever flips
  # mySecrets.enable on (ws5 attic is the likely trigger — hosts/nas/attic.nix),
  # add its key back here for the specific secrets it consumes, not wholesale.
  delivered = nonEmpty (map (h: registry.${h}.hostKey) (builtins.filter (h: h != "nas") names));

  laptops = nonEmpty [
    registry.zenbook-duo.hostKey
  ];
  coordinatorOnly = nonEmpty [ registry.coordinator.hostKey ];
in
{
  # --- delivered tier (every host that runs agenix — i.e. all but the nas) ---
  # (hermes-credentials removed 2026-08-04: the Nous Research harness is no longer
  # in use anywhere in the fleet — no package, no service, no consumer left.)
  "secrets/env.age".publicKeys = editors ++ delivered;
  # Rotated fleet SSH user key — delivered only to the remaining hosts so mutual
  # SSH works. It is not an editor recipient for itself or any other ciphertext.
  "secrets/ssh-user-key.age".publicKeys = editors ++ delivered;
  # atuin's shared encryption key — every host with a shell history to sync needs
  # it to decrypt the others' against the self-hosted server
  # (hosts/coordinator/services.nix). Minted once from the coordinator's
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
  "secrets/tailscale-authkey-coordinator.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/tailscale-authkey-zenbook-duo.age".publicKeys =
    editors ++ nonEmpty [ registry.zenbook-duo.hostKey ];

  # --- wifi PSK tier: the laptops PLUS the coordinator, whose Freebox uplink
  # (wlp192s0) is now declarative too (migrated from an imperative profile on
  # flash night — refs #37). Rekey after this change:  nix develop -c agenix -r
  "secrets/wifi.age".publicKeys = editors ++ laptops ++ coordinatorOnly;
  # BE550 repeated-LAN credentials ($BE550_SSID / $BE550_PSK), minted at cutover
  # phase 3 (2026-08-21) for the coordinator's be550-lan profile
  # (hosts/coordinator/uplink-nas.nix). Coordinator-only for now — extend to the
  # laptops tier when the zenbook gets its own be550 profile (it also needs its
  # loopback-AdGuard DoH story resolved first; see the dns_hijack drop list in
  # hosts/nas/router.nix).
  "secrets/wifi-lan.age".publicKeys = editors ++ coordinatorOnly;

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

  # SoundCloud Go+ cookies.txt (Netscape format), consumed by the music-consolidation
  # drain's yt-dlp invocations (systemd user units on coordinator only — see that
  # repo's docs/SPEC-2026-07-06-original.md). NOT for cliamp: cliamp shells to
  # `yt-dlp --cookies-from-browser chrome` directly against a live signed-in browser
  # and has no file-based cookie mode, so it needs no secret at all (dotfiles#70).
  "secrets/soundcloud-cookies.age".publicKeys = editors ++ coordinatorOnly;

  # YouTube Music cookies.txt (Netscape format), exported same sitting as the
  # SoundCloud ones (2026-08-03) for the parked YouTube-Music-library issue in
  # music-consolidation — that repo's fallback for SoundCloud Go+ tracks blocked
  # by DRM. Coordinator-only, same reasoning as soundcloud-cookies.
  "secrets/youtube-music-cookies.age".publicKeys = editors ++ coordinatorOnly;

  # cliamp (client) needs this on both boxes it runs from — coordinator (where
  # navidrome itself lives) and zenbook-duo (laptops tier).
  "secrets/navidrome-credentials.age".publicKeys = editors ++ coordinatorOnly ++ laptops;

  # Immich full-permissions API key (photos.internal), read client-side by agent
  # sessions on the coordinator for indexing/dedup/library passes. Replaces the
  # loose ~/immichkey file, which was once world-readable and then lost in the
  # cleanup — as agenix ciphertext it survives reflash and never needs re-minting.
  "secrets/immich-api-key.age".publicKeys = editors ++ coordinatorOnly;

  # Claude Code OAuth credential. Demoted from the common tier to coordinator-only
  # (2026-08-04, Tom's ruling): the nas holds no `claude` binary and never ran an
  # agent, so it had no use for the token; zenbook-duo was already excluded from
  # delivery (jul12 ruling — it logs in with its OWN session, since two devices
  # refreshing one shared token race and sign each other out). That left the
  # coordinator as the only real consumer, so the recipient tier now says so —
  # a token this wide should not be decryptable by boxes that never spend it.
  "secrets/claude-credentials.age".publicKeys = editors ++ coordinatorOnly;

  # Brother HL-L2445DW Web Based Management admin password, set 2026-08-21 when
  # the printer's forced default-password change gated its move onto the thomas
  # LAN. Operator recall secret — no service consumes it; CUPS speaks IPP with
  # no auth. Minted with `age -R` directly (not agenix -e), same ciphertext
  # format. Recall on the coordinator without the admin key:
  #   sudo age -d -i /etc/ssh/ssh_host_ed25519_key secrets/printer-admin.age
  "secrets/printer-admin.age".publicKeys = editors ++ coordinatorOnly;

  # Operator CLI credentials (Tom's ruling: the coordinator is the fleet's only
  # authenticated operator box — gh + wrangler stay off the laptops).
  "secrets/gh-hosts.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/wrangler-config.age".publicKeys = editors ++ coordinatorOnly;
  # Optional Hugging Face read token. The rule is declared now; ciphertext is
  # created with agenix only when Tom supplies the credential.
  "secrets/huggingface-token.age".publicKeys = editors ++ coordinatorOnly;

  # Qwen Token Plan API key (Alibaba MaaS, ap-southeast-1 — the OpenAI-compatible
  # subscription endpoint pi ships as the built-in `qwen-token-plan` provider).
  # Coordinator-only for the same reason as claude-credentials: it is a metered
  # subscription, not a per-token bill, so every box that can decrypt it can burn
  # the shared 7-day credit pool. The coordinator is the only agent host.
  "secrets/qwencloud-token.age".publicKeys = editors ++ coordinatorOnly;
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
