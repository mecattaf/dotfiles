# ds4-vllm recon — 2026-08-21 (pre-flight, nothing executed)

Deep read of `github.com/AlexKGwyn/ds4-vllm` (cloned at `~/Downloads/ds4-vllm`,
commit `a8f620d`), done the night of the CCGx PD-wedge incident and BEFORE any
of it runs on the fleet. Companion doctrine: `hosts/coordinator/tb-fleet.nix`
(the wedge + cure) and `hosts/coordinator/eth-fleet.nix` (the rail this project
made necessary). Full agent report lives in the session transcript; this is the
operative distillation.

## What it is

A rebuild kit for a hand-patched vLLM serving **DeepSeek-V4-Flash-0731**
(BF16, ~167 GB, catalog row `deepseek-v4-flash-0731-bf16` — already stocked in
the NAS Library) **TP=2 across exactly our two boxes**, decode all-reduce over
RDMA on the Thunderbolt cable. Box1 = Ray head + rank 0, box2 driven entirely
over ssh. One OpenAI API on box1:1234. Claimed ~300 tok/s prefill / 23-32
decode at 512 ctx on the reference rig.

Three layers, very different risk profiles:

- `container/` — podman image (pinned digest, vLLM `470229c`, ROCm 7 inside)
  + 31-file patch. **Ports to NixOS essentially free** (all dnf work is inside
  the image; host never gets ROCm).
- `host/` — bash orchestration + one systemd *user* unit. Light porting,
  `$HOME`-relative, fine as-is.
- `tbv/` — the dangerous layer: **replaces the kernel Thunderbolt modules
  wholesale.** Patched core (westeri `503c5ae1`, 7.1-rc1 base) + patched
  tbnet + out-of-tree `thunderbolt_ibverbs.ko` (hellas-ai `76ba39b` + local
  3453-line patch) + `nhi_throttle.ko` (raw MMIO pokes into every NHI's BAR0
  behind the driver's back). Stock `thunderbolt` blacklisted from initramfs;
  patched core hand-inserted after /var mounts; `ucsi_acpi` + typec force-
  loaded late, out of ACPI enumeration order.

## The four rulings that must survive until execution day

1. **First bring-up uses `transport: tcp`** (`ds4-config.yaml`; AGENTS.md §1.5
   is the author's own off-ramp). Zero changes to the Thunderbolt stack: no
   blacklist, no patched core, no coordinated reboots. Validates the container
   build, Ray across boxes, the model path and disk-KV tier on NixOS — 90% of
   the project — before touching the layer whose documented recovery is "reboot
   both boxes." Decode will be slow. That is the point.
2. **When the tbv layer happens, it happens via the upstream flake, not
   `tbv/install-modules.sh`.** hellas-ai/thunderbolt-ibverbs ships first-class
   NixOS support: `nixosModules.default`, `hardware.thunderbolt-ibverbs.enable`,
   a `linux-thunderbolt` kernel package at the right pin, and a boot-closure
   guard against exactly the vermagic drift ds4-vllm's imperative
   `~/.cache/tbv-build` path suffers from (every kernel bump silently drops
   RDMA → TCP with no alarm). Re-apply `tbv/ibverbs-local.patch` as an overlay
   only if the zero-copy fastpath is wanted. `install-modules.sh` writes
   /etc/modprobe.d, calls grubby, cp's units — NixOS fights or reverts all of
   it.
3. **ssh between the boxes moves to the eth-fleet rail before tbv day.**
   The project has no concept of a second network: interconnect, Ray, ssh and
   the ar2 rendezvous all die together when thunderbolt0 does — and its own
   README says the common wedge is recoverable "only by rebooting both boxes."
   Split `worker_ip` into a `worker_ssh_ip` (config loader auto-exports any
   YAML key as `DS4_<KEY>`). Keep NCCL/GLOO/RDMA on thunderbolt0 — the RoCE
   GID derives from its IP. Leave Ray on TB initially.
4. **Coordinated dual reboots are the project's routine — and the exact event
   class that wedged both CCGx PD controllers tonight.** The countermeasures
   already deployed (tb-link-heal's PD-blind rung with `framework_tool
   --pd-reset 2`; the eth rail) are load-bearing prerequisites, not nice-to-
   haves. If a dual reboot wedges PD again: the heal loop now fixes it within
   ~2 min per box, unattended.

## Known traps (all from the repo's own contents)

- `tbv_ar.py:20` / `tbv_ar2.py:19` hardcode `BOX1_IP = "192.168.100.1"` and
  the cuda_communicator hook passes no peer IP. **Must be edited to 10.99.0.1
  in `container/rootfs/` before building**, or the ar2 TCP rendezvous
  (ports 18515/18531) never connects. `tbv-roce-boot.sh:16` also greps for
  `192.168.100.` — non-fatal, but adds a 240 s timeout to every boot; patch it
  too.
- `DS4_TBV_AR=1` (v1) is dead code by the source's own comments ("currently
  inert… never measured on this stack"). Only `DS4_TBV_AR2` matters; the RDMA
  win is the ~48 KiB decode collective only (`TBV2_MAX_BYTES` = 1 MiB cap);
  prefill falls through to host-staged RCCL.
- `ds4-cluster-env*.sh` differing by one byte between boxes → "the two TP
  ranks silently diverge" (stated twice upstream). Checksum them; on NixOS,
  derive both from one source.
- Image built without `distributed.py` → disk-KV restores WRONG KV on rank 1
  (0/8 needle recall at 100% reported hits). The manual-serve script guards
  this; keep the guard.
- Silent RDMA→TCP fallback alarm string: journal grep `tbv_ar2: rank[0-9]
  ready`; absence after bring-up = running slow. Tripwire candidate on
  execution day.
- `bolt.service` ordering: the tbv unit assumes boltd exists; check
  `services.hardware.bolt` posture before enabling.
- Secure Boot must be off (unsigned modules) — verify before tbv day.
- With `cables: 1` the RX zero-copy rail auto-disables (ring pressure vs
  tbnet); `cables: 2` needs a second TB cable + prep script on both boxes.
  Not tonight's problem.
- Repo references files that don't exist (`tbv/build-scripts/`,
  `verify-tbv-perf.sh`, `tests/test_fs_lru_tier.py`) — the scripts were lifted
  from the author's live box. README perf claims contradict in-source comments.
  AI-authored by the author's own admission, 6 days of history, ~10 stars, one
  external contributor, **zero issue-tracker corpus** (hellas-ai upstream: zero
  issues ever, functionally frozen since 2026-07-01; PRs #71 and #52 there are
  worth a look). Expect undocumented hazards.

## Weights status

`deepseek-v4-flash-0731-bf16` was already a catalog artifact (roster row in
`lib/local-models.nix`, ACTION-PLAN §5) and the NAS Library is the only place
it materializes for now — per Tom's 2026-08-21 ruling, NOT on coordinator or
worker ("REQUIRED IN FULL ON EACH BOX" per the artifact note is deliberately
deferred until per-box disk rulings). library-fetch completed the remaining
shards the night of this recon; verify with
`ls /mnt/nas/models/weights/deepseek-v4-flash-0731-bf16 | wc -l` → 52 files.
