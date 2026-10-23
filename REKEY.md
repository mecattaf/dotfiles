# Fleet compute credential retirement

No ciphertext was printed, decrypted or changed in this PR. Both compute hosts
have `mySecrets.enable = false`. Their public host keys must not appear in an
agenix recipient tier. The worker host key is deliberately empty until Tom
records the fresh public key generated at install; adding it to the mesh does
not add any recipients.

This branch contracts the former agent tier to the admin editor and the shared
delivery tier to the client. The NAS agent-host PR assigns the new NAS service
recipients. Tom must re-encrypt the affected files against the **combined**
recipient declarations after that PR is ready, retaining the same plaintext.
Do not re-encrypt against this intermediate admin-only agent tier.

Affected files (the old ciphertext still admits the coordinator until rekey):

- `secrets/ssh-user-key.age`
- `secrets/atuin-key.age`
- `secrets/tom-password-hash.age`
- `secrets/atticd-server-token.age`
- `secrets/substrate-floor-token.age`
- `secrets/substrate-link-token-strix.age`
- `secrets/soundcloud-cookies.age`
- `secrets/youtube-music-cookies.age`
- `secrets/navidrome-credentials.age`
- `secrets/immich-api-key.age`
- `secrets/printer-admin.age`
- `secrets/gh-hosts.age`
- `secrets/wrangler-config.age`
- `secrets/cloudflare-api-token.age`
- `secrets/huggingface-token.age` (retains NAS access; drops compute)
- `secrets/qwencloud-token.age`
- `secrets/openrouter-token.age`
- `secrets/codex-auth.age`

The NAS PR's REKEY list is authoritative for new NAS consumers. Compute retains
its host SSH key and the coordinator's existing Tailscale state; neither is an
operator secret delivered by agenix. Removing declarations does not erase
existing home, credentials or model bytes. Retire old state separately after
NAS session continuity and the sealed backup have been verified.
