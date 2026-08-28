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
  # sets `mySecrets.enable = false` ("NO SECRET LIVES ON THIS BOX"), so the appliance is delivered nothing and must not
  # hold standing decryption authority over ciphertext it never reads (2026-08-04
  # ruling — it had been a recipient of the whole common tier, including tom's
  # password hash and the fleet SSH private key). If the nas ever flips
  # mySecrets.enable on (ws5 attic is the likely trigger — hosts/nas/attic.nix),
  # add its key back here for the specific secrets it consumes, not wholesale.
  #
  # DERIVED, not enumerated — which is why the worker's 2026-08-21 reintegration
  # (#229) needed no edit here: adding its row to the registry put it in this
  # tier automatically. What that does NOT do is rewrite the ciphertexts, which
  # are encrypted to a fixed recipient list at mint time. Every delivered-tier
  # secret was re-minted in that same commit (`age -R` over this list) so the
  # box can actually decrypt what this file says it may decrypt. Adding a host
  # here without re-minting yields a config that evaluates and an activation
  # that fails.
  delivered = nonEmpty (map (h: registry.${h}.hostKey) (builtins.filter (h: h != "nas") names));

  laptops = nonEmpty [
    registry.zenbook-duo.hostKey
  ];
  coordinatorOnly = nonEmpty [ registry.coordinator.hostKey ];
  # The reintegrated worker (#229, 2026-08-21). It joins the `delivered` tier
  # automatically above — that list is derived from the registry, so its row
  # landing was enough — but wifi credentials are their own tier and have to say
  # so explicitly.
  workerOnly = nonEmpty [ registry.worker.hostKey ];
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
  # BE550 repeated-LAN credentials ($BE550_SSID / $BE550_PSK) — the
  # thomas-6ghz profile on the coordinator (hosts/coordinator/uplink-nas.nix),
  # the zenbook (its AdGuard-DoH landmine was defused the same day the laptops
  # tier joined, 2026-08-21), AND the worker since its reintegration later that
  # day (#229). Every host that joins `thomas-6ghz` needs it, and for the worker
  # it is the only path onto the house LAN at all — no Freebox fallback profile,
  # no tailnet behind it. Re-minted with all three recipients.
  #
  # NB this is now the same recipient set as the delivered tier, but it is
  # deliberately still written out rather than reusing `delivered`: the two mean
  # different things (one is "every agenix host", the other is "every host that
  # associates to this SSID") and they will diverge again the moment a host
  # exists that runs agenix but is not on this wifi.
  "secrets/wifi-lan.age".publicKeys = editors ++ coordinatorOnly ++ laptops ++ workerOnly;

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
  # Hugging Face read token. Provisioned 2026-08-28 (fine-grained, HF display
  # name `nixOS`) after carrying a declaration with no ciphertext since the
  # declarative CLI landed — `builtins.pathExists` meant the coordinator simply
  # evaluated the delivery to nothing and `hf` ran unauthenticated.
  #
  # The nas joined the recipients the same day, and it is the ONLY secret the
  # appliance can decrypt. The consumer is not interactive `hf`: it is
  # hosts/nas/models.nix's library-fetch, the service its own header calls "the
  # ONLY thing that ever talks to Hugging Face", which curls catalog weights
  # anonymously and therefore 401s on anything gated. Coordinator keeps it for
  # the CLI.
  "secrets/huggingface-token.age".publicKeys = editors ++ coordinatorOnly ++ nasOnly;

  # Qwen Token Plan API key (Alibaba MaaS, ap-southeast-1 — the OpenAI-compatible
  # subscription endpoint pi ships as the built-in `qwen-token-plan` provider).
  # Coordinator-only for the same reason as claude-credentials: it is a metered
  # subscription, not a per-token bill, so every box that can decrypt it can burn
  # the shared 7-day credit pool. The coordinator is the only agent host.
  "secrets/qwencloud-token.age".publicKeys = editors ++ coordinatorOnly;
  # gws (Google Workspace CLI, personal account thomasmecattaf@gmail.com) — same
  # operator-box ruling as gh/wrangler above. client_secret identifies the OAuth
  # app; credentials.enc + .encryption_key + token_cache.json are the actual
  # logged-in state (see ~/.config/gws/HANDOFF.md for full provenance, 2026-07-10).
  "secrets/gws-client-secret.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/gws-credentials.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/gws-encryption-key.age".publicKeys = editors ++ coordinatorOnly;
  "secrets/gws-token-cache.age".publicKeys = editors ++ coordinatorOnly;
}
