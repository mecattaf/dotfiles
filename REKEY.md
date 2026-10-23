# NAS central credentials: Tom's rekey step

Part of #600 and the fleet cutover umbrella #597. This branch changes public
recipient lists only. No ciphertext was printed, decrypted or re-encrypted.

No ciphertext was printed, decrypted or changed in this PR. Both compute hosts
have `mySecrets.enable = false`. Their public host keys must not appear in an
operator-secret recipient tier. The worker host key is deliberately empty until
Tom records the fresh public key generated at install. Adding it grants access
only to the new TP2 service token below, never to the operator tier.

## New compute service credential

Tom must create `secrets/gufo-tp2-control-token.age` with the same random,
single-line token for both compute hosts. Record the worker's fresh SSH host
public key in `modules/mesh-registry.nix` first, then encrypt to the admin editor
and **only** the two compute host keys declared for this secret in `secrets.nix`.
Do not create an admin/coordinator-only ciphertext while the worker key is empty.
This specific service token is the sole compute recipient exception; it grants
no operator/API authority and does not enable `mySecrets`.

The ciphertext is deliberately absent here. Once Tom creates and commits it,
the compute profile declares root-only agenix delivery independently of the
operator tier. Until then `gufo-tp2.service` refuses to start because its
`LoadCredential` source `/run/agenix/gufo-tp2-control-token` is absent. Its
wrapper reads the credential at runtime; upstream accepts the value only in
argv, so it remains visible in `/proc/<pid>/cmdline`.

## Operator credential retirement

Merge together with the strix-coordinator/strix-worker PR; never deploy strix
from a main that has this PR but not that one. The coordinator keeps its
current brain generation for its first unplug/boot, through the worker and NAS
unplugs. Its compute-only generation waits for the NAS-home handover and a
later plain reboot. This document authorizes no deployment or reboot.

The admin recovery recipient stays on every secret. All 18 files below lose
strix's host recipient. The first three gain NAS and retain client; the next
14 gain NAS; Hugging Face already had NAS and now loses strix. Neither compute
host receives shared secrets. Login needs only mesh authorized public keys,
so strix-coordinator is not retained in the delivered tier. Existing home
copies remain until the supervised cutover; changing recipients does not
revoke old plaintext or historical ciphertext.

| File | Host recipients after rekey (plus admin) |
| --- | --- |
| `secrets/ssh-user-key.age` | nas, client |
| `secrets/atuin-key.age` | nas, client |
| `secrets/tom-password-hash.age` | nas, client |
| `secrets/atticd-server-token.age` | nas |
| `secrets/substrate-floor-token.age` | nas |
| `secrets/substrate-link-token-strix.age` | nas |
| `secrets/soundcloud-cookies.age` | nas |
| `secrets/youtube-music-cookies.age` | nas |
| `secrets/navidrome-credentials.age` | nas |
| `secrets/immich-api-key.age` | nas |
| `secrets/printer-admin.age` | nas |
| `secrets/gh-hosts.age` | nas |
| `secrets/wrangler-config.age` | nas |
| `secrets/cloudflare-api-token.age` | nas |
| `secrets/qwencloud-token.age` | nas |
| `secrets/openrouter-token.age` | nas |
| `secrets/codex-auth.age` | nas |
| `secrets/huggingface-token.age` | nas |

Run from the reviewed combined cutover checkout on strix, with Tom's recovery
age identity saved in a mode-0600 file outside the repository. Replace the
identity path below. Do not use a delivered SSH private key as the identity.
The pinned agenix CLI's `EDITOR=:` mode re-encrypts without opening an editor
or printing plaintext. Running it per file limits the operation to these 18
files and avoids the absent optional NAS DNS ciphertext in the full ruleset.

```sh
nix develop -c bash <<'SH'
set -euo pipefail
admin_identity=/absolute/path/to/toms-admin.agekey
for secret in \
  ssh-user-key atuin-key tom-password-hash \
  atticd-server-token substrate-floor-token substrate-link-token-strix \
  soundcloud-cookies youtube-music-cookies navidrome-credentials \
  immich-api-key printer-admin gh-hosts wrangler-config cloudflare-api-token \
  qwencloud-token openrouter-token codex-auth huggingface-token
do
  test -f "secrets/$secret.age"
  EDITOR=: agenix --identity "$admin_identity" --edit "secrets/$secret.age"
done
SH
```

Review filenames only with `git diff --name-only -- secrets/`, then commit the
18 re-encrypted files. Do this before any NAS activation; otherwise the new
secret declarations cannot decrypt their old ciphertext. Do not seed Claude
OAuth through agenix: preserve both seat directories and use hand `/login`s
when needed. The copied live Codex auth wins over its seed-once ciphertext.
Substrate's recipient changes are escrow only: no Substrate service or
credential delivery is added to NAS. Attic retains its existing live signing
key and state. Wi-Fi, the optional NAS DNS token and operator vault recipient
lists do not change.
