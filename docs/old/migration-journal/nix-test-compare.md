# nix-test — comprehensive compare & contrast

What the previous (autonomous, top-down) nix-test attempt did, mined for the bits
worth keeping. Source of record stays `nix-decisions.md`; this is the harvest doc.

**What nix-test IS:** a Phase-0 *skeleton authored blind* — written on a machine
with no Nix, never evaluated. Tells:
- **No `flake.lock` committed** → unpinned `nixos-unstable`, non-reproducible.
- **Every `pkgs/` hash is `lib.fakeHash`** (13 across 8 derivations) → nothing builds.
- The bespoke overlay pkgs are **exposed but commented out of every install set**
  → CI is green only because they're never consumed.
- Huge fraction of the "architecture" (niri-flake, quadlets, microvm, disko, TB
  cluster fabric, ROCm, secure boot) exists only as **commented placeholders**.
- All four `hosts/*/hardware.nix` are **non-bootable placeholders**.

So: **reference for shapes and findings, never a base to build on** (matches the
`nix-decisions.md` ruling). Below: ADOPT / ALIGN / DIVERGE / WRONG, then open
conflicts it surfaced.

---

## ✅ ADOPT — nice initiatives worth lifting into the real build

1. **Self-validating flake `checks` — the standout.** `nix flake check` runs three
   checks that close the exact hole our **RAW** choices create (raw files are never
   validated at switch):
   - `niri-config` — copies `config/niri` to a tmp HOME and runs `niri validate -c
     config.kdl`, **pinning niri to the same package the host runs**.
   - `shellcheck-bin` — `shellcheck -S error` over every shebang'd script in `bin/`.
   - `deadnix` over first-party Nix (`--no-lambda-pattern-names`).
   Same check runs locally and in CI. **Because we chose niri RAW + a whole-dir
   `bin/` symlink, this validation layer is more valuable for us than it was for
   them.** Lift it early.

2. **`mkOutOfStoreSymlink` hot-reload wiring — and its granularity rules.** The
   pattern is our RAW intent; nix-test worked out the *granularity*, which is the
   real lesson:
   - **Whole-dir** symlink for `~/.local/bin` (the repo *owns* it; new scripts work
     with no rebuild — accept that other tools' writes show in `git status`).
   - **Per-file** symlinks for `~/.local/share/applications/*.desktop` + icons —
     because Claude Code's url-handler, Chrome PWAs, GearLever all write their own
     `.desktop` files there; a whole-dir symlink collides on first activation.
   - **Per-`~/.config/<dir>`** via `genAttrs`.
   - `fish_variables` / `niri.kdl` editing through the symlink "shows up in git
     status, which is a feature."

3. **Claude Code = COPY via activation hook** (matches our COPY call). Concrete:
   `home.activation.claudeConfig = lib.hm.dag.entryAfter ["writeBoundary"]` →
   `cp -f settings.json/settings.local.json` + `cp -rf skills/.`. Caveat to carry:
   copy won't *remove* deleted skills, and edits need a re-activation to propagate.

4. **niri `include optional=true "local.kdl"`** — untracked per-machine overrides
   on top of the tracked KDL. Clean. Lift into our niri config.

5. **sops `.sops.yaml creation_rules` as a crypto-enforced ACL.** Two files:
   `common.yaml` (recipients = all host keys + admin + backup) and a coordinator-only
   file (**`coordinator` only — the `worker` deliberately excluded**, so a compromised
   worker *cannot* decrypt immich-db / cloudflare / router secrets). "Cryptography, not a
   runtime ACL, enforces this." This is exactly our SSH-host-key model — lift the
   `creation_rules` shape verbatim (**but swap the YubiKey recipient → personal age
   key**, see DIVERGE). Also bank its two documented footguns:
   - **First-boot bootstrap:** a host's SSH host key is generated *during* install,
     so it isn't yet a recipient → first-boot decrypt fails. Fix: `nixos-anywhere
     --extra-files` pre-seed, or install→grab pubkey→`sops updatekeys`→re-switch.
   - **Impermanence caveat:** if erase-your-darlings ever lands, `/etc/ssh` MUST
     persist or every secret becomes undecryptable.

6. **Two-layer module factoring + a typed cluster option.** `modules/common.nix`
   (device-agnostic, all hosts) + `modules/strix-halo.nix` (AMD-role only) defining
   `options.myCluster.role = enum ["master" "companion"]` and `tbHostId` (master=1/
   companion=2). The *shape* matches our `common.nix` + `hosts/<device>/` plan, but
   **in OUR config the enum is `["coordinator" "worker"]`** — the AMD pair is
   `coordinator` (main) / `worker` (compute); **`companion` and `sodimo` never
   appear**. (Under-consumed in
   nix-test — see WRONG — but the shape is correct.) Pair with disciplined
   `lib.mkDefault` so `nixos-hardware` modules can override (kernel/timezone/platform).

7. **Per-device findings — concrete, liftable as-is:**
   - **dell-xps:** import `nixos-hardware.nixosModules.dell-xps-13-9315`; add
     `intel-media-driver` + `LIBVA_DRIVER_NAME="iHD"` (deliberately iHD, not i965);
     PPD owns power — **no TLP**.
   - **zenbook-duo:** no dedicated nixos-hardware module → compose `common-cpu-intel`
     + `common-pc-laptop` + `common-pc-laptop-ssd`; `i915.enable_psr=0` (eDP
     flicker); `intel-media-driver`+iHD; `services.asusd.enable` (kbd/charge-limit);
     **second display + IPU6 webcam are niri/out-of-nixpkgs work, not NixOS** (Duo
     daemon + titdb need packaging as flake inputs); BIOS flash precedes Linux audio.
   - **Strix Halo kernel tuning:** `amd_iommu=off` + `ttm.pages_limit=33554432`
     (128 GiB pinnable for the iGPU). `ttm.page_pool_size` is **non-canonical — can
     drop** (its own comment + the research doc say so).

8. **Router-plane glue made declarative — the biggest banked audit catch.** Four
   round-1 agents all *missed* it; round-3 caught that "the machine IS the LAN
   router." Concrete drop-ins worth copying (coordinator only):
   - `net.ipv4.ip_forward = 1`.
   - dnsmasq-shared `00-adguard.conf`: `port=0` (frees :53 for the AdGuard quadlet)
     + `dhcp-option=6,10.42.0.1` (hands clients the gateway as resolver).
   - `01-be550-pin.conf`: `dhcp-host=98:03:8e:6b:61:e2,be550,10.42.0.2,infinite` —
     pins the TP-Link Archer BE550 AP, **the address the NAS mount hardcodes**.
   - **Coupling to remember:** NAS mount → BE550 pin → DHCP. On a blind build "the
     LAN gets no DNS/DHCP, the NAS mount fails (taking immich/navidrome with it)."
     Round-3 verdict: **land router/DNS/NAS items one at a time, on the real
     machine, with a rollback generation ready.**

9. **avahi "advertise a dumb NAS over mDNS" trick** (harness): `services.avahi`
   (publish + `nssmdns4`) + a `_smb._tcp` service record + a `systemd.services.
   avahi-alias-lacie` running `avahi-publish -a lacie.local 10.42.0.2`
   (`bindsTo` avahi-daemon, `Restart=always`) — makes a NAS that can't speak mDNS
   discoverable, discovery-only (data path stays client→AP). Optional nicety.

10. **CI shape worth keeping:** Determinate installer; a **realised** host matrix
    (`nixosConfigurations.<host>.config.system.build.toplevel`, not just eval) with
    `fail-fast:false`; a **"free runner disk"** step (the full closure OOM-disks the
    runner); weekly `update-flake-lock` PR (Mon 06:00 UTC) replacing the COPR 6-hour
    bot. `magic-nix-cache` deliberately avoided (HTTP-418 rate-limit poisons pushes).

11. **`secrets/` modeled, not API keys only:** intended `common.yaml` = wifi PSK +
    tailscale authkey; `master.yaml` = immich-db-password, cloudflare-tunnel-token,
    router/NAS secrets. (Note: nix-test did **not** model pi/claude/gcloud/gh API
    keys in sops — we said the harness keys hang off this layer, so **add them**.)

---

## ⟳ ALIGN — nix-test independently landed where we did

- **niri = RAW KDL** (not `programs.niri.settings`) — nix-test did exactly this and
  the 3-agent dotfiles sweep + your 2026-06-20 ruling agree. (nix-test used nixpkgs
  `programs.niri.enable`; **we** add **niri-flake** — see DIVERGE.)
- **Everything RAW/COPY, nothing typed** except `programs.{git,direnv,gpg}` — same
  managed-file-not-native-module stance we took (git the lone TYPED exception).
- **`pipx` dropped** ("imperative Python installs are the anti-pattern this exists
  to kill") — matches our drop.
- **microsandbox → microvm.nix** — nix-test even flagged its own `microsandbox.nix`
  as "may be obsoleted by microvm.nix." We decided microvm.nix → **drop the package**.
- **litellm + OpenWebUI dropped**, native llama.cpp + llama-swap (OpenAI API straight
  to the agents) — consistent with our direction (and now superseded in practice by
  the ds4 cluster, which postdates nix-test).
- **nixos-unstable channel** for fresh Strix-Halo kernels — same call.
- **Bottom-up phase order** (HM bridge → pkgs → NixOS host → CI/cache → secure boot
  last) — same as our Layer 0→4 plan.

---

## ✗ DIVERGE — our decisions deliberately differ; do NOT copy nix-test here

| Thing | nix-test did | We decided | Action on the nix-test artifact |
|---|---|---|---|
| **flatpak / Chrome** | kept `nix-flatpak` + flathub + 12 Chrome **PWAs via flatpak** (`Exec=flatpak run … com.google.Chrome --app=…`) | **drop flatpak** → `google-chrome` from nixpkgs (unfree) | **Rewrite all 12 `.desktop` Exec lines** → `google-chrome-stable --app=URL`. Drop the nix-flatpak input + preinstall set. |
| **Secrets edit identity** | YubiKey: `age-plugin-yubikey`, `admin_yubikey` recipient, pcscd, `pam_u2f` stub | **no YubiKey** → edit recipient = **personal age key** (`ssh-to-age` of laptop SSH key) | In `.sops.yaml` replace `&admin_yubikey` with a personal age key; drop pcscd/pam_u2f/age-plugin-yubikey. |
| **ASR** | WhisperLiveKit **container** (`asr-toolbox.container` + `Dockerfile.asr`, ROCm/PyTorch wheels) + asr-rs native *client* | **asr-rs v2 = single Rust binary** (parakeet, WIP); **no WLK container** | **Delete** the asr-toolbox quadlet/Dockerfile entirely; asr-rs is the whole stack. |
| **niri provider** | nixpkgs `programs.niri.enable` | **niri-flake** (sodiboo), bleeding-edge | Add the niri-flake input nix-test left commented. |
| **pi** | local `pkgs/pi.nix` (fetchurl tarball) | **pi.nix (lukasl-dev)** + **llm-agents.nix (numtide)** | Drop the bespoke pi package; use the flakes. |
| **antigravity** | `pkgs/antigravity.nix` stub (`TODO://` url) | **dropped** | Delete the stub. |
| **microsandbox** | `pkgs/microsandbox.nix` | **microvm.nix** | Drop the package. |
| **mactahoe** | `pkgs/mactahoe-oled.nix` = unpack a **prebuilt tarball** (no postPatch; layout "may be flat — adjust") | **rung 3 source-build + OLED postPatch, PROVEN** at `~/mecattaf/mactahoe-oled/` | **Use our `mactahoe-oled/`, ignore nix-test's package.** |
| **CADE** | docs describe CADE (Chromium Aura DE — the "be the compositor" overshoot) | **CUBS** (browser-shell *under* niri) | nix-ouverture.md supersedes; ignore CADE framing. |

---

## ⚠️ WRONG / STALE in nix-test — explicit traps to avoid

- **`//10.42.0.2/LaCie` NAS share is WRONG** — our harness audit says the share is
  **`/G`** (`nix-decisions.md` already flags this). Do not copy `/LaCie`.
- **`pkgs/mactahoe-oled.nix`** is a prebuilt-tarball unpack with an uncertain layout
  — *not* the source+OLED-postPatch we actually proved. Inferior; superseded.
- **fgp-browser `0001-support-CDP_URL-env-var.patch`** has a **synthetic header**
  (`From 0000…`, fabricated index/context, `@@ -678,6 +678,9 @@`) → **will likely
  not apply** to real upstream. The *idea* (read `CDP_URL` env when `--connect`
  omitted) is worth keeping for the deferred fgp work; the patch file is not.
- **`gws` packaged as `buildRustPackage`** from `googleworkspace/cli` — **unverified
  that upstream is actually Rust at that rev** (version was COPR-bot-managed). Verify
  the real upstream language/build before packaging (gws is deferred anyway).
- **nvim uses Mason (runtime LSP installer) + a runtime GitHub clone of lazy.nvim**
  — exactly the reproducibility drift to kill; this *is* the open nvim-session work
  (mason→Nix LSPs + tree-sitter pre-seed + lazy-nix-helper).
- **`myCluster.role`/`tbHostId` declared but barely consumed** — master services
  live *inline* in `hosts/harness` instead of being gated on `role=="master"`, and
  the TB `/30` link is comment-only. Adopt the option *and actually gate on it*.
- **Process smell — "logged as done ≠ done":** the zram-8GiB cap was recorded
  APPLIED in DECISIONS yet caught NOT-applied by three later audits. Our per-item
  loop (prove-then-record) exists precisely to avoid this.
- **FIPS dracut module / sysupdate-UKI profile = cargo-cult** (no `fips=1` karg
  anywhere; profile literally says "SHOULD NOT BE USED"). Don't port.
- **SELinux is lost on NixOS** (accepted for single-user desktop; AppArmor is the
  opt-in path) — just be aware.
- **All `hardware.nix` are placeholders** + **no flake.lock** + **all fakeHash** —
  never build on this tree.

---

## ⏳ Open conflicts nix-test surfaced that our decisions haven't resolved

1. **`HSA_OVERRIDE_GFX_VERSION` for gfx1151.** nix-test's WLK container hardcoded
   `11.0.0`; its own research doc says that's **wrong** for gfx1151 (should be
   `11.5.1` or dropped). The WLK container is gone, so it's moot *there* — but the
   spoof question resurfaces for any ROCm path (ds4 image, native llama.cpp). Flag
   for the LLM/ASR build phase. 🔬
2. **gws upstream reality** — confirm language/build/repo before the deferred gws
   packaging (don't assume nix-test's Rust guess). 🔬
3. **NAS share name** — `/G` vs `/LaCie`: verify on the real harness before the mount
   lands (already an open ⚠️ in decisions; nix-test reinforces the risk). 🔬
4. **Secrets scope** — our model says the agent-harness keys (pi/claude/gcloud/gh)
   hang off sops; nix-test modeled only wifi/tailscale/immich/cloudflare. Decide the
   full secret inventory when the secrets phase lands.

---

## Pointer
Don't build on `nix-test/`. Treat it as: a **checks/CI shape to lift**, a
**granularity manual for `mkOutOfStoreSymlink`**, a **per-device findings sheet**,
and a **router-plane + secrets-ACL reference** — filtered through the DIVERGE table.

---

## Rulings on this harvest (2026-06-20) — read with the ADOPT list

Overriding lens: **maximal nix-native is the end-state; RAW/symlink/hand-rolled is
temporary scaffolding to reach a first boot; nothing is built until Nix is flashed
on all devices.** Per-item verdicts:

- **#1 flake checks** — keep the *idea*, but niri RAW (the thing the check guards)
  is interim; niri gets nixified post-first-boot. **bin/ scripts → eventual
  nix-native** (`writeShellApplication`), not a permanent RAW dir.
- **#2 mkOutOfStoreSymlink granularity** — interim only; the end-state is the most
  nix-native format. Don't overbuild around the symlink shape.
- **#3 Claude Code copy hook** — **rejected as hand-rolled.** Use the **AI-agent nix
  flake** (llm-agents.nix / agent-harness) for config+skills if it supports it;
  only fall back to a copy hook if it genuinely can't. Pi via **pi.nix**.
- **#4 niri `local.kdl` override** — only if it stays nix-native (no contortions);
  re-evaluate during the niri nixification.
- **#5 sops creation_rules / footguns** — secrets is a **dedicated session, tool
  undecided**; edit identity = **personal age key** (swap out YubiKey). **Scope =
  MAXIMAL: all keys** (pi/claude/gcloud/gh + wifi/tailscale/immich/cloudflare).
  **No impermanence** → the `/etc/ssh`-persist caveat is moot.
- **#6 two-layer modules + role enum** — **liked.** Enforce the naming rule:
  `coordinator` + `worker`; `companion` and `sodimo` never appear.
- **#7 per-device findings** — **liked, lift as-is.**
- **#8 router plane** — fine; trial-and-error on the real box. **Acceptance test =
  the AdGuard server actually filters the broadcast wifi (ad-free).**
- **#9 avahi NAS-mDNS nicety** — ok.
- **#10 CI shape** — **"B-minus."** Keep it but improve: add **binary-cache push**
  (Attic/Cachix) + a **`nix-update`** job for pinned versions.
- **#11 secrets modeled** — fold into the dedicated secrets session (scope maximal).
- **ALIGN/pipx** — dropped pipx stands; replacement = nix-native Python
  (`python3.withPackages` + `uv`/`uvx` + devshells), exact shape TBD.
- **ALIGN/LLM** — drop litellm+openwebui; **models may be podman quadlets**,
  llama-swap native — decide by testing.
- **DIVERGE confirmations** — flatpak fully out; antigravity + microsandbox dropped;
  niri-flake later (bundled w/ niri nixification); mactahoe = our `mactahoe-oled/`;
  asr-rs v2 **not in first push**; **CADE→CUBS, nothing built until all devices flashed.**
- **TRAPS** — `/LaCie` NAS name + gws: **keep placeholder, fix later, non-blocking.**
  `HSA_OVERRIDE_GFX_VERSION`: **follow the dedicated AMD-Strix-Halo nix repo's
  current value** (latest, not the stale 11.0.0). nvim: **keep lazy.nvim, zero
  functionality loss.** fgp-browser: **conceptual inspiration only, not committed.**
