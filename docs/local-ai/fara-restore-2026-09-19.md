# Bringing FARA 9B back, and the fp8 / bf16 question

Tom, 2026-09-19, evening: "FARA 9b should BE BROUGHT BACK, perhaps at fp8 if
not bf16; this has avenue to be optimized. should be easy to retrieve and
apply."

This file records what the restore actually restores, and answers the
precision half of the ruling with numbers rather than a preference.

## What was retired, exactly

FARA 1.5 was cut on 2026-09-16 in commit `006396ea`, the same commit that put
both Halogen engines on both twins. The FARA half of that commit removed:

| Thing | Path |
|---|---|
| The on-demand model unit | `modules/fara-browser-model.nix` |
| The reference CLI | `pkgs/fara-cli.nix` and `pkgs/browserbase.nix` |
| The agent loop | `pkgs/browser-desktop/harness.py`, `replay.html`, the `/control` Caddy route, the sidebar control status and Take control |
| The house skill | `home/dot_claude/skills/fara-browser/SKILL.md` |
| The catalogue rows | `fara15-9b-q8-0`, `fara15-9b-mmproj-bf16` in `lib/local-models.nix` |
| The wanted-set rows | `modules/strix.nix`, coordinator branch |
| The fleet-status role | `fara` in `modules/fleet-status.nix` and `pkgs/fleet-status` |
| The flake assertions | the unit, the roles list, the wanted set, the catalogue names |

The 4B and the 27B rows had already left the catalogue on 2026-09-11; only the
9B pair was live at the end.

## The bytes are gone from the Library

MEASURED, `/mnt/nas/models/weights/RETIRED-2026-09-16.tsv`:

| id | bytes | GiB |
|---|---|---|
| `fara15-9b-q8-0` | 9,545,983,104 | 8.89 |
| `fara15-9b-mmproj-bf16` | 921,704,992 | 0.86 |
| `fara15-4b-q8-0` | 4,493,954,144 | 4.19 |
| `fara15-4b-mmproj-bf16` | 675,569,312 | 0.63 |
| `fara15-27b-q8-0` | 28,665,067,328 | 26.70 |
| `fara15-27b-mmproj-bf16` | 931,146,400 | 0.87 |

MEASURED: `/mnt/nas/models/weights/` holds no `fara*` directory today, and
`/var/lib/local-models/` on the coordinator holds none either. So the restore
is not only declarative: `library-fetch` has to re-download the two 9B files
from `bartowski/Fara1.5-9B-GGUF@153cb27` (the revision the catalogue always
pinned, with its sha256), then `local-models-borrow` loans them onto the
coordinator. Upstream is a public Hugging Face repo, so the row is restorable
exactly as `docs/nas/model-archive.md` promises. Nothing here is lost.

## fp8, bf16 or Q8_0

The engine decides this, not taste.

**What can serve FARA on this fleet.** One thing: `llama-server` from
`nix-strix-halo`'s `llama-cpp-rocm`, which is what the retired unit used. It
reads GGUF. Halogen is the fleet's other engine and it reads only `.hgn`
bundles built by Peonist; no FARA `.hgn` exists. The vLLM fork, flashnext and
flashnix are defunct projects and are named OUT in `AGENTS.md` and in
`DECISIONS.md` twice (2026-09-11, 2026-09-16), `flashnext-fp8` and
`qwen38-flash-next-fp8` explicitly.

**So FP8 has no engine here today.** FP8 is a tensor format for vLLM/TensorRT
style servers with FP8 matmul kernels. llama.cpp has no FP8 GGUF type, and
gfx1151 (Strix Halo) has no FP8 matrix path to use one. Reaching FP8 means
bringing back a vLLM-class server, which is the thing Tom ruled out twice.
That is a real decision with a real cost, not a flag.

**The sizes, so the choice is concrete.** Q8_0 measures 8.5 bits per weight
across the three FARA rows above (INFERRED from the byte counts: 9.55 GB for
the 9B, 4.49 GB for the 4B, 28.67 GB for the 27B). At that ratio:

| Precision | Weights, 9B | vs Q8_0 | Engine on this fleet |
|---|---|---|---|
| Q8_0 GGUF | 8.89 GiB (MEASURED) | — | yes, `llama-cpp-rocm` |
| FP8 | ~8.4 GiB (INFERRED) | about 0.5 GiB smaller | **none** |
| BF16 GGUF | ~16.7 GiB (INFERRED) | about 7.8 GiB larger | yes, `llama-cpp-rocm`, slower |

FP8 is not an upgrade over Q8_0 in either footprint or quality: both are eight
to eight-and-a-half bits per weight. It would only be a *speed* play, and only
on an engine with FP8 kernels, which is not this one. BF16 is the only real
precision step up, it doubles the footprint, and on gfx1151 llama.cpp's BF16
path is slower than Q8_0 because the Q8_0 kernels are the tuned ones.

**The vision projector is already BF16.** `fara15-9b-mmproj-bf16` is full
precision, and for a screenshot-driven computer-use agent the projector is
where precision is felt. That was the original design, not an accident: the
catalogue note reads "Q8_0 is an explicit operator choice for the mid-tier
browser-computer-use appliance; do not silently down-quantize it."

**Headroom is not the constraint.** MEASURED on the coordinator, 2026-09-19
evening: GTT total 134,309,523,456 B (125.08 GiB), GTT used 6,445,150,208 B
(6.00 GiB), VRAM carveout 536,870,912 B (512 MiB), MemTotal 125.08 GiB,
MemAvailable 99.06 GiB. `amdgpu.gttsize=126976` is still NOT on
`/proc/cmdline`, so the box has not rebooted since 2026-09-16; it does not
matter, because GTT already measures 125 GiB. Either precision fits. What does
not fit is FARA *plus* a coordinator Halogen engine: upstream sizes Flash as
leaving roughly 12 GB free on a 128 GB box, and this machine also carries Qwen
TTS, Parakeet, the 17.6 GB streaming ASR and Tom's live agent sessions.

**What this branch does.** It restores the Q8_0 row unchanged, byte-identical
to what the catalogue carried, because a BF16 row needs a real file path,
byte count and sha256 from the upstream repo and no one has fetched it. Hashes
are not to be invented. If Tom wants BF16, the change is one catalogue row and
one `--model` path, and it is a five-minute edit once someone has run
`library-fetch` against the BF16 file and read back its hash.

## How it runs

Operator-started, never resident. `modules/fara-browser-model.nix` declares
`wantedBy = [ ]` and `flake.nix` asserts it, which is the same rule as
`services.halogen.autoStart = false` on this box: the GPU belongs to Tom's
desktop, and an agent takes it for the length of one task.

```
fara-browser profiles
fara-browser status
fara-browser run --profile 'Profile 2' --task-file /path/to/task.txt
```

Do not start FARA while a coordinator Halogen unit is active
(`halogen-switch off` first). `fleet-status` reports the unit again under
`inference.fara_browser_model`, and the coordinator's update-adopt gate
refuses a switch while the unit is up.
