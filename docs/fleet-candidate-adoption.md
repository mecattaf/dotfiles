# Publishing a fleet candidate by hand, and reading an endpoint's answer

Written 2026-09-16 for #354 (the four items left on its 2026-09-14 status
comment). The nightly path needs no operator: `update-center` on the NAS
resolves `main` once, builds each enrolled host, pushes to Attic and publishes
a signed per-host manifest, and each endpoint's `update-adopt` timers stage and
(on the rolling policy) activate it. This page is for the two times an operator
is in the loop — publishing a closure built somewhere else, and reading
`update-adopt status` — and for the one flag in that path that looks like a
safety bypass and is not.

The Nix files that decide the behaviour here are `hosts/nas/update-center.nix`
(with its body in `hosts/nas/update-center.sh`) and `modules/update-adopt.nix`
(body in `modules/update-adopt.py`).

## Publishing a closure the NAS did not build

The NAS publishes only what is already in its own store and already in Attic:
`update-center --publish-only HOST STORE_PATH FLAKEREF` refuses a path that is
not valid locally, and publishes no pointer unless `attic push` succeeds
first. So a closure built on the coordinator has to be copied to the NAS first:

```sh
# on the coordinator, as tom
nix copy --to ssh-ng://root@nas --no-check-sigs /nix/store/<hash>-nixos-system-worker-<ver>
# on the NAS, as root
update-center --publish-only worker /nix/store/<hash>-nixos-system-worker-<ver> \
  github:mecattaf/dotfiles/<40-char rev>
```

### Why `--no-check-sigs` belongs on that line

A path you just built is unsigned. Nothing signs a local build: signatures are
added by a cache when it serves the path, so `attic push` signs with the
`fleet:` key on the way into the cache and nothing signs it on the way into the
NAS's store. The receiving daemon enforces `require-sigs` unless the client
asks it not to, so the copy above fails with *"cannot add path … because it
lacks a signature by a trusted key"* until `--no-check-sigs` is passed.

The flag is honoured only for a trusted user — `trusted-users = [ "root"
"@wheel" ]` in `modules/common.nix` — which is what makes it work as root to
the NAS and what makes it useless to anyone else.

It is legitimate here for one reason: **the trust in this transfer comes from
the transport and from who built the bytes, not from a signature.** You built
the closure on a fleet host, and you are handing it over an authenticated SSH
channel to a store you administer. A signature would only re-prove a fact you
already have.

It is **not** legitimate anywhere the signature is the only evidence:

- never on an endpoint substituting from a cache. `http://nas:8080/fleet` is
  trusted by its public key (`extra-trusted-public-keys` in
  `modules/common.nix`), and that key is the whole proof that the bytes are the
  ones the NAS built;
- never to silence a signature error whose cause you have not found. An
  unsigned path from a cache is a broken cache or a wrong key, and copying it
  anyway hides that;
- never in a unit or a timer, and never as a habit on `nix copy`. The seed
  timer in `home/update-center-seed.nix` copies the lock's private source trees
  to the NAS nightly and does *not* pass it: those paths are narHash-addressed,
  so their own hash is the proof and no signature is wanted. A path that needs
  the flag is a path whose only possible proof is who you are.

Adoption's own trust is separate from all of this and is not weakened by the
flag: the endpoint verifies the manifest's `ssh-keygen -Y` signature in the
`fleet-update` namespace against an allowed-signers file holding the NAS's host
key from `modules/mesh-registry.nix` (rendered into the store by
`modules/update-adopt.nix`), checks
that `store_path` names *this* host's system closure, and re-reads the
revision from the closure's own `fleet-revision.json` rather than trusting the
manifest's copy of it.

## Reading `update-adopt status`

Two answers that used to read as "fine" now say what they are.

**`status` as tom exits 1.** The state directory is `/var/lib/update-adopt`,
mode 0700 root. A run that cannot read it prints the facts it can still see
(`current`, `booted`, `profile` and the running generation's revision), sets
`state_unreadable` to the reason, leaves `state`, `candidate`, `last_refusal`,
`last_known_good` and `pending_reboot` at `null`, and exits 1. It no longer
prints `"state": "idle"` for a host it never looked at. Run it under `sudo`.
`fleet-status` collects every host, the coordinator included, as root over ssh
for exactly this reason (`modules/fleet-status.nix`); if it ever runs the verb
as a non-root user it grades the answer `unknown`, not "up to date".

**A 404 manifest is `no-candidate`, not `fetch-failed`.** Both still exit 0 —
neither is this host's failure — but they are different facts and the journal
now names them differently:

| Journal line | What happened | What to do |
|---|---|---|
| `reason=no-candidate` | The NAS answered, with 404: it has published nothing for this host. Normal for a host that is not enrolled, and for any host before the first successful nightly | Check `update-center` on the NAS, not the endpoint |
| `reason=fetch-failed` | No HTTP answer at all: the NAS is down, or off the mesh from here | Check reachability |

Read them with
`journalctl -t update-adopt -o cat` (the identifier is set by the script, so a
unit glob is not needed), or from the last refusal in `sudo update-adopt
status --json`.
