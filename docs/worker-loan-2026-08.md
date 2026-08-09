# Worker loan 2026-08-08 → ~2026-08-22: self-contained drain box

The returned worker (same Strix Halo as coordinator) is back for two weeks as a
dedicated, fully self-contained box for the **academic-ocr drain** and
**music-consolidation tier-3**. Both were cut over on 2026-08-08; the
coordinator no longer runs either. The coordinator-side academic drain was
removed declaratively on 2026-08-09; the worker runtime still belongs in the
worker-restoration Nix round.

## What runs on the worker now

| thing | how |
|---|---|
| academic-ocr drain | user unit `academic-drain.service` (enabled), same store build `fj524vhg…-2026-08-06` as coordinator, `Restart=always`/`RestartSec=600` |
| tally daemon | user unit `tally-daemon.service`, fresh state (old pre-retirement state archived at `~/.local/{state,share}/tally.pre-2026-08-08`), same pin `p7zy7fl…tally-0.1.0` + checked config `7c45hx6a…` |
| OCR model serving | system `llama-swap.service` + runtime drop-in → `/var/lib/llama-swap-ocr/config.yaml` (qwen3-vl-8b-ocr, qwen3-vl-32b-ocr, qwen3-embedding-8b; exact coordinator cmd lines; weights nix-copied) |
| corpus | **local copy** `/home/tom/nas-local/documents/academic-papers` (16G, incl. catalog + receipts), bind-mounted at `/mnt/nas` so every hardcoded path in drain-worklist.py/absorb.py hits local disk |
| notes repo | rsynced to `~/mecattaf/notes`; absorb.py only ever **commits** locally — push at loan end |
| music tier-3 | `mc-tier3.service` via `scripts/tier3-run.sh` + **new** `mc-tier3-guard.timer` (15 min; relaunch-if-dead — the guard tier-3 never had, which is why it sat dead on coordinator at 2/1484) |
| tier-3 output | **local** `~/music-staging/_ingest/tier3` (run.sh patched; see below) |
| chrome for capture | Chrome 151 in tom's nix profile (`nix profile add`, GC-rooted) — worker's system chrome is 150 and the tier-3 profile was stamped 151 |
| cookies | `/run/agenix/{soundcloud,youtube-music}-cookies` re-placed at boot from root-only masters in `/root/worker-loan/` |

Verified end-to-end 2026-08-08: worker GPU inference ("WORKER GPU OK" via
qwen3-vl-8b-ocr), drain resumed the in-flight paper on its persisted run-id,
and tier-3 captured a full 213.5 s track, fingerprint-aligned vs the SoundCloud
preview (BER 0.013) — login works headless.

## Worker-local patches (drift vs the repos, on purpose)

1. `~/mecattaf/music-consolidation/scripts/tier3-run.sh` — `OUT` is now
   `${TIER3_OUT:-/home/tom/music-staging/_ingest/tier3}` (was hardcoded
   `/mnt/nas/…`). Self-containment: no NAS write at runtime.
2. `~/mecattaf/music-consolidation/scripts/tier3-capture.py` — chrome launch
   gained `--password-store=basic`. **Root cause of the capture hang**: on a
   headless session Chrome's UI thread blocks ≥60 s per Secret-Service DBus
   call (no unlockable keyring), so every CDP call timed out. Coordinator never
   saw this because its desktop keyring is unlocked at login. Worth upstreaming
   into the repo as an unconditional flag — cookies are injected per-run, the
   keyring buys nothing.

## Networking (TB5-first, per ruling)

- `tb-fleet` NM profiles both ends: coordinator `10.99.0.1/30` ↔ worker
  `10.99.0.2/30`; worker routes `10.77.0.0/30` via coordinator.
- Coordinator runtime unit `worker-nas-gateway.service` (`/run/systemd/system`,
  `PartOf=firewall.service`) SNATs worker→NAS to `10.77.0.1`. Only needed for
  bulk copies / merge-back — **runtime NFS is gone** (bind mount is local).
- Worker firewall: runtime `iptables -I nixos-fw -i thunderbolt0 -s 10.99.0.1 -j ACCEPT`.
- Coordinator's rotated pubkey (`tom@mesh-20260729`) appended to worker
  `~/.ssh/authorized_keys` — plain sshd over TB now works (tailscale SSH only
  intercepts on tailscale0).
- `worker-status` on coordinator (`~/.local/bin`) — one-shot status over TB,
  tailscale fallback.

## Reboot self-healing on the worker

Persistent things (user units, nix profile, state, `/var/lib` config) survive
on their own. The `/run` pieces are re-asserted at boot by
`worker-reassert.service` (user oneshot → `sudo -n /root/worker-loan/reassert.sh`):
firewall hole, cookies into `/run/agenix`, `mnt-nas.mount` bind, llama-swap
drop-in. `loginctl enable-linger tom` is set. Coordinator-side: only
`worker-nas-gateway.service` is runtime; re-create if the coordinator reboots
before the nix round lands (or just don't — nothing needs it day-to-day).

## Coordinator-side cutover state (watch the next HM switch)

- `academic-drain-stop` ran clean; backfill-tables driver stopped and its flow
  run cancelled (state `needs-attention`, zero tally jobs — per #145 the
  cancel is not OCR evidence; the affected papers keep receipts).
- `academic-drain.service`, its coordinator package, Tally pool, and registered
  flow were removed from the coordinator's declarative Home Manager profile on
  2026-08-09. Future switches and boots do not restore it. The monthly tier-2
  guard was transient and is also gone.
- Coordinator's academic state stayed in place (23G) as a pre-cutover snapshot;
  the worker's copy is authoritative from 2026-08-08 09:26.

## For the nix round (declarative twins wanted)

- `hosts/worker` restoration: TB static IP + NAS-route, firewall accept on
  thunderbolt0 from 10.99.0.1, bind mount `/mnt/nas` ← `/home/tom/nas-local`,
  llama-swap OCR roster (lib/local-models.nix hosts enum currently allows only
  `"coordinator"`), tally daemon + academic-drain user units on worker,
  mc-tier3 guard, cookies secrets re-keyed to worker (`secrets.nix` dropped the
  worker identities at retirement — the runtime cookie copies bypass agenix),
  `Host worker → 10.99.0.2` in home ssh config (home-manager owns the file).
- Known gap: `gpu-cooldown-tripwire.timer` on the worker still implements the
  central-executor design (asks *coordinator* to enqueue a hold) — a no-op now.
  If it should protect the 24/7 OCR load it must target the worker's own tally
  daemon. Hardware throttling is the only guard meanwhile (62 °C edge under
  load today, plenty of headroom).

## Merge-back at loan end (~2026-08-22)

1. Stop both drains on worker (`academic-drain-stop`; `systemctl --user stop
   mc-tier3.service mc-tier3-guard.timer`).
2. Music: `rsync -a ~/music-staging/_ingest/tier3/ /mnt/nas/music-staging/_ingest/tier3/`
   (real NAS via coordinator gateway, or from coordinator pulling over TB).
3. Academic: worker's `/home/tom/nas-local/documents/academic-papers/` (catalog
   sqlite + receipts changed) → NAS `documents/academic-papers/`; worker's
   `~/.local/state/academic-ocr` → wherever the drain lives next.
4. Notes: `git -C ~/mecattaf/notes push` (worker's clone holds the absorb
   commits; or rsync the repo back and push from coordinator).
5. Cookies masters in `/root/worker-loan/` — shred before returning the box:
   `shred -u /root/worker-loan/*-cookies`.
