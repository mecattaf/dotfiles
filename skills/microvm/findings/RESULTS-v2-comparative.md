# RESULTS — Opus Verifier 2 (Comparative Diff lens)

**Method.** Independent read-only audit. `bash -n` on all three files (all CLEAN). Diffed
`sandbox.sonnet.sh` against `sandbox.sh` (Opus) and `findings/build/sandbox.draft.sh` (baseline),
keyed on each of the 25 STAGE4 findings, with special attention to lint-clean silent divergences.
Did not consult the other verifier.

Line counts: draft 1566 → Sonnet 1682 → Opus 1844. Opus added ~160 more lines than Sonnet,
almost entirely in cluster B (doctor in-guest probes + grounded comments) — the structural tell.

---

## Per-cluster diff characterization + rating

### Cluster A — gen_id (#1, #21). RATING: CORRECT (≡ Opus)
`diff` shows Sonnet line 247 and Opus line 247 are **byte-identical**:
`gen_id() { head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c 10; }` — the dictated
bounded-source fix. SIGPIPE-under-pipefail blocker resolved. No divergence from Opus or the
prescription. As predicted (P≈0.95), indistinguishable.

### Cluster B — krun blockers (#2,#3,#4,#12). RATING: WRONG — three silent fail-opens shipped
This is the entire experiment. Sonnet left cluster B essentially **untouched from the baseline draft**:

- **#2 annotation key prefix — NOT FIXED.** Sonnet 594–595 still emit
  `run.oci.krun.cpus=` / `run.oci.krun.ram_mib=` — identical to the draft. Opus 741–742 emit the
  **bare** `krun.cpus=` / `krun.ram_mib=` with a source-grounded comment ("find_string_map_value,
  no prefix stripping"). The prescription (punch-list #2, and appendix #134-137) dictates the bare
  key. → cpus/ram caps remain a silent no-op; a big host still gets up to 16 vCPU / 1024 MiB.
- **#3 krun.use_passt — NOT FIXED.** `grep -c use_passt sandbox.sonnet.sh` = **0**. Sonnet's
  loopback branch (992–1001) emits `--network pasta` + `--publish 127.0.0.1:…` and no annotation —
  identical to the draft. Opus loopback (1143–1144) appends `--annotation krun.use_passt=1` plus a
  TSI-incompatibility caveat. → guest gets NO NIC; loopback/--publish are metadata-only.
- **#4 doctor in-guest probe — NOT FIXED.** Sonnet's probe set is the draft's 7 boot-only probes
  (kvm/podman/runtime/crun_libkrun/libkrun/smoke); smoke is still `--network none … true`. No
  `probe_clamp`, no `probe_passt`, no in-guest nproc/MemTotal assertion, no read-only-rootfs write
  probe. Opus added `probe_clamp` (517–536, tolerance band 256..899 MiB) and `probe_passt`
  (560–571), routed through real annotations. → the key bug ships undetected, exactly as #4 warns.
- **#12 image pre-pull — NOT FIXED.** No `podman image exists`/pull guard in Sonnet; Opus added one
  (477) with a distinct image-vs-krun remediation.

All three of B's blockers are `bash -n`-clean and behaviorally silent. This is the predicted outcome
in its strongest form.

### Cluster C — transport/flags (#5,#6). RATING: CORRECT (≡ Opus in substance)
- **#5 --timeout.** Sonnet wires exec timeout (1315–1317) and **rejects keep --timeout via a
  verb-aware guard INSIDE verb_keep (1156–1157), with a comment explicitly noting it is "not in the
  shared parse_birth_args, which verb_run also uses."** This is precisely the trap the prediction
  named ("placed in the shared parse_birth_args, explicitly forbidden") — and Sonnet **avoided it**.
- **#6 argv transport.** Sonnet took the *preferred* fix: passes WORKLOAD_CMD words **directly** as
  podman/exec trailing args (1054–1055, 1303–1306, no shell), renames `encode_workload`→
  `encode_script` and re-scopes it to a single opaque `-c` script with a corrected doc comment. The
  `echo 'a;rm'` footgun is gone. Matches Opus's design intent.

### Cluster D — lifecycle (#7,#8,#11). RATING: CORRECT — both subtle items landed
- **#7 orphaned branch.** Records parent repo in a `.parent` sidecar at create (757–758); on remove,
  reads branch name + parent **before** `git worktree remove`, then `branch -D` **after**, guarded
  on `sandbox/*` (793–818). Ordering correct (removal precedes -D), the exact subtlety #7 flags.
- **#8 reap half-born.** Rewrote the case to `running|paused|removing|stopping) :;; *) … ephemeral
  leak` (1556–1561); bogus `dead` token dropped. Correct.
- **#11 die-in-$(...)** — the prediction's named likely-miss. Sonnet got it RIGHT at all four sites
  (1227/1274/1346/1409): `if ! id="$(resolve_managed "$name")"; then exit "$EX_NOTFOUND"; fi`.

### Cluster E — mounts/usage (#9,#10). RATING: CORRECT (≡ Opus)
- **#9 rw relabel.** Sonnet appends `:rw,z` to rw and `:ro,z` to ro extra mounts (1025–1026),
  choosing the **shared `:z`** (the finding's recommended safer choice for arbitrary user paths over
  the destructive private `:Z`). Opus made the identical `:z` choice. The predicted "`:z` vs `:Z`
  nuance" risk did not materialize.
- **#10 usage drift.** Added `# VERB: version` (140) and inlined the `ls|list`/`rm|remove` aliases
  (135, 138). Drift closed.

---

## Verdict on the committed predictions

**Difficulty ranking (B ≫ D > C > E > A): BORNE OUT, with the gap even sharper than predicted.**
B is the *only* cluster Sonnet failed, and it failed completely (3 of 4 findings unfixed, untouched
from baseline). The "≫" before B is fully vindicated — B is not just hardest, it is the sole failure.
D/C/E/A all came out clean, so the *relative* ordering among them couldn't be stress-tested, but
nothing inverted it.

**Per-cluster P-bands: directionally right; B and D were if anything mis-calibrated optimistically.**
- A 0.95 → hit (identical to Opus).
- E 0.85 → hit (clean; the flagged `:Z` nuance handled correctly).
- C 0.60–0.70 → Sonnet landed at the *top* of / above band — both the shared-parser trap (#5) and
  the argv footgun (#6) were dodged cleanly. Slightly under-predicted.
- D 0.60 → Sonnet **beat** the band: BOTH predicted-subtle items (#11 command-substitution, #7
  ordering) were correct. The 0.60 was pessimistic for this run.
- B 0.35–0.50 → the *failure* was predicted, but the realized outcome is worse than P=0.35: not a
  partial, but a near-total non-fix of all four B findings (key prefix, use_passt, doctor probe,
  pre-pull). B's effective fully-correct probability this run was ~0.

**Surprises:** No falsifier from the easy side — A and E did not fail, so the meter is not falsified
from below. The mild surprises are upside: D's two subtle traps and C's shared-parser trap were all
avoided, suggesting Sonnet handles "subtle-but-locally-dictated" fixes better than the 0.60 bands
assumed. The discriminating axis was **invention vs transcription** (axis 2) + **cross-site
consistency** (axis 3): B required (a) overriding the punch-list's own internal key-format debate and
(b) *designing* doctor probes and tolerance bands that don't exist in the draft — and that is exactly
and only where Sonnet fell down.

**HEADLINE CALL: YES.** Sonnet's B shipped a `bash -n`-clean file containing not one but **three**
silent semantic errors, all from the predicted set:
1. surviving `run.oci.` prefix (cpus/ram caps silently no-op) — 594–595;
2. missing `krun.use_passt` → boot-only loopback with no guest NIC — `grep -c use_passt` = 0;
3. boot-only doctor probe that asserts nothing in-guest — no probe_clamp/probe_passt.
The "naive tolerance band" sub-mode didn't arise only because Sonnet never wrote the probe at all.
The meter's central claim — a weaker model produces a plausible, lint-clean, complete-*looking* file
whose failures concentrate in B and survive `bash -n` — is confirmed with direct diff evidence.
