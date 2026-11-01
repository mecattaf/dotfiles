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
  nonEmpty = builtins.filter (k: k != "");

  # Admin age key (private half in Google Password Manager) — always a recipient so
  # editing works before/after any flash.
  admin = "age159pyyqqnrxwv3d7f758u5xtzv53fu2nwc85x3sur63g3p29jnegq9tf47w";

  # Editing authority is deliberately operator-only. Fleet-delivered SSH user
  # keys must never be recipients: compromise of one host must not unlock Git
  # history or future ciphertext.
  editors = [ admin ];

  # Only NAS (brain) and Zenbook (seat). Neither compute box needs a shared
  # private SSH key or password to admit key-only mesh logins.
  delivered = nonEmpty [
    registry.nas.hostKey
    registry.client.hostKey
  ];
  brainOnly = nonEmpty [ registry.nas.hostKey ];
  clientOnly = nonEmpty [ registry.client.hostKey ];
  nasOnly = nonEmpty [ registry.nas.hostKey ];
  computeTp2 = nonEmpty [
    registry.strix-coordinator.hostKey
    registry.strix-worker.hostKey
  ];
in
{
  # Machine-to-machine Gufo control only; no operator authority.
  "secrets/gufo-tp2-control-token.age".publicKeys = editors ++ computeTp2;
  # Shared login/history credentials: NAS brain and Zenbook seat. Neither
  # compute host receives them; mesh authorized public keys admit SSH logins.
  "secrets/ssh-user-key.age".publicKeys = editors ++ delivered;
  "secrets/atuin-key.age".publicKeys = editors ++ delivered;
  "secrets/tom-password-hash.age".publicKeys = editors ++ delivered;

  # Existing NAS-only optional DNS token and client-only Wi-Fi credential.
  "secrets/nas-cloudflare-dns.age".publicKeys = editors ++ nasOnly;
  "secrets/wifi-lan.age".publicKeys = editors ++ clientOnly;
  "secrets/wifi.age".publicKeys = editors;
  "secrets/vault/operator-vault-20260705.age".publicKeys = editors;

  # Central service/operator credentials follow the brain to the NAS.
  # Attic's live key remains a runbook-placed file; moving this ciphertext's
  # recipients does not replace that key. Substrate is paused: rekey its
  # credentials centrally but do not deliver them or add its units on NAS.
  "secrets/atticd-server-token.age".publicKeys = editors ++ brainOnly;
  "secrets/substrate-floor-token.age".publicKeys = editors ++ brainOnly;
  "secrets/substrate-link-token-strix.age".publicKeys = editors ++ brainOnly;
  "secrets/soundcloud-cookies.age".publicKeys = editors ++ brainOnly;
  "secrets/youtube-music-cookies.age".publicKeys = editors ++ brainOnly;
  "secrets/navidrome-credentials.age".publicKeys = editors ++ brainOnly;
  "secrets/immich-api-key.age".publicKeys = editors ++ brainOnly;
  "secrets/printer-admin.age".publicKeys = editors ++ brainOnly;
  "secrets/gh-hosts.age".publicKeys = editors ++ brainOnly;
  "secrets/wrangler-config.age".publicKeys = editors ++ brainOnly;
  "secrets/cloudflare-api-token.age".publicKeys = editors ++ brainOnly;
  # Only the Library/agent host accesses Hugging Face; compute borrows bytes.
  "secrets/huggingface-token.age".publicKeys = editors ++ brainOnly;
  "secrets/openrouter-token.age".publicKeys = editors ++ brainOnly;
  # Seed once, never overwrite the live Codex OAuth session on activation.
  "secrets/codex-auth.age".publicKeys = editors ++ brainOnly;
}
