# NAS credentials and fresh compute identities

The migration ciphertexts are re-encrypted and verified as of 23 October 2026.
This tree contains the completed recipient change. Deployment and actual NAS
credential delivery remain separate steps.

## Completed operator recipient change

All 18 operator ciphertexts retain Tom's admin recovery recipient. Their final
host recipients are:

| Ciphertext | Host recipients, in addition to admin |
| --- | --- |
| `ssh-user-key`, `atuin-key`, `tom-password-hash` | NAS and Zenbook |
| `atticd-server-token`, `substrate-floor-token`, `substrate-link-token-strix` | NAS |
| `soundcloud-cookies`, `youtube-music-cookies`, `navidrome-credentials` | NAS |
| `immich-api-key`, `printer-admin`, `gh-hosts`, `wrangler-config` | NAS |
| `cloudflare-api-token`, `qwencloud-token`, `openrouter-token` | NAS |
| `codex-auth`, `huggingface-token` | NAS |

The previous Strix SSH **host** identity was already an authorized decryption
recipient. It was used once to decrypt and re-encrypt directly through memory.
NAS-side decryption was verified privately for every result. No delivered SSH
user key was used as an editor identity; no plaintext credential, plaintext
digest or private key was printed or written to a temporary file. Tom's admin
private key was not needed or retrieved.

Both compute hosts have fresh public SSH host identities in
`modules/mesh-registry.nix`. Private extra-files installation trees remain
outside Git in protected fleet-move staging. Install each fresh key only on its
named host. Preserve old keys in protected recovery, and do not restore the old
operator-capable coordinator identity onto fresh compute.

## QwenCloud retirement (2026-11-01)

Tom initiated account closure and requested removal of the saved key. The
QwenCloud ciphertext, recipient entry and agenix delivery are removed. The
older table above records the completed October migration, not an active
QwenCloud credential. Historical sessions and usage receipts remain.

## Compute service credential

`secrets/gufo-tp2-control-token.age` now exists: one random scoped Gufo control
token encrypted only to admin and the two fresh compute host keys. Both private
host identities decrypted it successfully. It grants no operator, GitHub,
Cloudflare, Claude or Codex authority.

Delivery uses root-only agenix credentials. Upstream accepts the value in argv,
so a running TP2 process exposes it in process arguments; keep this token limited
to Gufo control. Hardware qualification and model staging remain required.

## Handover

- Stage tested, merged source and needed closures on NAS before compute install.
  Verify actual NAS secret delivery after activation.
- Preserve both Claude seats and shared settings. Claude OAuth has no agenix
  seed. Live Codex/GitHub/Wrangler auth wins over stale seed-once files; never
  overwrite a refreshed live credential.
- Take a final capture with harness writers quiescent. Initial online database
  captures are preservation copies, not an atomic final handover.
- Substrate stays paused. Its rekey provides central escrow; it does not enable
  a runner or finish the DSH runner contract.
- Keep coordinator Chrome per Tom's latest instruction. Preserve its profiles
  and encrypted NAS/admin keyring recovery escrow before firmware changes. A
  board-bound TPM blob alone cannot recover after a fresh install or PCR change.
- Future edits can use the admin recovery identity with `secrets.nix`. Optional
  DNS, Wi-Fi and operator-vault ciphertexts are unchanged.

Recipient changes do not revoke old plaintext or archived ciphertext. Protect
that archive and install fresh compute keys and declared roles, without copying
the old home back wholesale.
