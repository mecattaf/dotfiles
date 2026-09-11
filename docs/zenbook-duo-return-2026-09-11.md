# Zenbook Duo return and coordinator demotion — consolidation of 2026-09-11

Status: consolidation document, revised 2026-09-11 afternoon after Tom's rulings R-12…R-18
(§1). Written on the coordinator (`~/mecattaf/dotfiles`, branch `worker-remote-wired`, HEAD
`7e544f5c`, clean tree) from eight read-only research reports plus spot re-verification of the
tree. Nothing in this document was implemented. Tags: **VERIFIED** = read in a file, commit,
transcript or live probe named here; **INFERRED** = reasoned from verified facts, untested;
**ASSUMPTION** = the orchestrator's reading of an ambiguous ruling, to be confirmed by Tom.

Revision marks: every change made for the afternoon rulings is tagged **(2026-09-11 pm)**;
superseded text is ~~struck~~ or annotated "SUPERSEDED by R-nn", never deleted, so the
reader can see what replaced what. The laptop's fleet identity is now **`client`** (R-12);
`zenbook-duo` survives below only for history and for the omarchy-fleet install being
offboarded. The file keeps its name.

Audience: Tom (orchestrator level, no code) and the implementing agent that follows. The
implementing agent should treat §10 as the work order; §11 holds the ONE question that still
blocks and the defaults the agent takes for everything else (R-18). **The orchestrator's
answer to Tom, in one line: OK to power the Zenbook Duo back on now — that is §10 step 2;
nothing in this document has to be ruled on first.**

---

## 0. Why (the agency.agency vision and what it imposes on a thin client)

R-5 names the "agency.agency full vision" as the long-term goal and calls dotfiles "a byproduct
of configuring things for the AI agent". Where the vision lives (VERIFIED, session A §4): the
`~/agency` corpus (312 md files, 133 MB in the home census), the register area "agency and
moonshot: 6 projects", and the notes-backlog task `front-02 -
Bring-Agency-from-red-corpus-to-sealed-build-handoff.md` (dirty in the notes tree). Tom made
no statement about "agency.agency" in sessions A, B or C beyond the R-5 phrase; the invariants
below are INFERRED from the verified heuristics (triad tally / tally-ts-sdk / herdr-kitten,
"GitHub issues replace handoffs", "one inference engine, one model", conwip factory).

Invariants the vision imposes on the Zenbook, and which every later section obeys:

1. Agents and their seats (cc/cc2/cc3, codex, pi, the tally-* clocks, the microvm host) stay on
   the coordinator; the laptop never runs an agent or holds a Claude/Codex credential (I-3).
2. No local LLM on the laptop; inference is halogen on the worker (`modules/halogen.nix`).
3. herdr is the projection: the laptop sees the coordinator's work through
   `herdr --remote coordinator`, not through per-pane copies or a mirrored clipboard (§6).
4. Follow-ups are GitHub issues, not handoffs (§10 step 15); rulings go to DECISIONS.md.
5. Everything else in this document (hardware layer, binds, peripherals) is byproduct: it must
   work, it must not pull work back onto the laptop.
6. **(2026-09-11 pm, R-16)** The client closure is near-static: compositor + kitty + clipboard
   bridge + peripherals + Chrome + the Duo hardware layer. Everything that changes often
   (herdr, hk, tally, skills, models, printing, artifact plane, PWA and launcher entries) lives
   on the coordinator; the client never switches without Tom's hand (§4.1 I-5, §5.1).
7. **(2026-09-11 pm, R-13)** The coordinator goes headless the moment the client is proven as a
   seat (§10 steps 9–11). "coordinator remains the machine that i run on — and i insist on
   that." After the flip its only inputs are ssh and the VT getty; there is no VNC at all.

---

## 1. Rulings of 2026-09-11 and the orchestrator's assumptions

Rulings (verbatim intent, numbered for reference as R-n throughout):

1. **R-1** The coordinator stops being the main input device. The ASUS Zenbook Duo UX8406MA is
   reclaimed from Marwan as of right now and becomes Tom's main input device. It is a blank
   canvas to be configured fully.
2. **R-2** The Zenbook leaves omarchy-fleet/omarchy-nix (Hyprland + Quickshell "Omarchy") and
   transitions BACK INTO dotfiles: niri, no quickshell, shell scripts in `~/.local/bin`. Tom is
   not using Omarchy on it.
3. **R-3** ~~The coordinator goes fully headless EVENTUALLY, not today.~~ **SUPERSEDED by R-13
   (2026-09-11 pm)**: headless is the step right after the client is proven, not "eventually".
   Still true: Tom is about to reboot the coordinator; this document is the consolidation
   before that reboot.
4. **R-4** The dual-5K desktop (two ASUS PA27JCV 5120x2880 on DP-1/DP-4, kanshi profile
   `Desktop`) is formally RETIRED: too much screen real estate. Only DP-1 is connected now.
5. **R-5** The dual-screen Zenbook is reintegrated as a THIN CLIENT: very little runs on the
   device. Long-term goal is the "agency.agency full vision"; dotfiles is "a byproduct of
   configuring things for the AI agent" (session A heuristic, VERIFIED).
6. **R-6** Crucial improvements: CLIPBOARD CONTROL between Zenbook and coordinator over ssh, and
   EFFORTLESS KITTY SSH into coordinator sessions (herdr-kitten `hk` sessions live on the
   coordinator).
7. **R-7** The peripherals on the coordinator's USB move to the Thunderbolt dock the Zenbook
   benefits from: Sony INZONE Buds `054c:0ec2`, Creative Sound Blaster GS3 `041e:3298`, iContact
   Camera Pro webcam+mic `1bcf:2d3e`, Apple Magic Trackpad `05ac:0265`, MoErgo Glove80 Left
   `16c0:27db`, MediaTek `0e8d:0717` dongle. All the coordinator-as-desktop niceties carry over.
8. **R-8** "the only thing that really moves there is the google chrome browser which still
   remains on coordinator."
9. **R-9** VNC: nothing beyond what is set up today (wayvnc on the coordinator, Remmina profiles
   from `home/remote.nix`). **(2026-09-11 pm)** Read together with R-13: the wayvnc server is a
   niri user service and dies with the flip, so after the flip there is NO VNC anywhere in the
   fleet, and nothing replaces it.
10. **R-10** Known niri defects on the dual-screen Zenbook (touch → output mapping needs unmerged
    niri PR #1856; stock niri maps both ELAN panels to one output) are ACCEPTED for now.
11. **R-11** Full carry-over of the coordinator's niri shortcuts (`home/dot_config/niri/binds.kdl`)
    with possible functional changes, e.g. F10 "Sleep Monitors" may become "brightness to zero"
    on the Zenbook.

Rulings of 2026-09-11 afternoon (verbatim intent):

12. **R-12 HOSTNAME.** The laptop is called `client` henceforth ("for thin client"), everywhere
    the fleet names things: flake node, `networking.hostName`, mesh-registry row, agenix
    recipient, deploy target, ssh nickname, update-center entry. No `zenbook`/`zenbook-duo`
    alias — the dotfiles rule is "typed name = identity" (`home/ssh.nix:15-21`, VERIFIED).
    `hosts/client/`, `.#client`. The name `zenbook-duo` remains only for history and for the
    omarchy-fleet install being offboarded (§3).
13. **R-13 HEADLESS NEXT, NOT EVENTUALLY.** Tom: "on the strix halo i am currently 1 monitor
    unplugging away from making the coordinator completely headless. this means that my
    primary device becomes the zenbook duo, once and for all. coordinator remains the machine
    that i run on — and i insist on that." Everything runs on the coordinator; the client is
    only the seat. The flip is §10 steps 10–11, immediately after the seat is proven (step 9).
    The `myDisplay.enable` option (§8.3) is part of the FIRST code step. No VNC after the flip.
14. **R-14 NO KEY RECREATION.** Tom: "NO NEED FOR KEY RECREATION WHATSOEVER. there is no
    contamination of the zenbook key. keep things as they are." `client` keeps the host key
    that is on the laptop today (the fleet key, §2.2); the registry row reuses that public
    key; no offline mint, no re-key. Consequence for the install path: §4.5.
15. **R-15 RAIL.** Tom: "zenbook becomes a bespoke node on the headscale fleet when out of the
    house, and on the thomas-6ghz wifi it has no need for it." Q-5 = (b): NAS headscale, the
    existing enrolment (node 4) kept. On the LAN `coordinator` = 10.42.0.2 direct; off-LAN the
    path is through the NAS (§4.3).
16. **R-16 NEAR-ZERO UPDATES.** Tom: "i expect VERY FEW if any updates at all on the zenbook duo
    laptop. it should really encapsulate what a thin client DOES which is nothing more than to
    be the display for the stronger computer. in our case it also happens to handle my google
    chrome tabs." The client is on NO automatic pull or switch; the NAS may still build its
    closure nightly (cache warm), nothing activates without Tom. A-1 CONFIRMED.
17. **R-17 SEAT SEMANTICS.** greetd autologin to niri, always; "no sddm, ever". Multitouch
    gestures (ntm) and rotation are OUT OF SCOPE TODAY ("multitouch and old rotation things
    are not in scope for today"); the niri touch-mapping fixes are recorded as the recovery
    path only (§4.4, §9 D-1). Tom's framing: "really i think this is a straightforward
    port-over from my coordinator's existing nixos config" — §4 reads as coordinator config
    minus coordinator-only gates plus the Duo hardware layer.
18. **R-18 ORCHESTRATION STYLE.** Tom: "i m not expecting a list of things to rule on. i m
    expecting you to tell me 'ok to power on zenbook duo back on now'." §11 shrinks to what
    truly blocks, each with the default the agent takes if unanswered.

Orchestrator assumptions (each must be confirmed or overturned by Tom):

| ID | Assumption | Basis |
|---|---|---|
| A-1 | **CONFIRMED (2026-09-11 pm, R-16).** R-8 means: Chrome is the one real LOCAL app on the client, AND Chrome stays installed on the coordinator (fleet-wide `google-chrome` in `home/home.nix`, VERIFIED). No Chrome-over-VNC or Chrome-remoting is implied. | Sentence is ambiguous; the fleet-wide package makes both readings cost nothing. |
| A-2 | F10 on the Zenbook = R-11's literal ask, "brightness to zero", implemented as a popup-free backlight toggle (`brightnessctl -s -d intel_backlight set 0` / `brightnessctl -r -d intel_backlight`; the daemon's 500 ms sync carries the zero to eDP-2). The earlier draft's `niri msg output … off` recommendation is WITHDRAWN (§5.2 F10 row explains the lockout). Mod+Shift+P keeps DPMS-all. | Critique (thin-client-design): `home/dot_local/bin/brightness` only touches `*/drm/*` backlights so `asus_screenpad` is irrelevant (VERIFIED lines 26-34); `brightnessctl -s/-r` exist (VERIFIED `--help`); i915 treats brightness 0 as backlight power-off and the daemon copies, never compares (reported from upstream `intel_backlight.c` and `secondary_display.rs`, not re-read here — INFERRED). |
| A-3 | R-9 "VNC unchanged" means the client gets a Remmina `coordinator (VNC)` profile for free (registry-driven), and the client does NOT itself run a wayvnc server. **(2026-09-11 pm)** Narrowed by R-13: the profile is useful only between step 6 and the flip (step 11) and is NOT a gate; the `5900` door stays `tailscale0`-only, so from the client it does not work at all — accepted. After the flip `home/remote.nix` loses the server AND the profile generator (§8.3). | `home/remote.nix:53` is `lib.mkIf osConfig.programs.niri.enable` (VERIFIED) — without a gate the client WOULD run wayvnc :5900 unauthenticated. |
| A-4 | ~~"Headless eventually" is a later, separate ruling; nothing in this document removes niri, greetd, wayvnc or Chrome from the coordinator now.~~ **SUPERSEDED by R-13 (2026-09-11 pm)**: the flip is steps 10–11 of §10. Chrome stays installed on the coordinator (A-1) as headless tooling only. | R-3 → R-13. |
| A-5 | **CONFIRMED (2026-09-11 pm).** Today's reboot of the coordinator is ALSO the coordinator switch onto `7e544f5c` (PR #368 still OPEN, VERIFIED `gh pr list`), discharging session B's "no reboot until done" constraint (DoD met 13:09Z, VERIFIED). | Session B §4. |
| A-6 | **CONFIRMED by R-17 (2026-09-11 pm).** The client is a niri seat (greetd autologin → niri from `modules/common.nix:210-234`, inherited by importing common), i.e. today's rulings formally supersede session B's 10:55:34Z "ONLY the coordinator has a display output" (made when the fleet had no laptop; VERIFIED in `hosts/worker/default.nix:35-37` header comment). The historian (r-dotfiles-tenure §4.9) asks that this header be superseded in the SAME commit that adds `hosts/client/` — step 3. After the flip the sentence becomes "ONLY the client has a display output". | Session B §3.3. |

---

## 2. State of the estate right now (2026-09-11)

### 2.1 Coordinator (VERIFIED live + tree)

| Item | State |
|---|---|
| Repo | `~/mecattaf/dotfiles`, branch `worker-remote-wired`, HEAD `7e544f5c` ("halogen: declare the Qwen3.8-27B alternate engine"), clean. `origin/main` = `681459f5`. |
| Open PRs (gh) | #368 `worker-remote-wired → main` (this branch); #369 `tb-cleanup → worker-remote-wired` (2 commits, head `0fce0cae`; the bolt removal is in `41fc8a0b`, the worker Ethernet-MAC dnsmasq pin `9c:bf:0d:01:cc:65` in `0fce0cae` — VERIFIED `gh pr list --json headRefOid`, `git log 7e544f5c..0fce0cae`; NOT merged: `modules/common.nix:256` still has `bolt.enable = true` at HEAD); #360, #358 (NAS, already fast-forwarded into main per session C — flagged); #359, #336, #333 older. |
| Running generation | BEHIND HEAD: live `~/.ssh/config` still has `worker HostName=10.99.9.2`; `worker` resolves to the retired TB identity until the switch. Kernel Linux 7.2.2. niri `26.04 (Nixpkgs)` (the "25.11 pinned" note in `niri/config.kdl:38` and the standing context is STALE; `overlays/default.nix:15` only patches `niri-session` stderr). |
| Outputs | One: DP-1 ASUS PA27JCV 5120x2880@60 scale 2 at logical 0,1440 (leftover geometry from the retired `Desktop` profile, where DP-4 sat at 0,0). kanshi running; `profile Desktop` cannot match with one output. **(2026-09-11 pm, R-13)** This one cable is what stands between the coordinator and headless; it is unplugged at §10 step 11 and, per the Q-14 default, moves to the client's dock. |
| Audio | PipeWire 1.6.8. Default sink Sound Blaster GS3 (runtime WirePlumber state, not declarative). Default source iContact Camera Pro, pinned by `hosts/coordinator/audio.nix` (`priority.session = 3000` on the USB-serial node name). |
| USB | 054c:0ec2 INZONE Buds, 1bcf:2d3e iContact, 041e:3298 GS3, 05ac:0265 Magic Trackpad (wired USB; `bluetoothctl devices` empty), 16c0:27db Glove80 Left, 0e8d:0717 MediaTek = the coordinator's ONLY Bluetooth controller `hci0` (VERIFIED: `readlink -f /sys/class/bluetooth/hci0/device` → `…/usb3/3-3/3-3:1.0`; `/sys/bus/usb/devices/3-3` manufacturer "MediaTek Inc.", product "Wireless_Device", interface class `e0` with a `bluetooth` subdir; unreferenced in the repo because `modules/common.nix:255` `hardware.bluetooth.enable = true` is fleet-wide). |
| Backlight | None (only keyboard LEDs; no `/dev/i2c-*`), so F1/F2 are no-ops here today. |
| User services | niri, piri, wayvnc, voxtype (+osd), herdr server (0.9.0, coordinator-gated `home/herdr.nix:85`), tally-daemon + timers, dcal-daemon, remmina-applet, 2x `wl-paste --watch cliphist store` (750 entries), kanshi, wl-gammarelay-rs, swaybg, xwayland-satellite. |
| DEAD desktop tier | `vicinae` (Mod+D since `03a49294` 2026-03-13 "bind Mod+D to launcher"; the line was last touched by `cf7c8d3f` 2026-07-29; binary absent on the coordinator today — VERIFIED `git log -S vicinae`), `rofi`, `rofimoji`, `wshowkeys`, `notify-send`/libnotify, `iwmenu`, `blueman-manager`, `alacritty` — none installed, no notification daemon. Mod+V clipboard picker, Mod+Shift+V, Mod+Apostrophe, F9 menu, bin/{powermenu,battery,wifi-menu.sh,music-download,fzf-shortcuts} are dead. Working picker pattern: fzf in a floating kitty (F10, Shift+F9, Shift+F10). |
| Networking | static 10.42.0.2/24 (NM profile `lan`, thomas-6ghz); tailscale.com emergency rail (`hosts/coordinator/tailscale.nix`, node 100.105.121.73); NOT on the NAS headscale. wayvnc :5900 admitted only on `tailscale0` (`tailscale.nix:92`). |
| Disk | root 62% after the 09-11 DS4 wipe (333 GB free). |

### 2.2 Zenbook Duo (VERIFIED from omarchy-fleet tree + session C; the device was not touched)

| Item | State |
|---|---|
| **Live status 17:40 local (2026-09-11 pm)** | Tom powered the laptop on; it sat on the Omarchy (Plymouth) logo and Tom power-cycled it. NAS DHCP leases show NO lease for it; headscale node 4 has been offline since 2026-09-10 13:00. Presumed cause: the known VMD MTL016 stall (`omarchy-fleet/docs/zenbook-duo-boot-2026-09-10.md`: intermittent ~5 min 21 s boots, "diagnosed; no boot fix deployed or validated yet", VERIFIED header) — a wait, not a brick. Operating rule for step 2: leave it on for ≥6 minutes before judging; only then power-cycle again. NB dotfiles also enables Plymouth (`modules/common.nix:58`, VERIFIED), so the same stall will look the same under `client` until D-3 is validated. |
| Flashed | 2026-09-08 by omarchy-fleet (disko `lib/laptop-disko.nix`: 1 GiB ESP + ext4 root, no swap, unencrypted). Autologin to `marwan`'s Hyprland/Omarchy desktop via SDDM. |
| Generation | app release `470fae7f` (toplevel `hw7zd4yd…-nixos-system-zenbook-duo-26.05.20260727.2f5a153`), kernel **6.18.40**, unpatched initrd (no MEI modules, no VMD patch). `bc866db` (Linux 7.2.4 + VMD MTL016 backport + early MEI) is published on the NAS but NOT accepted. |
| Rail | NAS headscale node **4**, `zenbook-duo-fleet`, `100.64.0.4`, `tag:fleet`, userspace `tailscaled-fleet`; persisted control URL STILL `http://10.42.0.1:8090` (public migration to `https://nas-saas.tail8dd1.ts.net:8443` never run on the real laptop). At home on the LAN it is reachable; off-LAN it is not. **(2026-09-11 pm, R-15 facts)** The fleet rail is `tailscaled --tun=userspace-networking … --state=/var/lib/tailscale-fleet/tailscaled.state`, brought up with `--accept-routes=false` (`omarchy-fleet/modules/fleet-rail.nix:8,23-24,72,108`, VERIFIED); the repo's login server is the Funnel endpoint `https://nas-saas.tail8dd1.ts.net:8443` (`profiles/fleet-common.nix:48`; Funnel enabled and policy-approved in dotfiles `hosts/nas/default.nix:120-121`, VERIFIED; "actual off-LAN laptops pending", `docs/nas/personal-tailscale.md:50`). `scripts/fleet-endpoint-migrate.py` rewrites ONLY `ControlURL` inside that state file and asserts the machine/node keys unchanged (`:23,79,102`, VERIFIED) — so the node identity survives a control-URL migration. Userspace mode cannot install the NAS's subnet route into the kernel; the dotfiles `client` runs the ordinary kernel-TUN `services.tailscale` instead (§4.1 I-8). |
| Host key | **(2026-09-11 pm, R-14)** The laptop carries the fleet key `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAoNjOhvz1H+SO5AhDdb4Z1FZlzUC+/KlMR1Oa7V0+YM root@zenbook-duo` (`omarchy-fleet/modules/fleet-registry.nix:44-51`: "generated offline on 2026-09-07 … private half delivered once via `nixos-anywhere --extra-files`", VERIFIED). That it is the key ON THE METAL, not just in the registry, is VERIFIED from the coordinator's own `~/.ssh/known_hosts:25`, where a live connection recorded exactly this key under the alias `zenbook-duo-lan`; the flash gate `ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key` "MUST equal the registry row" (`docs/flash.md:139-144`) is the procedure that admitted it (its result is not written in LEDGER.md — grep empty — so the known_hosts line is the evidence). This is NOT the 2026-07-05 dotfiles key `…QoQJxxP` (`77eac406^:modules/mesh-registry.nix:83`, VERIFIED by comparing the strings): that key was wiped with the 2026-09-08 omarchy flash and is public in git history — it is not on the laptop and nothing reuses it. **`client`'s registry row reuses the fleet public key as-is; no new key is minted (R-14).** The `root@zenbook-duo` comment is not key material and stays. ~~the old dotfiles registry row cannot be reused as-is~~ — still true, but moot: the ROW is new, the KEY is the fleet one. |
| Marwan's envelope | Unix user `marwan`, `hashedPasswordFile = /etc/fleet/marwan.passwd` (passcode corrected in session C; it is NOT in any repo, but it IS in plaintext in the session C JSONL — Tom typed both laptop passcodes, Dell/Omar and ASUS/Marwan, in one message — and the research extract copied that line to the scratchpad `c-users.txt:94`; VERIFIED present, values deliberately not repeated here), `omarchy.email_address = marwan@example.invalid`. Marwan never physically received the device, never signed into anything (handover.md: owner card + passcode handoff PENDING). INFERRED: nothing to export. The Dell value is the LIVE credential of a lent laptop: see O-9. |
| Secrets on device | NONE (`omarchy-fleet/secrets/` empty, `mySecrets.enable` inert). No GitHub deploy key. |
| Hardware config proven on metal | `profiles/zenbook-duo.nix` + `hosts/zenbook-duo/hardware.nix` (§4.2). Boot defect: intermittent 5m21s boots from VMD `8086:7d0b` MTL016 NVMe completion timeouts; fix prepared, unvalidated. |
| Consent client | `update-center-client.nix` polls NAS 8091/8080 every 5 min as root with a blanket reboot prompt. Moot once switched to dotfiles (the units are not in the `client` closure; under the in-place path their state dir is residue to remove, §3 O-6). |

### 2.2b Other input devices in Tom's estate (not in the standing context)

- **MacBook Air M5** — surfaced only by dotfiles issue #353 (OPEN, VERIFIED `gh issue view 353`):
  a research write-up on pairing it with the Zenbook over one USB-C/TB4 cable. Verdicts in the
  issue: (A) Zenbook-as-display-for-the-Mac is a hardware dead end (no DP sink, no UDC); (B)
  Mac→Zenbook input passthrough ranked lan-mouse > waynergy (wlroots virtual-input, so it
  applies to niri as well as Hyprland), input-leap/Deskflow not viable; transport =
  `thunderbolt-net` ↔ macOS Thunderbolt Bridge on the same cable; clipboard sync untested; the
  issue calls the whole scenario "Tom-only … never wired into the fleet's shared device
  config". It carries NO ruling on clipboard, kitty-ssh or the coordinator seam. Whether the
  Mac is a second thin client or out of scope is Q-17.

### 2.3 What sessions A, B, C left as constraints and open threads

**Session A** (Claude `2ae71708`, 2026-09-10 11:50Z → 2026-09-11 15:29Z; VERIFIED distillation):

- Zero Tom mentions of the Zenbook, VNC, clipboard, kanshi or agency.agency (keyword scan).
- Standing rule 13:07Z 09-11: "whatever you do don t reboot coordinator node". Discharged by
  today's R-3/R-13 (Tom is rebooting it in person; A-5 confirmed 2026-09-11 pm: the reboot is
  the switch onto `7e544f5c`).
- PR #369 (`tb-cleanup`, 2 commits, head `0fce0cae`; the bolt removal is in `41fc8a0b`, the
  worker Ethernet-MAC pin in `0fce0cae`) removes `services.hardware.bolt.enable` from
  `modules/common.nix:256` and the mkForce in `modules/headless.nix:23` (VERIFIED `git diff
  7e544f5c..0fce0cae`). The PR agent flagged "a dock plugged into the coordinator is no longer
  auto-authorized". Tom DID rule, the same day, in DECISIONS.md lines 57-58 (VERIFIED): "The
  stock `thunderbolt` driver and bolt stay for ordinary USB4 peripherals; only the fleet's use of
  the bus is gone." The bolt hunk therefore contradicts a standing ruling and collides with R-7
  (a Thunderbolt dock on a host that imports `modules/common.nix`). See §7.2 and Q-2.
- "one single inference engine, one single model configuration" (halogen on the worker,
  `modules/halogen.nix`, port 8731). Thin-client consequence: the Zenbook needs nothing local
  for LLMs.
- Heuristics that shape this document: "fable (orchestrator, high level, no code written ever)";
  GitHub issues replace handoffs; placement not retention; dotfiles is the "experimentation
  bench ... conwip factory for my agents".
- Open threads still live and relevant: merge #369 + #368 and switch; bolt hunk (now ruled,
  Q-2); cc2/cc3 sign-in before 09-14 (cc3 unauthenticated); DS4 nix residue
  (`/etc/local-models` symlinks, `home/pi.nix` DS4 row); `~/loops` ruling; consolidated project
  list never arrived (not in B or C either, VERIFIED).
- Two security items that bind any agent acting after the reboot (session A §5 item 12,
  VERIFIED): **revoke the disclosed Cloudflare token** (carried all session, never done); **do
  not reap `~/sept7`** — `tally-pump.service` execs `~/sept7/plan/codex-lane/pump.sh` every
  5 min and resumes after the reboot.
- Not this document (listed so they are not lost; session A §5): worker runtime leftovers
  awaiting yes/no (stale NM profiles, `/var/lib/{flashnext-rdma,tb-link-heal,usb4-stream}`,
  markers, `~/.cache/flashnext-rdma-build`); Qwen3.8-Flash-Next GGUF set on the NAS (89 GB)
  keep/delete; unfiled drafts SIFT-1..6 / BENCH-1..8 / K-1,K-2 / D-1..4; the four halogen brief
  §7 questions and the 24/7 worker consumer lane; finalize-tally line (dotfiles#362, tally#52,
  tally-ts-sdk#127/#133, six FT worktrees); midnight notes push; 2-generation retention change
  not implemented.
- dotfiles issue #353 (Zenbook Duo + MacBook Air M5 over USB-C): body READ (§2.2b). No bearing
  on §6; optional later follow-up (lan-mouse over `thunderbolt-net`) if a Mac is ever paired
  with the laptop. Q-9 is closed.

**Session B** (Claude `b98d7c74`, 2026-09-11 10:42–13:09Z; VERIFIED distillation; rulings live
in `queue-operation` records):

- Commits `f32289cb` and `7e544f5c` are this session's; PR #368 OPEN; coordinator never switched
  or rebooted (only TB heal/tripwire/lowlat units stopped).
- 10:55:34Z "ONLY the coordinator has a display output (and therefore needs the compositor)" —
  encoded as `hosts/worker/default.nix:88-89` (`programs.niri.enable = lib.mkForce false;
  services.greetd.enable = lib.mkForce false;`) and `home/remote.nix:53`
  (`lib.mkIf osConfig.programs.niri.enable`). A-6 supersedes it for the client only; the
  worker's header prose (`:35-37`) is superseded in the same commit as `hosts/client/`
  (step 3, historian §4.9) **(2026-09-11 pm)**.
- "delete, don't comment out; resurrection = gh history" (10:58:59Z). Applies to every retired
  artefact in §8.
- Thunderbolt as a fleet rail is dead forever, but `f32289cb` deliberately keeps the stock
  `thunderbolt` driver and bolt "for ordinary USB4 peripherals" (`hosts/coordinator/hardware.nix:14`
  comment; `modules/common.nix:256`). The Zenbook dock is exactly that use (INFERRED).
- Pending on the coordinator at switch time (DECISIONS.md operator acts): `nmcli connection
  delete tb-fleet tb-fleet2 eth-fleet`; `rm -rf /var/lib/{flashnext-rdma,tb-link-heal,usb4-stream}`;
  stale failure markers under `/var/lib/failure-markers`; `local-models-prune` to five files.
- Name resolution: `modules/fleet-hosts.nix` is TWINS ONLY (header, VERIFIED); the client needs
  NAS DNS (10.42.0.1) or its own `networking.hosts` for `coordinator`/`worker`/`nas`. The
  historian confirms no `zenbook-duo` row ever existed in that file (r-dotfiles-tenure §4.5) —
  `hosts/client/default.nix` must NOT import it **(2026-09-11 pm)**.
- The flake check `home-profiles` (`flake.nix:1829`, built at `:1953`, VERIFIED) carries the
  herdr assert block at `flake.nix:1858-1930`: `coordinatorHome.systemd.user.services ? herdr`
  (1858-1860, no `PartOf`, `WantedBy = default.target`), herdr-kitten in
  `coordinatorHome.home.packages` (1899), the `kitty-herdr-nix.conf` store-path text asserts
  (1908-1911), `!(workerHome.systemd.user.services ? herdr)` (1924, again 1999) and herdr-kitten
  in `workerHome.home.packages` (1930). A client row = a `clientHome` twin of the worker's
  negative herdr assert; **(2026-09-11 pm, R-16)** the herdr-kitten package assert is INVERTED
  for the client (hk is churn; the client runs bare `herdr --remote`, §5.2/§6.2). Same block,
  lines 1938-1944, asserts wayvnc present on the coordinator and absent on the worker, and
  niri+greetd ENABLED on the coordinator — all three are re-keyed on `myDisplay.enable` in
  step 3 so the flip (step 10) is a one-line change (§8.3).
- pi ran in-session with a private `PI_CODING_AGENT_DIR` pointed at 10.42.0.5 as a workaround
  for the unswitched coordinator (session B §5 item 5, VERIFIED) — clear it after the switch.

**Session C** (Codex `01a08a20`, 2026-09-10 07:05–16:38Z; VERIFIED distillation):

- Left the laptop as described in §2.2. Laptops left home ~12:44Z before endpoint migration.
- Rulings that still bind: ASUS + Dell stay on the private headscale (#42/#43) — now moot for
  the ASUS under R-1/R-2; no VPS/paid cloud; Freebox untouched; NAS-side omarchy updates "a few
  times per month"; retention current + previous.
- Offboarding facts: ~~delete headscale node 4~~ **SUPERSEDED by R-15 (2026-09-11 pm): node 4
  is KEPT (rename/retag optional, §3 O-3)**; drop `devices.zenbook-duo` from
  `omarchy-fleet/modules/fleet-registry.nix`; `agenix -r` on dotfiles (the OLD `…QoQJxxP` key was
  removed from the registry in `77eac406` but `wifi.age`, `wifi-lan.age`,
  `navidrome-credentials.age` were never re-minted — no commit touches those three ciphertexts
  after `77eac406` (`git log 77eac406..HEAD -- secrets/wifi.age secrets/wifi-lan.age
  secrets/navidrome-credentials.age` is EMPTY, VERIFIED); the only secrets commits since are
  `673b8d85` and `dc2c5d81`, both additions of other ciphertexts); ~~full wipe; NEW host key~~
  **SUPERSEDED by R-14 (2026-09-11 pm): the key stays, and the recommended install path has no
  wipe (§4.5)**.
- Ruling #47 (session C, 09-10, VERIFIED `c-users.txt:432`): "i gues i m good to remove:
  harness, zenbook-duo since they were literally put on a headscale suite and will never touch
  this again" — Tom removed the SaaS `zenbook-duo` node from the tailscale.com dashboard.
  Bears on Q-5 option (c) — moot since R-15 chose (b) **(2026-09-11 pm)**; ruling #47 stands
  untouched.
- Open: identity-archive decryption never rehearsed (`decryptionVerified:false`); PR #358/#360
  show OPEN although main already contains them; Plymouth failure on the ASUS uninvestigated.

---

## 3. Offboarding the Zenbook from the lent fleet

Ordered per `omarchy-fleet/docs/offboarding.md` (8 steps) with concrete identifiers. Marked
**[Tom]** = needs the device or a NAS/root action by Tom in person; **[agent]** = read-only or
repo edit a code-writing agent can do; **[irreversible]** where so. **(2026-09-11 pm)** Two of
the fleet's own offboarding steps are overruled for this device: step 7 "new offline-generated
host key … do not reuse" (`offboarding.md:26-27`, VERIFIED) is overruled by R-14, and the
headscale node delete by R-15. The name `zenbook-duo` in this section refers to the omarchy
install being removed, never to the dotfiles host (`client`).

| # | Step | Who | Notes |
|---|---|---|---|
| O-1 | **(2026-09-11 pm)** The laptop is unreachable at the time of writing (§2.2 live status); this step runs as soon as it answers on the LAN. Inventory while reachable: `hostname`, `cat /etc/ssh/ssh_host_ed25519_key.pub` (**R-14 gate: must equal the fleet registry row `…AoNjOhvz…`**; if it does not, STOP and report — the whole no-recreation premise rests on it), `nixos-version`, `uname -r`, `boltctl domains` (security string `+iommu` or not — Q-3), `libinput list-devices` and `niri`-equivalent evidence for which ELAN is the top panel is NOT possible under Hyprland; instead **undock the keyboard so BOTH panels are lit** (docked, Hyprland reports eDP-2 absent entirely — LEDGER A-19), run `hyprctl devices` and touch each panel to close omarchy-fleet LEDGER A-19 before the wipe (see §9; the two digitiser strings `elan9008:00-04f3:425b` / `elan9009:00-04f3:425a` were already measured on 2026-09-08, `omarchy-fleet/LEDGER.md:383-404` VERIFIED — only the panel pairing is open). While undocked, also record what the Duo's OWN keyboard emits under the daemon's `fn_lock = true` for F1/F2/F6-F8 and the mic key (`wev` or `libinput debug-events`): plain `F1..F12` or `XF86MonBrightness*`/`XF86Audio*` — decides the §5.2 XF86 row. Also `cat /sys/class/drm/card*-eDP-*/status`, `ls /sys/class/backlight`, `lsusb` with the dock attached (first-ever dock test, §7.1). | [Tom] on the laptop console or `nix run ~/mecattaf/omarchy-fleet#fleet-ssh -- zenbook-duo <cmd>` from the coordinator while both are on the LAN (VERIFIED script in omarchy-fleet `flake.nix:74-97`). | This is the only moment to gather metal facts cheaply; do it before O-6. |
| O-2 | Marwan's data: confirm Marwan never used it (handover.md says physical handoff pending). Nothing to export. | [Tom] one question to Marwan. | INFERRED safe. |
| O-3 | Stop offers on the NAS, KEEP the rail: run the publisher with `--devices xps` only from now on — the device list is the hard-coded constant `DEVICES = ("xps", "zenbook-duo")` at `hosts/nas/omarchy-update-publish.py:19`, with `--devices … default=list(DEVICES)` at `:217` (VERIFIED; the `omarchy-update-center.nix:31` usage string only echoes it). Until that constant is edited, a publish with no `--devices` builds BOTH devices, so the NAS edit must land BEFORE O-4 drops `hosts/zenbook-duo` from the fleet flake (else Omar's publish path breaks). The omarchy consent-update publish is for lent laptops only; `client` never appears in it. ~~`headscale nodes list` → `headscale nodes delete -i 4` (`zenbook-duo-fleet`)~~ **SUPERSEDED by R-15 (2026-09-11 pm): node 4 stays.** Instead: `headscale nodes list` (node 4 present, offline); optionally `headscale nodes rename -i 4 client` (cosmetic; the node's hostname is what `tailscale up --hostname` says, so set `--hostname client` on the dotfiles side too) and retag `tag:fleet` → `tag:mesh` (`headscale nodes tag -i 4 -t tag:mesh`) so ACLs treat it like the NAS's own node — verify the tag is not what the fleet ACL keys the xps on before removing it. `headscale preauthkeys list` → expire any outstanding fleet key (enrollment keys were 24 h single-use, so likely none). Also `headscale nodes list-routes` (or `headscale routes list`): the NAS node advertises `10.42.0.0/24` (`hosts/nas/headscale.nix:317,323`, VERIFIED) but approval is server-side and NOT verified — approve it here if it is not; §4.3 depends on it. `fleet-ssh zenbook-duo` keeps working until the dotfiles switch (step 6) removes the fleet's authorized-keys layout — after it, `ssh client` is the path. | [Tom] (root on NAS; ssh to another host is disallowed for agents). | Nothing irreversible any more. |
| O-4 | omarchy-fleet repo edits: drop `hosts/zenbook-duo/`, `profiles/zenbook-duo.nix`, `flake.nix` zenbook assertions (lines 154-214, 294, 409, 449-456 per fleet-hardware), `.github/rulesets/device-zenbook-duo.json`, `.github/scripts/path_guard.py:15 DEVICES`, `.github/ISSUE_TEMPLATE/support.yml` option, `docs/owners/marwan.md`, `devices.zenbook-duo` row in `modules/fleet-registry.nix`; add a "retired 2026-09-11, returned to dotfiles" row to `docs/handover.md` and a LEDGER entry. Keep `modules/zenbook-duo-daemon.nix`, `pkgs/zenbook-duo-daemon.nix`, `pkgs/patches/vmd-mtl016-7.2.4.patch`, `docs/zenbook-duo-boot-2026-09-10.md`, `docs/zenbook-duo-research.md` in git history as the reference (they are copied INTO dotfiles in §4.2; per the delete-don't-comment rule the fleet copies can go once dotfiles has them). Repo is unpublished (LEDGER holds a redacted passcode) so no GitHub rulesets are live. | [agent], in omarchy-fleet, AFTER §4 has landed in dotfiles (so nothing is lost). | Not a dotfiles change. |
| O-5 | Secrets: fleet side has no ciphertexts. dotfiles side: run `nix develop -c agenix -r` once the `client` registry row exists (re-mints every ciphertext for the current recipient sets, which both drops the historical `…QoQJxxP` exposure and admits `client`). **(2026-09-11 pm, R-14)** The recipient added is the REUSED fleet public key — no minting of any key, only re-encryption of the ciphertexts (`wifi-lan.age` and the four `delivered`-tier files, §4.1 I-3). | [Tom] (needs the admin age key). | Combined with §4.1 I-1/I-3; §10 step 4. |
| O-6 | ~~Disk wipe = the dotfiles disko reflash. Kills `marwan`, the fleet host key, the fleet tailscaled state, the consent client.~~ **SUPERSEDED (2026-09-11 pm, R-14): the recommended path is the in-place switch (§4.5 path A), which wipes nothing.** Under path A the omarchy closure is simply replaced: `marwan` disappears with the switch only if `users.mutableUsers = false` on the dotfiles side (not verified — grep of `modules/common.nix` found no setting; if users are mutable, `userdel -r marwan` by hand), and the residue to remove by hand is `/etc/fleet/marwan.passwd`, `/home/marwan`, `/var/lib/update-center-client*` (consent client), `/var/lib/tailscale-fleet` (AFTER its state file has been carried into `/var/lib/tailscale`, §4.1 I-8). The host key in `/etc/ssh/` is untouched by a switch. Path B (reflash) is the fallback only and then this row applies as written, with the private key and tailscale state extracted first. | [Tom]. | Do NOT accept `bc866db` and do NOT run `fleet-endpoint-migrate.py` on the omarchy install — the dotfiles side sets the control URL itself. |
| O-7 | Coordinator/NAS cleanups: the `zenbook-duo-lan` line in `~/.ssh/known_hosts` on the coordinator (fleet key `ssh-ed25519 …AoNjOhvz…`, VERIFIED present under that alias, not under `zenbook-duo-fleet` or a bare IP) — **(2026-09-11 pm, R-14)** the KEY is right and becomes `client`'s pinned key in `/etc/ssh/ssh_known_hosts` via the registry; only the alias line is stale, remove it once `ssh client` works TOFU-free (R-12: no `zenbook` alias survives); NAS `hosts/nas/omarchy-update-publish.py:19` `DEVICES` → `("xps",)` and the `:31` usage string in `omarchy-update-center.nix`; dotfiles `docs/nas/personal-tailscale.md:129` already records the stale SaaS `zenbook-duo` node removed 09-10 (verify with `tailscale status` on the coordinator). | [agent] for the repo lines; [Tom] for known_hosts. | |
| O-8 | Attic: nothing device-specific to revoke (cache `fleet` is `--public`); zenbook closures expire on the 1-month rule. | — | |
| O-9 | Passcode hygiene: delete the scratchpad extract `c-users.txt` (and the other `c-*.txt`/`sess*.txt` extracts) once this document is signed; redact the passcode line in the session C JSONL (`~/.codex/sessions/2026/09/10/rollout-…01a08a20….jsonl`) BEFORE any harvester, drain or transcript mirror touches it (session A heuristic: transcripts are harvested and mirrored as "part of my bench"); decide whether Omar's Dell passcode is rotated at his next consented update (it is live and was typed in the same message). | [Tom] for the JSONL and the Dell decision; [agent] for the scratchpad files. | The ASUS value dies with `marwan`'s removal (O-6, by hand under path A **(2026-09-11 pm)**); the Dell value does not. |
| O-10 | omarchy-nix bookkeeping: `FINALIZATION.md:8` still scopes "ASUS Zenbook Duo UX8406MA for Marwan" as the September 10 mandate (VERIFIED). Add a LEDGER/SPEC entry "Zenbook retired to dotfiles 2026-09-11; scope = XPS only". State explicitly that the Dell/Omar side SURVIVES: the Dell is still on `470fae7f`, its control URL un-migrated, `bc866db` unaccepted (session C), and it is now the sole reason the NAS headscale + omarchy-fleet plane stays alive; the Dell threads (endpoint migration, `bc866db`, fingerprint) are untouched and still owed to Omar. | [agent] in omarchy-nix; [Tom] owns the Dell threads. | Not a dotfiles change. |

What to keep from omarchy-fleet as reference (read, not import): `profiles/zenbook-duo.nix`,
`hosts/zenbook-duo/hardware.nix`, `modules/zenbook-duo-daemon.nix`, `pkgs/zenbook-duo-daemon.nix`,
`pkgs/patches/vmd-mtl016-7.2.4.patch`, `docs/zenbook-duo-boot-2026-09-10.md`,
`docs/zenbook-duo-research.md`, `docs/flash.md` (kexec radio-unload recipe, BootOrder phantoms),
LEDGER R29–R42; omarchy-nix `research/wave2/zenbook-duo-hardware.md`.

---

## 4. Re-admitting the laptop into dotfiles as `client` (R-12)

**(2026-09-11 pm, R-17) Framing: `hosts/client/` = the coordinator's config MINUS the
coordinator-only gates PLUS the Duo hardware layer.** Everything in `modules/common.nix` is
inherited by importing it — greetd autologin tom → niri (`modules/common.nix:210-234`, VERIFIED:
`initial_session` at `:230-233`, the `agreety` `default_session` at `:217-220` is for user
`greeter`; "no sddm, ever" is already the fleet default), niri, VT getty recovery, the
`nas:8080/fleet` substituter, the 10.42.0.1 DNS pin, bluetooth, printing client, fonts. The
gates that keep coordinator-only things off the client, and what each becomes:

| Gate site (VERIFIED `grep`) | What it guards | Predicate for the client era |
|---|---|---|
| `home/home.nix:93` | python extras `click`, `pytest` (CLI-Anything harnesses) | stays `hostName == "coordinator"` (agent tooling) |
| `home/home.nix:311` | atuin `sync_address` localhost vs `http://coordinator:27321` | stays; the client's shell is an escape hatch, its `auto_sync` assert is OFF (§4.3 Firewall) |
| `home/home.nix:346`, `:364` | NAS Nautilus bookmarks, `xdg.userDirs` on the NFS automount | stays coordinator-only |
| `home/home.nix:509` | `fara-cli` | stays coordinator-only |
| `home/voxtype.nix:66,151,157` | voxtype + OSD | coordinator-only today; needs a display AND a mic — after the flip it has neither, so it is keyed on `myDisplay.enable && hostName == "coordinator"`, i.e. inert from step 10 (Q-1 default (c)) |
| `home/tally.nix:19`, `tally-pump.nix:97`, `tally-filler.nix:97`, `tally-uplink.nix:110`, `seat-feeder.nix:65`, `util-sampler.nix:48`, `paper.nix:13`, `harness-records.nix:25` | the tally-* / seat / util / paper plane (`isCoordinator`) | stays coordinator-only |
| `home/herdr.nix:85` | herdr SERVER | stays coordinator-only; the `herdr` binary is delivered everywhere (the client needs it for `--remote`) |
| `home/herdr.nix:62-64,77` | herdr-kitten (`hk`) package + kitty `action_alias hk` | **NEW gate `hostName != "client"`** (R-16: hk is churn; the client runs bare `herdr --remote`) |
| `hosts/coordinator/{atuin,attic,nas-client,services,tailscale,uplink-nas,journal-upload,audio}.nix` | atuin server, attic, immich/navidrome relays, caddy artifact plane, halogen client (`utility-model`), microvm host, tally-b, tailscale.com rail | scoped by IMPORT (only the coordinator imports them, VERIFIED `ls hosts/coordinator`) — nothing to gate; none of it is in the client closure |
| `home/home.nix:386-395` `dcal-daemon` | no gate at all — WOULD start on the client | **NEW gate `hostName == "coordinator"`** |
| `home/home.nix:260` `xdg.desktopEntries` (Chrome PWAs), launcher entries | fleet-wide | **NEW gate `hostName != "client"`** (R-16 churn; the client gets plain Chrome — if Tom wants the SoundCloud scratchpad PWA on the client it is one line, but the default is off) |
| `modules/printing.nix` (via `modules/common.nix:20`) | CUPS + Brother queue, fleet-wide | **NEW gate**: not imported by the client (R-16 "printing stays coordinator-side"); printing from the client = print from the coordinator |
| `~/.claude/skills`, `home/pi.nix`, Claude/Codex CLIs | agent surface | not on the client (§0 invariant 1; `modules/secrets.nix:29` OAuth ruling stands) |
| `home/remote.nix:53` (`mkIf niri.enable`) | wayvnc server + Remmina client/profiles | split on **`myDisplay.enable`**: Remmina client where there is a seat; the wayvnc unit `hostName == "coordinator" && myDisplay.enable`, deleted outright at the flip commit (§8.3) |
| `flake.nix:1938-1944` | wayvnc/niri/greetd asserts hard-coded on coordinator=on, worker=off | re-keyed on `myDisplay.enable` per host (step 3) |
| piri, kanshi, wl-gammarelay-rs, swaybg, cliphist watchers, xcursor, GTK theme | fleet-wide under niri | already inert where niri is off (`niri/startup.kdl` spawns die with the session); no gate needed, `myDisplay.enable` is the NixOS-level truth they follow |

`myDisplay.enable` (new option, introduced in the FIRST code step per R-13): true on `client`,
true on `coordinator` until the flip commit sets it false, false on `worker`/`nas`. It drives
`programs.niri.enable`, `services.greetd.enable`, the `home/remote.nix` split and the three
flake asserts — so the flip is one line in `hosts/coordinator/default.nix`.

### 4.1 Identity (mesh-registry, secrets, flake node, deploy, update-center pull)

All VERIFIED against HEAD unless marked.

| Step | File / mechanism | What changes | Constraint |
|---|---|---|---|
| I-1 | ~~New host key: generate `ssh-ed25519` offline into the operator staging bundle … NEVER reuse the fleet key (offboarding.md step 7)~~ **SUPERSEDED by R-14 (2026-09-11 pm).** `client` keeps the key on the laptop today: the fleet key `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAoNjOhvz1H+SO5AhDdb4Z1FZlzUC+/KlMR1Oa7V0+YM root@zenbook-duo` (VERIFIED on the metal via the coordinator's `known_hosts:25`, §2.2). Nothing is minted, nothing is delivered: under the in-place path (§4.5 A) `/etc/ssh/ssh_host_ed25519_key` is simply not touched; under the reflash fallback (B) the private half is extracted from the running laptop into the `--extra-files` bundle first. The 2026-07-05 `…QoQJxxP` key is NOT on the laptop and is not reused. | `modules/mesh-registry.nix` new row `client = { aliases = ["client" "<LAN ip>"]; hostKey = "ssh-ed25519 …AoNjOhvz1H+SO5AhDdb4Z1FZlzUC+/KlMR1Oa7V0+YM root@zenbook-duo"; userKey = <shared tom@mesh-20260729>; }` (shape identical to the coordinator/worker rows at lines 19-56). The `root@zenbook-duo` comment is inert; leave it. | The registry row alone regenerates `~/.ssh/config`, `known_hosts`, `authorized_keys` and Remmina profiles fleet-wide (`home/ssh.nix`, `modules/mesh.nix`, `home/remote.nix`). `ssh client` from the coordinator is TOFU-free from the first switch because the key never changed. |
| I-2 | Flake roll-call: `flake.nix:2385-2394` defines `activeHostSets` (attrNames of `nixosConfigurations`, `deploy.nodes`, `meshRegistry` — alphabetically sorted) and `expectedHosts = ["coordinator" "nas" strixWorker]`; `:2416` asserts LIST EQUALITY `hosts == expectedHosts` for all three (VERIFIED), so ORDER MATTERS. **(2026-09-11 pm, R-12 correction)** ~~append `"zenbook-duo"` AFTER `strixWorker`~~ — `"client"` sorts BEFORE `"coordinator"` (`"cl" < "co"`), so `expectedHosts = ["client" "coordinator" "nas" strixWorker]`. The three-way agreement is the historian's headline touch-point (r-dotfiles-tenure §4): all three registries in ONE commit or `nix flake check` is red. Add `client = mkHost { hostModule = ./hosts/client; }` (shape at `77eac406^:flake.nix`), add the deploy-rs node with `hostname = "client"` — `:2480-2481` assert `deploy.nodes.<h>.hostname == "<h>"` for coordinator/nas and the client node must match that shape (name resolved via NAS DNS or `networking.hosts`); deploy-rs is never USED for the client (R-16, I-5) but the roll-call requires the node. Add the `clientHome` asserts modelled on `77eac406^`'s `zenbookHome`: tally off, voxtype off, wayvnc — INVERT to "absent" (A-3; the historian flags this as a genuine reversal of the old zenbook precedent, which asserted its own wayvnc PRESENT), ntm — NOT asserted (R-17: out of scope), atuin `auto_sync` — assert OFF for the client (the coordinator's `:27321` door is `tailscale0`-only, `hosts/coordinator/atuin.nix:10` VERIFIED, and R-16 says do not grow the client for its shell). In the `home-profiles` herdr block (`flake.nix:1858-1930`) add the client row: `!(clientHome.systemd.user.services ? herdr)` and **`!(builtins.elem herdr-kitten clientHome.home.packages)`** (R-16, inverted from the worker's positive assert at `:1930`). | `flake.nix` in ONE commit with I-1. | `nix flake check` is red until all three registries agree. |
| I-3 | Secrets tiers: `secrets.nix:43` `delivered` is derived from the registry (every non-nas host) so `env`, `ssh-user-key`, `atuin-key`, `tom-password-hash` are admitted automatically. Add `clientOnly = nonEmpty [ registry.client.hostKey ]` and set `wifi-lan.age` (`secrets.nix:109`, currently `editors ++ coordinatorOnly ++ workerOnly`) to `editors ++ coordinatorOnly ++ clientOnly` — i.e. ADD the client and DROP `workerOnly` in the same rekey, discharging DECISIONS.md 2026-09-11 operator act (4) "the worker's recipient on secrets/wifi-lan.age is now unused and can be dropped at the next rekey" (lines 79-80, VERIFIED; the worker is wired-only on `enp191s0`, no wifi profile). Rewrite the stale comment block `secrets.nix:96-108` (it still claims three recipients including the zenbook and calls thomas-6ghz the worker's "only path onto the house LAN"). Put `clientOnly` on `wifi.age` (`:95`, currently `coordinatorOnly`) only if the laptop should roam on the Freebox wifi too (default no). The wifi-lan delivery gate is `modules/secrets.nix:428-447` — `builtins.elem config.networking.hostName [ "coordinator" … "worker" ]` at `:434-442` (VERIFIED): add `"client"`, remove `"worker"` and its comment in the same commit. `navidrome-credentials` delivery (`modules/secrets.nix:324-334`) is coordinator-only; leave it (thin client, cliamp stays on the coordinator, §5.2). (Earlier draft cited `:387` and `:310`; those are the `immich-api-key` and `hf-token` gates — corrected.) Claude OAuth deliberately NOT delivered (`modules/secrets.nix:29` ruling 2026-07-12 stands: agents run on the coordinator; the historian notes the old reasoning assumed a laptop running Claude locally — the thin client has no session to race at all, so the exclusion holds for a simpler reason). **(2026-09-11 pm, R-14)** The recipient is the reused fleet public key; `agenix -r` re-encrypts, nothing is minted. | `secrets.nix`, `modules/secrets.nix`, then `nix develop -c agenix -r` (O-5). | Activation fails on the laptop if any delivered ciphertext is not re-minted. |
| I-4 | Host module: `hosts/client/{default,hardware,disko}.nix` **(2026-09-11 pm, R-12)** — start from `git show 77eac406^:hosts/zenbook-duo/default.nix` (95 lines; VERIFIED shape: nixos-hardware `common-cpu-intel`/`common-pc-laptop`/`common-pc-laptop-ssd`, `thomas-6ghz` `ensureProfiles` from `wifi-lan.age`, `i915.enable_psr=0`, asusd, thermald, iio, iHD) and replace the hardware layer with §4.2. `disko.nix` from `77eac406^` (1G ESP vfat `umask=0077` at `/boot` + ext4 100% at `/` on `/dev/nvme0n1`, disk name `main`) is BYTE-IDENTICAL in content to omarchy-fleet's `lib/laptop-disko.nix` (VERIFIED by reading both) — same `disk-main-ESP`/`disk-main-root` partlabels (INFERRED from disko's naming), which is what makes the in-place switch (§4.5 A) mount the existing filesystems without a reflash. Both sides boot with systemd-boot (`modules/common.nix:53`, `omarchy-fleet/modules/fleet-common.nix:48`, VERIFIED), so the switch adds a dotfiles generation to the same ESP and the omarchy generations stay selectable as a rollback until GC. Imitate the worker's "WHAT IT IS NOT" header (historian §4.9): not a tailscale.com node, not a build pusher, not a DNS island, not an agent host, not a tally executor, not on any automatic switch — and supersede the worker header's "ONLY the coordinator has a display output" in the same commit. | new files | `mySecrets.enable = true`; `networking.hostName = "client"`; `myDisplay.enable = true`. Do NOT import `modules/fleet-hosts.nix` (twins only) nor `modules/headless.nix` nor `modules/printing.nix` (R-16). |
| I-5 | **(2026-09-11 pm, R-16 rewrite.)** Update path: NONE that is automatic. ~~pull, not push … "Tom, or an agent over `ssh zenbook sudo nixos-rebuild switch …`"~~ — the client is on NO pull timer, NO deploy-rs push, NO catch-up unit (the historian records that `c0ebbf71`→`4698216d` built and killed exactly such a laptop-specific mechanism in six days: "a laptop is just a member that's sometimes offline"), and `nixos-rebuild switch` on it is an explicit act of Tom's, expected "VERY FEW if any" times. The NAS MAY still build its closure nightly for cache warmth: add `"client"` to `hosts/nas/update-center.nix:47` `hosts = ["coordinator" "worker"]` (the historian confirms the zenbook was NEVER on this list — new territory, not resumption; `update-center.nix:11-15` "activation stays a per-device pull" already means "nothing activates by itself"). Still true (VERIFIED): (1) the nightly resolves `github:mecattaf/dotfiles/main` (`update-center.nix:65`), so the closure exists in attic only once the work reaches `main`; (2) off-LAN the substituter falls through (`modules/common.nix:82-83` `connect-timeout = 5; fallback = true`) — never switch the client off-LAN; (3) `modules/gc-retention.nix:41` keeps 20 generations fleet-wide — irrelevant for a host that rebuilds rarely. **herdr version coupling (operator rule, now sharper):** the herdr client and server speak a versioned protocol (herdr-kitten `hk/herdrc.py:15` "protocol 21", VERIFIED; `herdr` binary pinned by `flake.lock` rev `b99002ac`). Since the client rarely switches, a herdr input bump on the coordinator that changes the protocol version ALSO obliges a client switch — that is the one event that forces a client update; bump the coordinator first, then the client, in the same sitting. The NAS building the client closure from `main` is what makes that second switch a cache hit. | `hosts/nas/update-center.nix`; an operator rule in the herdr bump procedure | NAS eMMC once failed a zenbook build (`docs/nas/emmc-relief-2026-08-22.md:21`); the build plane has since moved (`c712b2e7`). |
| I-6 | Operator nickname: `home/ssh.nix:44-51` `operatorAliases` gains `client = "client"` — an identity map like the other three (RHS must be a registry attr: `unknownTargets` defined at `home/ssh.nix:53`, asserted at `:97`). ~~`zenbook = "zenbook-duo"`~~ **SUPERSEDED by R-12 (2026-09-11 pm): no `zenbook` nickname**; the `:18-21` history note ("the one nickname that ever differed was `zenbook`") stays as history. Also edit `needsJump` (`:72`): today it adds `ProxyJump coordinator` to `nas` for every host that is not nas/coordinator, which for the client would route `ssh nas` through a coordinator that is NOT reachable off-LAN except via the NAS itself — a loop. The file's own comment (`:69-71`) already anticipates this: "at that point the jump becomes unnecessary for clients on that plane". Set `needsJump = target: target == "nas" && !(builtins.elem hostName [ "nas" "coordinator" "client" ])`. | `home/ssh.nix` | See §6.2 for the coordinator-side block the client needs; §4.3 for why no `Match`/`ProxyJump` is needed for `coordinator`. |
| I-7 | journal-upload: `hosts/nas/journal.nix:46-60` allowlists 10.42.0.2 and 10.42.0.5 only, with a comment that the rule was written to EXCLUDE the roaming zenbook ("the rule stands for any future mobile member", historian §3). Admitting the client is a deliberate ruling (Q-8). **Default (2026-09-11 pm): no.** | — | |
| I-8 | **(2026-09-11 pm, R-15) Headscale rail on the dotfiles side.** `hosts/client/default.nix`: `services.tailscale.enable = true; useRoutingFeatures = "client"; extraUpFlags = [ "--login-server=https://nas-saas.tail8dd1.ts.net:8443" "--accept-routes" "--hostname=client" ]` (the NAS's own block at `hosts/nas/headscale.nix:313-324` is the in-repo model: `--login-server` ONLY in `extraUpFlags`, never `extraSetFlags`, VERIFIED comment `:300-304`). Kernel TUN, not the fleet's userspace unit, because `--accept-routes` must install the NAS's `10.42.0.0/24` route into the kernel (§4.3). `modules/secrets.nix:169-180` auto-wires a tailscale.com auth key ONLY if `secrets/tailscale-authkey-client.age` exists — do NOT create that file (its own comment `:165-167` says so; R-15 is headscale, not tailscale.com). Enrolment: path A carries the existing node (copy `/var/lib/tailscale-fleet/tailscaled.state` → `/var/lib/tailscale/tailscaled.state`, root-only, BEFORE the switch, then `fleet-endpoint-migrate.py`'s edit — `ControlURL` → the Funnel URL — applied to the carried file, or simply `tailscale up --login-server=<funnel> --force-reauth` with a fresh `headscale preauthkeys create -u <user> --reusable=false -e 1h` if the carried state refuses the URL change; INFERRED that the state file is portable between the two daemons — same tailscale binary family, same JSON prefs — verify with `tailscale status` showing `100.64.0.4`). Path B re-enrols with a new pre-auth key and node 4 is then expired by hand. Either way the ACL must let the client reach the NAS's subnet route; `headscale nodes list-routes` must show `10.42.0.0/24` APPROVED (O-3). | `hosts/client/default.nix`; NAS root commands in O-3 | Off-LAN control-plane reachability (Funnel 8443) has never been exercised by a real laptop (`docs/nas/personal-tailscale.md:50`) — §10 step 14 is the first time. |

### 4.2 Hardware layer — restoration inventory merged with omarchy-fleet's newer findings

Legend: DOT = `git show 77eac406^:hosts/zenbook-duo/…`; FP = `omarchy-fleet/profiles/zenbook-duo.nix`;
FH = `omarchy-fleet/hosts/zenbook-duo/hardware.nix`; FD = `omarchy-fleet/modules/zenbook-duo-daemon.nix`
+ `pkgs/zenbook-duo-daemon.nix`; BOOT = `omarchy-fleet/docs/zenbook-duo-boot-2026-09-10.md`.
Verdict: CARRY = into `hosts/client/` **(2026-09-11 pm, R-12)**; ADAPT = mechanism moves; DROP = Omarchy-only.

| Item | Source | Verdict | Notes |
|---|---|---|---|
| `boot.initrd.availableKernelModules = [xhci_pci thunderbolt vmd nvme usbhid usb_storage sd_mod]` | DOT hardware.nix = FH | CARRY | `vmd` is load-bearing (root invisible without it); `thunderbolt` stays — this is the docking host. `nixos-anywhere --generate-hardware-config` DELETES `boot.initrd.kernelModules` (omarchy flash.md Step 2) — never pass it. |
| `boot.initrd.kernelModules = [mei mei_me mei_gsc_proxy i915]` | FH (DOT had only `i915`) | CARRY | Early i915 = reliable dual-eDP modeset (DOT `1c718bb0`); early MEI = GSC proxy binds before i915's 20 s deadline when storage stalls (BOOT). Dependency fix, not the stall fix. |
| `boot.kernelModules = [kvm-intel]`, microcode | DOT = FH | CARRY | |
| `hardware.cpu.intel.npu.enable = true` | DOT hardware.nix:33 = FH :48 (both VERIFIED present) | **DROP** — deliberate departure from both prior incarnations, recorded here | AGENTS.md: "The NPU path is decommissioned — permanently, 2026-08-29 … Do not add a `flm` invocation, an `flm serve` unit, or an NPU backend row back" (VERIFIED). That ruling is worded for the XDNA2 twins, but a thin client with all inference on the worker has zero consumer for Intel NPU firmware; re-enabling it reintroduces the surface the ruling closed. **Default (2026-09-11 pm, R-18): DROP stands unless Tom says otherwise before step 3.** |
| `boot.kernelParams = ["i915.enable_psr=0"]` | DOT = FP | CARRY | i915 is bound, xe idle; `xe.enable_psr` would be a silent no-op. |
| Kernel series + VMD MTL016 patch | FH `boot.kernelPatches = [vmd-mtl016-7.2.4]`, `omarchy-fleet/pkgs/patches/vmd-mtl016-7.2.4.patch`, `modules/fleet-kernel.nix` pin `linuxPackages_7_2` at nixpkgs `d9ed7310` | ADAPT | dotfiles default is `linuxPackages_latest` (`modules/common.nix:52`, mkDefault); twins override in `modules/strix.nix:158`; NAS pins `linuxPackages_7_2` via `freshPkgs` (`hosts/nas/kernel.nix:5`). Recommendation: the Zenbook pins `linuxPackages_7_2` the NAS way and carries the patch as `pkgs/patches/vmd-mtl016-7.2.4.patch` + `boot.kernelPatches`; the patch is 7.2.4-specific and "not yet kernel-built or boot-validated" (patch header). Q-4. Until validated, expect intermittent ~5 min boots; that is a wait, not a brick. |
| e2fsck `broken_system_clock = 1` in `/etc/e2fsck.conf` AND `boot.initrd.systemd.contents."/etc/e2fsck.conf"`, `boot.initrd.systemd.emergencyAccess = true`, `services.timesyncd.enable = true` | FP | CARRY | No RTC retention: battery drain resets clock to 2024; fsck refused "last write time in the future" and initrd sat in emergency mode with no shell. Requires systemd initrd (INFERRED — confirm dotfiles' initrd flavour). `hwclock` hangs without `--directisa`; wrap in `timeout` if ever scripted. |
| `services.asusd.enable = true` + `systemd.tmpfiles.rules = ["d /etc/asusd 0755 root root -"]` | DOT (asusd) + FP (tmpfiles) | CARRY | Without the dir the unit dies `status=226/NAMESPACE` (LEDGER R37). Charge limit never set (`charge_control_end_threshold = 100`). |
| `systemd.services."systemd-backlight@backlight:asus_screenpad".enable = false` | FP (`3b3e847`) | CARRY | Driver reports 130816/255, unit fails every boot; `suppressedSystemUnits` proven insufficient (2026-09-10). `home/dot_local/bin/brightness` already skips non-DRM backlights (`drm_backlights()` filters on `*/drm/*`, lines 26-34 VERIFIED), so this defect has NO bearing on F10 (§5.2). |
| logind lid semantics (`services.logind.settings.Login.HandleLidSwitchDocked`) | NEW — dotfiles sets no lid option anywhere (VERIFIED grep of `modules/`, `hosts/`, `home/*.nix` and `77eac406^:hosts/zenbook-duo/default.nix`) | DECIDE (Q-15) | systemd 261.2 `logind.conf(5)` (VERIFIED from the store man page): "If the system is inserted in a docking station, or if more than one display is connected, the action specified by `HandleLidSwitchDocked=` occurs", and it defaults to `ignore`. Keyboard detached → both eDPs connected → two displays → lid close does NOT suspend, and niri "will already automatically turn the internal laptop monitor on and off in accordance with the laptop lid" (niri 26.04 wiki `Configuration:-Switch-Events.md:28`, VERIFIED) → eDP-1 off, every window migrates to eDP-2, the panel UNDER the closed lid. Keyboard snapped on → the daemon has forced eDP-2 disconnected → one display → lid close suspends. On the TB dock the "docking station" clause may apply too. Inconsistent by construction; pick `"suspend"` everywhere (default recommendation) or `"ignore"` everywhere with F10/brightness-0 as the explicit verb, and add a niri `switch-events { lid-close { spawn … } }` hook only if the eDP-1-off behaviour needs countering. |
| `services.thermald.enable = true`; `hardware.graphics.extraPackages = [intel-media-driver]`; `LIBVA_DRIVER_NAME = "iHD"` | DOT = FP | CARRY | |
| `services.upower = { percentageAction = 5; criticalPowerAction = "PowerOff"; }` | FP | CARRY | No swap → no hibernate (fleet A-06). |
| nixos-hardware `common-cpu-intel`, `common-pc-laptop`, `common-pc-laptop-ssd` | DOT = FP | CARRY | No UX8406 module upstream. `common-pc-laptop` does NOT enable bolt. |
| `systemd.user.services.niri.serviceConfig.TimeoutStartSec = lib.mkForce "120"` | DOT | CARRY | jul5 "diagnostic rope, NEEDS LIVE VERIFY"; harmless. omarchy's Hyprland twin of this line is DROP. |
| zenbook-duo-daemon (PegasisForever v1.2.0, rev `7955be86…`, hash `sha256-ucyjhbF/…`; USB `0b05:1b2c` attach → `off` to `/sys/class/drm/card1-eDP-2/status`, detach → `on`; 500 ms backlight sync `intel_backlight` → `card1-eDP-2-backlight`; Fn/brightness/mic/emoji keys; suspend pipe) | FD + pkgs | CARRY as `modules/zenbook-duo-daemon.nix` + `pkgs/zenbook-duo-daemon.nix` | CONFIRMED compositor-agnostic (writes DRM force-status → real hotplug uevent; no hyprctl). dotfiles never had an equivalent (ntm filled the slot, never auto-started). Two consequences: (a) kanshi needs a docked sibling profile (eDP-1 alone at scale 2; the existing `Laptop` profile is scale 1.5 for the XPS) — `DuoDocked`; (b) the 500 ms sync overwrites eDP-2's backlight, so Shift+F1/F2 `brightness … focused` on eDP-2 is ineffective unless sync is disabled (INFERRED, Q-6). Fork-and-pin into mecattaf/ still open (fleet A-18). |
| zenbook-duo-rotate (`hyprctl eval hl.monitor`, iio via `net.hadess.SensorProxy`) | `omarchy-fleet/modules/zenbook-duo-rotate.nix` | DROP (Hyprland-specific) | **OUT OF SCOPE TODAY (2026-09-11 pm, R-17: "multitouch and old rotation things are not in scope for today").** Recorded for later only: `hardware.sensor.iio.enable = true` (DOT had it), dock-gating, transform mapping normal/left-up/bottom-up/right-up → `niri msg output eDP-1 transform 0/90/180/270` (INFERRED syntax); ntm (`22eebdc0^:home/ntm.nix` + flake input) shipped inert for its whole tenure and is NOT restored (historian §2). D-5. |
| `omarchy.monitors`/`omarchy.scale`, SDDM + `fleet-seat.nix`, `fleet-browser/onboarding/ai-apps/update-center-client/fleet-rail/failure-surfacing/tripwire/rollback-offline/fleet-boot-order`, `marwan` account, `fleet-kernel.nix` input, wifi via `--extra-files` bundle | omarchy-fleet | DROP | kanshi `Duo` replaces monitors; greetd autologin tom → niri from `modules/common.nix:210-234` (the tom autologin is `settings.initial_session` at `:230-233`; `:217-220` is the `agreety` `default_session` for user `greeter` — VERIFIED) — **R-17 "no sddm, ever" is already the fleet default, inherited by importing common (2026-09-11 pm)**; wifi via `ensureProfiles` + `wifi-lan.age`. `fleet-rail` is replaced by I-8, not dropped without successor. |
| Touch mapping (`programs.niri.package = pkgs.niri-pr1856`, overlay attr from `22eebdc0^:overlays/default.nix:33-65`, `niri-local.kdl` per-device blocks from `22eebdc0^:home/home.nix:168-185`) | DOT + `22eebdc0^` | DROP for now (R-10); **recorded recovery path (2026-09-11 pm, R-17)** | The overlay is `niri-pr1856 = final.niri.overrideAttrs` on `stefanboca/niri` rev `3b75b961…` with `cargoDeps` re-vendored (hashes in the commit), `doInstallCheck = false`; the per-device blocks are `input { touch "ELAN9008:00 04F3:425B" { map-to-output "eDP-1" } touch "ELAN9009:00 04F3:425A" { map-to-output "eDP-2" } }` with the pairing UNCONFIRMED on metal (dotfiles#67; O-1 closes it). Resurrect only if the global `map-to-output` mitigation (§4.4) proves unlivable. See §9 D-1. |
| AdGuard import | removed `ef70e0a6` 2026-08-21 | DROP, never re-add | Per-device AdGuard is forbidden on this LAN (dns_hijack collision, `hosts/worker/default.nix` header). |
| `hardware.sensor.iio.enable = true` | DOT | CARRY (cheap) | Only consumer would be rotation (deferred). |
| Flash facts | omarchy flash.md | reference | kexec needs `iwlmvm iwlmld iwlwifi btusb btintel btrtl btbcm btmtk` unloaded + FLR on the wifi function; else cold-boot USB. NVRAM has phantom "Linux Boot Manager" entries; anchor on the ESP PARTUUID, reorder never delete. Installer takes a different DHCP lease than the OS (DUID) — match on MAC `a0:b3:39:06:75:a7` in dnsmasq leases. 6 GHz WPA3 re-association after an NM restart takes >90 s (LEDGER R33): deploy confirm timeouts ≥300 s. |

### 4.3 Network

| Topic | Decision / state |
|---|---|
| House LAN | `thomas-6ghz` NM profile via `ensureProfiles` with `$BE550_SSID/$BE550_PSK` from `wifi-lan.age` (shape at `77eac406^:hosts/zenbook-duo/default.nix`; the worker's profile "was modelled on the zenbook's"). Gate at `modules/secrets.nix:428-447` + recipients at `secrets.nix:109` (I-3). INFERRED check: the SSID/PSK in `wifi-lan.age` are still the live 6 GHz network after `26d4afdf` "retire BE550 router" — the BE550 is now in router mode at 10.42.0.3 behind the NAS (session C 11:15Z), so the SSID likely survived; verify at flash. DHCP from the NAS (10.42.0.1); pin a dnsmasq `dhcp-host` on MAC `a0:b3:39:06:75:a7` in `hosts/nas/router.nix` for a stable LAN address to put in the registry aliases (same pattern as the worker's `9c:bf:0d:01:cc:65` pin from PR #369). |
| Name resolution | `coordinator`, `worker`, `nas` must resolve on the client. `modules/fleet-hosts.nix` is twins-only and the client must NOT import it (historian §4.5); use `networking.hosts` in the host module (`10.42.0.2 coordinator`, `10.42.0.5 worker`; `nas` = 10.42.0.1 is already fleet-wide in common.nix) — static entries, not NAS dnsmasq names, so the same names resolve off-LAN through the subnet route. `desk` (= `herdr --remote coordinator`) and the ssh `coordinator` block key on the name `coordinator`. |
| Tailnet rail | **(2026-09-11 pm) Q-5 ANSWERED by R-15: option (b), NAS headscale, existing enrolment kept.** ~~Three options … Recommendation: (a) for the first flash; (c) only if Tom explicitly overturns the 09-10 ruling~~ — superseded. Facts the design rests on (VERIFIED): the NAS's own node advertises `10.42.0.0/24` (`hosts/nas/headscale.nix:317,323`, `useRoutingFeatures = "server"`); headscale's DNS comment says roaming clients reach the LAN "through the subnet route this node advertises" (`:194`); the control server has a public Funnel endpoint `https://nas-saas.tail8dd1.ts.net:8443` (`hosts/nas/default.nix:120-121`; `docs/nas/personal-tailscale.md:50` "actual off-LAN laptops pending"); the coordinator is NOT on headscale (`hosts/coordinator/tailscale.nix`, tailscale.com only) so the client can never address it tailnet-to-tailnet ("two nodes on different control planes share no netmap", `home/ssh.nix:64-66`). Design: the client runs kernel-mode tailscale with `--accept-routes` (I-8). **On the LAN**: the wifi interface holds a connected `10.42.0.0/24` route in the main table, and tailscale's Linux policy routing (`ip rule … lookup main suppress_prefixlength 0` ahead of its table 52 — INFERRED from tailscale's documented design, not re-read) lets that more-specific local route win, so `coordinator` = 10.42.0.2 goes straight out the wifi with no tailnet involved — exactly R-15's "on the thomas-6ghz wifi it has no need for it". **Off-LAN**: no connected /24 exists, table 52 sends 10.42.0.2 into `tailscale0` → NAS (100.64.0.1) → its LAN leg → the coordinator; the NAS SNATs subnet-routed traffic by default, so the coordinator sees 10.42.0.1 as the source. One address, one name, one ssh block, both places. Verification: `ip route get 10.42.0.2` shows `dev wlan…` at home and `dev tailscale0` on a phone hotspot (step 14). Ruling #47 (the SaaS `zenbook-duo` node removed 09-10) stays untouched; no `tailscale-authkey-client.age` is ever minted. |
| ssh.nix `coordinator` block for the client | **(2026-09-11 pm, R-15)** Two candidate shapes were weighed. **(1) Subnet route, no ssh_config logic (RECOMMENDED):** the registry-driven block stays exactly `HostName coordinator` (→ 10.42.0.2 via `networking.hosts`); routing decides the path (row above). Zero moving parts in ssh; herdr's generated ssh config (which includes `~/.ssh/config`, VERIFIED `herdr --default-config`) needs nothing special; the pinned host key is checked on the same name in both places. **(2) `Match host coordinator !exec "on-lan-test"` → `ProxyJump nas`:** works without the subnet route but spawns a probe process on EVERY `ssh coordinator` (herdr reconnects, every plain `ssh`), adds a hop and a second control socket through the NAS, and `programs.ssh.settings` is a flat `Host`-block map (`home/ssh.nix:101-106`) with no `Match` slot — it would need `extraConfig`. Not recommended; keep as the fallback if headscale route approval turns out to be blocked. `worker` from the client: LAN 10.42.0.5 direct (registry alias) — `workerRail = "worker"` (`f32289cb`); off-LAN it too rides the subnet route. `nas`: direct, `needsJump` false for the client (I-6). |
| Firewall | wayvnc :5900 door is coordinator-only (`hosts/coordinator/tailscale.nix:92`) — the client opens nothing (A-3 says it runs no wayvnc anyway). **Every coordinator door on `tailscale0` is unreachable from the client, on the LAN AND off it** (VERIFIED interface scoping): atuin `27321` (`hosts/coordinator/atuin.nix:10`), immich/navidrome relays `2283`/`4533` (`hosts/coordinator/services.nix:221`), `2283`/`4533`/`32400` (`nas-client.nix:276`), `28981` (`nas-client.nix:383`), wayvnc `5900` (`tailscale.nix:92`) — the client's packets arrive on the coordinator's LAN interface in both cases (§ rail row). **(2026-09-11 pm defaults, R-16/R-18):** no LAN door is opened. atuin: the `clientHome` `auto_sync` assert is OFF (I-2) — the client's shell is an escape hatch. Remmina `coordinator (VNC)`: not a gate; it dies with the flip anyway (R-13). immich/navidrome/plex from the client: through Chrome against the NAS's own tailnet-private HTTPS names (the NAS is on the client's tailnet), never via the coordinator relays. |

### 4.4 Home layer

| Item | State at HEAD | Change |
|---|---|---|
| `~/.config/niri-local.kdl` | `home/home.nix:170-179` emits an inert comment on every host; included by `niri/config.kdl:42-44` (mandatory include, `optional` unsupported on 25.11 — stale note, niri is 26.04). The historian confirms the slot was kept at `22eebdc0` precisely for a returning laptop. | Add a `hostName == "client"` branch **(2026-09-11 pm, R-12)**. Under stock 26.04 the only legal touch content is global: `input { touch { map-to-output "eDP-1" } }` (`niri validate` accepts global, rejects per-device — VERIFIED). Pick eDP-1 (top panel correct, bottom wrong) or eDP-2 (`e1f3f312` stopgap); recommendation eDP-1 since the top panel is the working surface. Also the place for `output "eDP-2"` defaults if kanshi is insufficient, and for the client's Mod+Return override (§5.2) if niri's include merging allows a duplicate bind — else the bind goes through a hostname-branching script in `~/.local/bin`. **Recovery path recorded (R-17):** the per-device blocks + `niri-pr1856` overlay from `22eebdc0^` (§4.2 touch row) — not restored today. |
| kanshi | `home/dot_config/kanshi/config` `profile Duo` intact since 2024-05-07 (eDP-1 scale 2 @0,0 + eDP-2 scale 2 @0,900, adaptive_sync, gammarelay 3850/3350 K); scroll-era `scrollmsg` comments dead. | Keep `Duo`; add `DuoDocked` (eDP-1 alone at scale 2 — because the daemon switches eDP-2 off when the keyboard is docked, kanshi will see one eDP); **(2026-09-11 pm, Q-14 default) add `DuoDock` = eDP-1 + eDP-2 + the PA27JCV on the dock's DP output (match on the panel's description string, since the connector name on the Duo is unknown until step 7), and `DuoDockDocked` (eDP-1 + PA27JCV) for the keyboard-snapped-on case** — four profiles, because the daemon's eDP-2 toggle and the dock plug are independent. The `Desktop`/`Triple` profiles go (§8); `Desk` (DP-1 alone) lives on the coordinator only until the flip. Delete the scrollmsg comment block (delete-don't-comment). |
| `brightness` | `home/dot_local/bin/brightness` dual-eDP aware, `focused` mode resolves `card1-eDP-2-backlight`/`intel_backlight`, skips `asus_screenpad`. | Carry with ONE fix: `brightnessctl -d <dev> set 5%-` (lines 19-20, 51, 62) has no `-n`, so the fifth press from 25% lands on 0, and on i915 brightness 0 is backlight power OFF, not "very dim" (reported from upstream `intel_backlight.c`, INFERRED). The coordinator has no backlight (§2.1) so it never fired; on the Duo F1 at 5% blanks the top panel and, via the daemon sync, the bottom one 500 ms later. Add `-n` (min 1, VERIFIED `brightnessctl --help`) to the up/down invocations and reserve zero for an explicit `brightness off|restore` verb (the F10 toggle, §5.2). Daemon sync caveat (Q-6) unchanged. |
| `remote.fish` | `desk = exec herdr --remote coordinator` on non-coordinator hosts (`home/dot_config/fish/conf.d/remote.fish`, VERIFIED). | The one surviving thin-client script; everything from July (`new-terminal`, `desk-resume`, annex, zmx) was deleted in `061b5be7`. |
| `home/remote.nix` | `lib.mkIf osConfig.programs.niri.enable` → renders wayvnc server + Remmina on ANY niri host. | **(2026-09-11 pm, R-13)** Step 3: key the module on `myDisplay.enable`; the wayvnc unit additionally on `hostName == "coordinator"` (A-3). Registry row gives the client `coordinator (VNC)` and the coordinator `client (VNC)` — the latter is dead weight; `others` filter needs a "hosts that serve" predicate, which after the flip is the EMPTY set. Flip commit (step 10): DELETE the wayvnc unit and the profile generator outright (delete-don't-comment; R-9 + R-13 = no VNC anywhere), leaving Remmina installed only if Tom wants it for non-fleet targets — default: remove the package too. |
| `home/voxtype.nix`, `home/herdr.nix:85`, tally/seat/util/paper modules, NAS `xdg.userDirs`/Nautilus bookmarks (`home.nix:346,364`) | coordinator-gated (VERIFIED). | Unchanged: they stay on the coordinator. voxtype additionally becomes inert at the flip (§4 framing table). |
| `home/herdr.nix:62-64,77` herdr-kitten | delivered to every interactive host (VERIFIED); `flake.nix:1930` asserts it on the worker. | **(2026-09-11 pm, R-16)** Gate the `hk` package and the kitty `action_alias hk` on `hostName != "client"`. The client keeps the `herdr` binary (needed for `--remote`). Consequence: D-11's missing `hk-assets` no longer affects the client at all. |
| `home/home.nix:260` `xdg.desktopEntries` PWAs; `modules/printing.nix` | fleet-wide (VERIFIED). | **(2026-09-11 pm, R-16)** off the client (§4 framing table). |
| `dcal-daemon` | `home/home.nix:386-395` declares `systemd.user.services.dcal-daemon` with NO `mkIf`, `Install.WantedBy = [ "default.target" ]` (VERIFIED) — it WILL start on the client. | Gate on `hostName == "coordinator"` (step 3 home-layer list). |
| `home/piri.nix`, cliphist watchers, kanshi, wl-gammarelay-rs, swaybg, gsettings/GTK theme, fonts, Chrome + PWAs, kitty | fleet-wide. | Carry. The 48 px cursor is NOT in `home/home.nix` (which only sets the Bibata theme, `:339-342`): it is `xcursor-size 48` in `home/dot_config/niri/misc.kdl:86` plus the gsettings spawn in `niri/startup.kdl:29` (VERIFIED), both fleet-wide RAW symlinks tuned for 5K@2x. Duo is 2880x1800@2x — likely fine; if a per-host size is ever wanted it goes in the `niri-local.kdl` slot, not in niri/. |

### 4.5 Install path under R-14 (2026-09-11 pm): in place, or reflash with the key carried

R-14 ("keep things as they are") and R-1 ("blank canvas") pull in opposite directions on the
DISK, not on the config: the closure is a blank canvas either way, because every file the
client runs comes from the dotfiles closure. What differs is whether the disk is wiped.

| | **Path A — switch in place (RECOMMENDED)** | **Path B — reflash, key carried** |
|---|---|---|
| Command | From the coordinator, Tom's shell: `nixos-rebuild switch --flake ~/mecattaf/dotfiles#client --target-host root@<lan-ip>` (the laptop authorizes ONLY the admin key `tom@mesh-20260729` for root — `omarchy-fleet/modules/fleet-registry.nix:17-18` hub-and-spoke, VERIFIED — which is the coordinator's `~/.ssh/id_ed25519`, registry `userKey`). Build first on the coordinator or NAS (step 3 gate), so the switch is a closure copy. | `nixos-anywhere --flake .#client --extra-files <bundle>` after `scp root@<lan-ip>:/etc/ssh/ssh_host_ed25519_key{,.pub} <bundle>/etc/ssh/` (mode 0600, root-only staging, never git) and `scp …/var/lib/tailscale-fleet/tailscaled.state <bundle>/var/lib/tailscale/tailscaled.state`; via kexec (radio modules unloaded, `flash.md`) or cold-boot USB; NEVER `--generate-hardware-config`. |
| Host key | untouched in `/etc/ssh/` (a switch never rewrites host keys). | restored from the bundle before first boot; `ssh-keygen -y` must equal the registry. |
| headscale node 4 | state file carried by hand (I-8); node identity preserved (INFERRED portability). | state file carried in the bundle; same. |
| Disk / filesystems | identical disko layout (I-4, VERIFIED) → mounts as-is; `/home/marwan`, `/etc/fleet`, `/var/lib/tailscale-fleet`, consent-client state are RESIDUE removed by hand (O-6). `/home/tom` is created fresh by the switch. | wiped; nothing to clean. |
| Boot loader | systemd-boot on both sides: dotfiles generation added to the same ESP; omarchy generation stays selectable as rollback until GC. NVRAM phantoms unchanged. | fresh ESP; BootOrder phantom entries (flash.md) may need reordering. |
| Boots spent | ONE reboot (the switch). Every boot may cost the ~5 min VMD stall (D-3), so fewer boots is a real argument. | kexec + first boot + (if kexec fails) USB cold boot: two to three stalls. |
| Initrd risk | the new initrd carries `vmd`, `nvme`, early i915/MEI from `hosts/client/hardware.nix` (§4.2). If the switch's `boot.initrd.availableKernelModules` were wrong the laptop would not find root — same risk as B, and B has no rollback entry. | same, minus the rollback entry. |
| Blank-canvas reading of R-1 | satisfied at the closure level; a few residue directories remain until O-6 removes them. | satisfied literally. |
| **Gate** | `hostname` prints `client`; `ssh client` from the coordinator connects with NO TOFU prompt (key unchanged, registry pinned); `ls /run/agenix` shows `env ssh-user-key atuin-key tom-password-hash wifi-lan`; greetd → niri as tom on eDP-1; `nmcli -t -f NAME,DEVICE connection show --active` includes `thomas-6ghz`; `tailscale status` shows `100.64.0.4` (node 4 carried) or, if re-enrolled, the new node and node 4 expired; `systemctl --failed` empty; `id marwan` → no such user (or removed by hand); `nixos-rebuild list-generations` shows the omarchy entry as the previous generation. | as A, plus: `ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key` equals the registry row BEFORE anything else is trusted; installer lease matched on MAC `a0:b3:39:06:75:a7`; `efibootmgr` shows the new "Linux Boot Manager" first. |

**Recommendation: A.** R-14 says keep things as they are; A keeps the key, the node, the ESP
and the rollback generation with zero extraction steps, and spends one VMD-stall-priced boot
instead of two or three. B is the fallback if A does not come back on the LAN after one full
stall window (~6 min) and one power-cycle — because B is also the ONLY path that works when
the laptop cannot boot its current system at all. The reflash recipe (§4.2 "Flash facts")
stays in the doc for that case.

---

## 5. The thin-client split

### 5.1 Disposition, condensed

| Runs on `client` (Z) — **audited against R-16 (2026-09-11 pm)** | Stays on coordinator (C) | Remote seam (S) |
|---|---|---|
| niri + all pure window/workspace/focus chords; kanshi `Duo`/`DuoDocked`/`DuoDock`/`DuoDockDocked`; wl-gammarelay-rs; swaybg; piri (scratchpad mechanism only — ~~SoundCloud PWA~~ moved to C per R-16, one-line opt back in); Chrome (plain; PWA `xdg.desktopEntries` are C-side churn) + Ctrl+N/Mod+N/Mod+Shift+{C,W,Period}; screenshots (Mod+S variants); colorpicker; brightness F1/F2/Shift+F1/F2 + F10 backlight toggle; volume F6-F8 and audio-route Shift+F9 and call-record Shift+F10 (after the dock move); cliphist + local Mod+V picker (once rebuilt on fzf); kitty; `herdr` binary (client half only); `fzf-nmcli`; GTK theme/fonts; xdg portals; the Duo daemon + asusd + the hardware layer. **Moved OFF the client by R-16:** ~~Nautilus~~ (no local files worth a file manager; default off, one line back), ~~wf-recorder `record`~~ (default off), ~~printing queue~~ (`modules/printing.nix` not imported), ~~PWAs/launcher entries~~, ~~hk~~, OBS (was already "default drop"). | herdr server AND `hk`; tally-*, seat-feeder, util-sampler, nightly-record, claude-transcript-mirror, paper timers; Claude seats cc/cc2/cc3 + credentials; skills tree; models; atuin server; caddy artifacts, microvm host, halogen client (`utility-model`), immich/navidrome relays; NAS NFS automount + Nautilus sidebar; printing; PWA/launcher entries (headless Chrome tooling only after the flip); OBS; cliamp (navidrome creds coordinator-only); ~~wayvnc server~~ (dies at the flip, R-13); Chrome ALSO stays (A-1 CONFIRMED); ~~voxtype~~ (mic-less after step 7, display-less after step 11 → Q-1 default (c): dropped) | Mod+Return (`herdr --remote coordinator`, bare — no hk on the client); herdr's own server-side keybindings (`--remote-keybindings server`) replace the kitty ctrl+b / ctrl+g / ctrl+shift+o gestures; clipboard across the seam; media keys F3-F5 when the player is cliamp on the coordinator; `open-webui` PWA (assumes local :8080; stale — delete); `worker-status` (LAN ssh, fine) |

### 5.2 binds.kdl carry-over, per chord

Everything not listed carries unchanged (all niri-native chords: Mod+H/J/K/L, Mod+Shift+J/K
monitor-up/down — written for exactly the stacked Duo layout — Mod+1..0, Mod+F/G, Mod+W,
Mod+Tab, Mod+Equal, overview, wheel scrolls, Mod+Shift+P power-off-monitors, Mod+Escape).

| Chord | Today | On the Zenbook | Why |
|---|---|---|---|
| Mod+Return | local workspace hop + `exec kitty -e hk new` (`binds.kdl:27`) | keep the hop; **(2026-09-11 pm, R-16)** `exec kitty -e herdr --remote coordinator --remote-keybindings server` — the bare herdr invocation that `hk ssh` expands to (herdr-kitten `hk/remote.py:17-35`, VERIFIED), because `hk` is not delivered to the client (§4.4). ~~`exec kitty -e hk ssh --in-place coordinator`~~ stays correct on any host that HAS hk; the `hk_role=herdr_ui` stamp and the `--in-place` subtlety (kitty exports `KITTY_LISTEN_ON`, `kittyc.available()` turns true, second OS window, flash-and-close) are hk-internal and vanish with it. `desk` (= `herdr --remote coordinator`, `remote.fish`) stays as the fish-level equivalent. PATH precondition: `herdr` resolves at `/etc/profiles/per-user/tom/bin/herdr` on the coordinator (VERIFIED locally), so non-interactive ssh finds it. Per-host bind: `binds.kdl` is a fleet-wide RAW symlink, so the client's spelling goes either in the `niri-local.kdl` slot (if niri merges a duplicate bind from an include — verify with `niri validate`) or through a `~/.local/bin/term-new` script that branches on `hostname` (safe default). | `hk new` on the client does not exist; `herdr --remote` is the supported tier: "clipboard works correctly in that path" (herdr#2399). |
| Mod+Shift+Return | `kitty -e fish` | unchanged (local escape hatch) | |
| Mod+Ctrl+Shift+Return (`hk resume`), Mod+Shift+N (`hk ws …`) | local hk | under `--remote` use herdr's own workspace/session pickers (remote.fish ruling B18); ~~or `hk --host coordinator`~~ (no hk on the client, R-16) — on the client these two chords become no-ops or open a second projector window; default: unbind them in the client's slot | |
| Mod+D | `vicinae open` — DEAD (binary absent today; bind since `03a49294` 2026-03-13) | **Q-7 default (2026-09-11 pm): fzf-in-kitty app launcher; `vicinae` is not added.** | |
| Mod+V | `cliphist \| rofi -dmenu \| cliphist decode \| wl-copy` — DEAD (rofi) | rebuild `~/.local/bin/clipboard` on fzf-in-floating-kitty (same window-rule pattern as `sleep-monitors-prompt`); delete the rofi reference | cliphist is local; cross-host is §6.1. |
| Mod+Shift+V, Mod+Apostrophe, F9 `pomodoro menu`, powermenu/battery/wifi-menu | DEAD (rofimoji/wshowkeys/rofi) | **Q-7 default: rebuild on fzf where a verb is still wanted (F9), delete the rofi/rofimoji/wshowkeys references and scripts otherwise (delete-don't-comment).** | |
| Mod+C colorpicker | `niri msg pick-color` → wl-copy → notify-send (silent fail) | carry; drop the notify or add libnotify + a daemon | |
| Mod+Space / Mod+Shift+Space | voxtype evdev push-to-talk (coordinator-gated, Strix/migraphx package) | seam — see §7.3 | **Q-1 default (2026-09-11 pm): (c) no dictation at first switch; the chords are unbound on the client.** |
| F1/F2, Shift+F1/F2 | brightness over DRM backlights; `focused` mode | carry (with the `-n` fix, §4.4); functional from the GLOVE80 (plain F-keys). From the Duo's OWN keyboard see the XF86 row below. | daemon sync caveat (Q-6). |
| **XF86 twins (new row)** — the Duo's own keyboard | nothing: `grep XF86 binds.kdl` → no hits (VERIFIED; `binds.kdl:95-112` binds plain F1..F10 only) | The daemon reads the keyboard's vendor HID reports and re-emits configured keys through a uinput virtual device: `KEY_BRIGHTNESSDOWN`/`KEY_BRIGHTNESSUP`, `KEY_MICMUTE`, `KEY_LEFTCTRL+KEY_DOT` (emoji), under `fn_lock = true` (`omarchy-fleet/modules/zenbook-duo-daemon.nix:17,26-35` VERIFIED). Those reach niri as `XF86MonBrightnessDown/Up`, `XF86AudioMicMute` and Ctrl+Period — none bound, so brightness and mic-mute from the laptop keyboard are DEAD while the same F-keys on the Glove80 work. Add next to each F-key row: `XF86MonBrightnessDown/Up` → `brightness down/up`; `XF86AudioMute/LowerVolume/RaiseVolume` → `volume`; `XF86AudioPlay/Prev/Next` → `media`; `XF86AudioMicMute` → a new mic-mute verb (`wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle`; none exists today). Whether `fn_lock = true` delivers the F-row as plain F1..F12 (making the plain binds fire) is NOT established from the daemon source — record it in O-1 and bind BOTH spellings. The daemon's emoji chord (Ctrl+.) has no target: Mod+Shift+V is rofimoji (dead) and Ctrl+Period is unbound — decide with Q-7. | R-11 "all niceties carry" is false without this row. |
| F3/F4/F5 | `media` → playerctl, prefers `-p cliamp` | local Chrome/SoundCloud MPRIS works; cliamp on the coordinator needs `ssh coordinator playerctl …` or cliamp inside a remote herdr pane with audio on… the coordinator (no) | Recommendation: on the laptop, `media` drops the cliamp preference; music = SoundCloud PWA (local, audio on the dock). |
| F6/F7/F8 | `volume` → `wpctl @DEFAULT_AUDIO_SINK@` | carry; the sink (GS3/INZONE) is on the dock | |
| Shift+F9 audio-route | fzf: GS3 + webcam mic vs INZONE + INZONE mic; hard-coded USB-serial node names | carry verbatim — node names include USB serials, identical on any host | |
| Shift+F10 call-record | pw-record on INZONE monitor + INZONE mic | carry verbatim | |
| **F10** | `sleep-monitors` → `niri msg action power-off-monitors` (DPMS all) in an fzf popup | **Recommendation: R-11's literal ask — a popup-free BACKLIGHT TOGGLE.** `if [ "$(brightnessctl -d intel_backlight get)" -gt 0 ]; then brightnessctl -s -d intel_backlight set 0; else brightnessctl -r -d intel_backlight; fi` (`-s` save / `-r` restore exist, VERIFIED `brightnessctl --help`). With the daemon sync on, eDP-2 follows within 500 ms; if Q-6 disables sync, do both devices. Keep `power-off-monitors` on Mod+Shift+P (`binds.kdl:324`) as the DPMS "everything dark". | The earlier draft's two premises against brightness-0 were WRONG and its own recommendation was a LOCKOUT. (a) `asus_screenpad` is irrelevant: `bin/brightness` only touches `*/drm/*` backlights (VERIFIED lines 26-34) and eDP-2's real backlight is the i915 per-connector `card1-eDP-2-backlight` (daemon config, VERIFIED). (b) The daemon does not fight a zero: it copies `intel_backlight` → `card1-eDP-2-backlight` every 500 ms with no comparison (reported from upstream `secondary_display.rs`, INFERRED) — it amplifies. (c) On i915, brightness 0 is a real backlight-off, not a dim (reported from upstream `intel_backlight.c` `enable = power==ON && brightness != 0`, INFERRED). So one write darkens both panels, needs no popup, cannot lock Tom out (keys still work, F2/F10 restore), leaves the layout untouched and kanshi never sees it. The only honest argument left against it is "the compositor keeps rendering" — a power argument irrelevant to a docked thin client. **Why `niri msg output … off` is withdrawn:** with no dock display, turning both eDPs off leaves niri with no outputs (`MonitorSet::NoOutputs`, reported from upstream `src/layout/mod.rs`, INFERRED); the "recovery via the same popup" needs a visible kitty+fzf window, which cannot render — the `sleep-monitors-prompt` window rule (`window-rules.kdl:21-30`) needs an output to float on. Binds still fire, so only a popup-free script could recover. Further, the change is "temporary … forgotten" on any config reload (VERIFIED `niri msg output --help`), and ANY head-set change (keyboard snap → daemon forces eDP-2 status → kanshi re-applies `DuoDocked`, or a dock display plug) re-runs a kanshi profile and re-enables the panels; and no kanshi profile with a dock display exists at all (`Duo` = 2 eDPs, `DuoDocked` = 1 eDP — VERIFIED `kanshi/config`), so the "windows migrate to the dock display" rationale had no profile behind it. If output-off is ever kept for the dock-display case, it must be state-driven and popup-free on the ON path (`niri msg -j outputs`; if any eDP is off → `on` both unconditionally, no window), and a `DuoDock` kanshi profile (eDP-1 + eDP-2 + dock display) must exist first. A-2. |
| Mod+E Nautilus | local + NAS sidebar (coordinator-gated) | local only; NAS via gvfs sftp to coordinator if wanted (not recommended for a thin client) | |
| Mod+Shift+Semicolon OBS | obs-studio | drop on the laptop or keep local-capture | Tom's call; default drop. |
| Mod+S/Mod+Shift+S/Mod+Alt+S | niri screenshots → `~/Pictures/Screenshots` | carry (local files). To hand a screenshot to a coordinator-side agent: herdr `--remote` image-paste bridge (§6.1) or `kitten transfer`. | |
| Chrome/PWAs | fleet-wide `xdg.desktopEntries` | carry; `open-webui` entry (localhost:8080) is stale on both hosts — delete | A-1. Agent-opened Chrome windows are a SEAM, not a local app — §6.3. |

---

## 6. The two crucial seams

### 6.1 CLIPBOARD (R-6)

Design principle (VERIFIED mechanism, INFERRED assembly): **coordinator → laptop is OSC 52 and
only OSC 52; laptop → coordinator is paste (bytes down the pty); OSC 52 READS are dead in herdr
(herdr-kitten mapping P27) so no coordinator-side program may ever read the laptop clipboard —
that is the safe default, keep it.**

Laptop side (`home/dot_config/kitty/kitty.conf`):

- No `clipboard_control` line → kitty default `write-clipboard write-primary read-clipboard-ask
  read-primary-ask` (VERIFIED kitty 0.48.0 docs). Any program on the far end of ssh/herdr may
  WRITE the laptop clipboard; reads prompt. Do NOT add `read-clipboard`. Leave as is; optionally
  write the default out explicitly with a comment so nobody "fixes" it.
- `copy_on_select clipboard` stays (kitty-native selection copies immediately). Under
  `herdr --remote` mouse goes to herdr, which selects and emits OSC 52 (mapping P26);
  Shift+drag bypasses to kitty.
- cliphist: `niri/startup.kdl:7-9` `wl-paste --type text --watch cliphist store` (+ image twin).
  An OSC 52 write makes kitty the Wayland selection owner exactly like a local copy, so it lands
  in cliphist and Mod+V (INFERRED from mechanism; verify with the one-liner below) — **but only
  if kitty's window is keyboard-focused at the moment the OSC 52 arrives.** niri (smithay)
  refuses a selection set from a non-focused client: the niri 26.04 binary carries the string
  "denying setting selection by a non-focused client" (VERIFIED `grep -a` on
  `/nix/store/…-niri-26.04/bin/niri`). This is compositor policy, not fixable in `kitty.conf`;
  do not "fix" it by adding `read-clipboard`.
- Retire `~/.local/bin/clip2path` for the thin client (unbound today; pastes a LAPTOP path into a
  coordinator-side agent). Image → agent goes through herdr `--remote`'s built-in remote image
  paste (copies the image to a remote temp file and pastes that path; mapping P28
  `keys.remote_image_paste`). `kitten transfer` is the plain-tier alternative.

Coordinator side (the trap): the herdr server (`home/herdr.nix:85`, linger) inherited niri's
environment (`WAYLAND_DISPLAY=wayland-1`, `DISPLAY=:0`, no `SSH_*` — VERIFIED from
`/proc/<herdr server>/environ`). Inside a herdr pane:

| Writer | Today | Fix |
|---|---|---|
| Claude Code 2.1.266 | native `wl-copy` (coordinator clipboard) AND OSC 52 always (VERIFIED in the binary) | none needed: the OSC 52 copy reaches the laptop through herdr. After the flip (step 11, R-13) the `wl-copy` half fails silently — by design. |
| nvim 0.12.4 | `opt.clipboard = 'unnamedplus'` (`home/dot_config/nvim/lua/options.lua:9`) picks `wl-copy` when `WAYLAND_DISPLAY` is set; OSC 52 auto-path disabled by unnamedplus | `vim.g.clipboard = 'osc52'` gated on `HERDR_ENV` or `SSH_TTY` in options.lua. One conditional, <10 lines. |
| fish 4.8.1 `fish_clipboard_copy` (function embedded in the binary; the 4.7.1 source file in the store has the same shape) | runs `wl-copy` IF `WAYLAND_DISPLAY` is set and `wl-copy` exists (lines 17-19), AND THEN ALWAYS emits `\e]52;c;…\a` when `TERM != dumb` and stdout is a tty (lines 28-36; VERIFIED in `…-fish-4.7.1/share/fish/functions/fish_clipboard_copy.fish`; 4.8.1 embedded, same logic INFERRED). So in a herdr pane today it double-copies (coordinator + laptop) exactly like Claude Code; after the headless flip it silently skips `wl-copy`. | no fix; verified both paths. |
| any script calling `wl-copy` on the coordinator (`bin/clipboard`, `colorpicker`) | copies to the coordinator | do not run desktop scripts inside remote panes; they are laptop scripts now. |
| `kitten clipboard` (OSC 5522) | works over plain `kitten ssh`; through herdr UNVERIFIED | test; if herdr drops 5522, plain-tier only. |

Answer to "where does a ssh'd Claude Code session copy to": inside a herdr pane → the coordinator
clipboard (wl-copy) AND the laptop (OSC 52, only if the projector window is focused); under plain
`kitten ssh` (`SSH_TTY` set, no `WAYLAND_DISPLAY`) → the laptop only. nvim is the ONLY writer that
needs a code change (`vim.g.clipboard = 'osc52'` gate; `clipboard.vim:185-200` shows the
`g:clipboard == 'osc52'` opt-in path, VERIFIED, and the auto-branch is disabled by `unnamedplus`).

Failure modes: (1) outer terminal ignores OSC 52 → silent copy loss (herdr#2399) — kitty accepts
by default, so only a misconfigured `clipboard_control` causes it; (2) `wl-copy` callers after
the coordinator goes headless → "Failed to connect to a Wayland server" — only scripts, not
Claude/nvim once fixed; (3) size: `clipboard_max_size 512` MB default, irrelevant; (4) no
inbound read: a coordinator-side `wl-paste`/Claude image paste reads the COORDINATOR clipboard —
use the herdr image bridge; **(5) SILENT: focus-gated writes.** An OSC 52 that reaches the laptop
kitty while Tom is in Chrome (a Claude Code pane that copies after finishing, a script, an
hk-driven pane, a second herdr window) is dropped by niri ("denying setting selection by a
non-focused client", VERIFIED above); kitty reports nothing, cliphist never sees it. For
unattended hand-offs from agents use a file path (herdr `pane read`, `kitten transfer` on the
plain tier), not the clipboard.

Verification (inside a remote pane): (a) `printf '\e]52;c;%s\a' "$(printf hi | base64)"` then
`cliphist list | head -1` on the laptop must show `hi`; (b) `sleep 4; printf '\e]52;c;%s\a'
"$(printf lost | base64)"` and switch focus to Chrome during the sleep — expect the copy to be
LOST; document it as the accepted defect. (a) alone passes by hand and hides class (5).

What the plan does NOT need: a `wl-paste --watch … | ssh coordinator wl-copy` daemon (would
make the coordinator's clipboard mirror the laptop's — useless once headless, and a read path).

### 6.2 KITTY SSH into coordinator sessions (R-6)

**(2026-09-11 pm, R-16)** The client does not carry `hk` (§4.4), so every `hk …` spelling in
this subsection describes the coordinator side or a host that has hk; on the client the only
verbs are `herdr --remote coordinator` (tier 1) and `kitten ssh coordinator` (tier 2). The
tiers and their facts stand as written.

Facts (VERIFIED): `hk` needs `KITTY_LISTEN_ON` + a local `kitty` binary (`hk/kittyc.py:29-44`);
dotfiles `listen_on unix:@kitty-{kitty_pid}` is an ABSTRACT socket and kitten ssh's
`forward_remote_control` "does not work with abstract UNIX sockets"; `hk --host coordinator`
routes herdr calls over `ssh coordinator 'herdr …'` but window launches run a LOCAL
`herdr terminal attach` (`verbs.py:618-620`), which needs a local herdr socket (`HERDR_SOCKET_PATH`
is forwarded if set). herdr's remote path: `herdr --remote coordinator` needs herdr + a running
server on the far side (both true), manages its own ssh control sockets unless
`[remote].manage_ssh_config = false`, reconnects with backoff. `hk ssh coordinator` = one kitty OS
window running `herdr --remote coordinator --remote-keybindings server`, stamped
`hk_role=herdr_ui` (`hk/remote.py`, mapping P58); `hk ssh --plain` = `kitten ssh` (P59).

Design (three tiers, from most to least supported):

1. **Session projector (default, Mod+Return):** `kitty -e herdr --remote coordinator
   --remote-keybindings server` on the client **(2026-09-11 pm, R-16; = what `hk ssh --in-place
   coordinator` runs on a host with hk)** (§5.2; `desk` is the fish equivalent). Everything
   herdr — workspaces, panes, resume, fork inside herdr, OSC 52 out (focus-gated, §6.1), image
   paste in — works. Without hk's kitty mappings, ctrl+b / ctrl+shift+o / ctrl+g go straight
   down the pty to herdr, which under `--remote-keybindings server` interprets them itself
   (INFERRED from the flag's name and hk's forwarding design — hk's P60/P22 mappings exist to
   forward exactly these bytes; verify at step 9). ~~ctrl+b prefix forwards (P60 …); ctrl+g fork
   … DEFERRED (herdr-kitten #9, P62). Two things TO build beyond the bind change: (i)
   herdr-kitten's kitty gesture assets `~/.config/kitty/hk-assets/` are NOT delivered by nix …
   so a freshly flashed laptop ships with ctrl+b/ctrl+g/ctrl+shift+o broken until #26 lands~~ —
   that debt now belongs to hosts that run hk (the coordinator) and is D-11, not a client
   item. Still binding: (ii) the herdr version-coupling rule (I-5). Reconnect story: `herdr --remote` retries with
   bounded backoff after sleep/network loss and keeps the last workspace visible but dimmed;
   multiple Mod+Return windows are independent views of the same server (herdr.dev
   connecting-machines, reported by the critique — INFERRED); herdr's generated ssh config
   includes `~/.ssh/config` first, adds `ServerAliveInterval/CountMax` as fallbacks and a private
   per-attach control socket (VERIFIED `herdr --default-config` `[remote]` block), so the
   registry-driven Host block is honoured.
2. **Plain shell:** `kitten ssh coordinator` (Mod+Shift+Return variant; `hk ssh --plain` only on hosts that carry hk).
   Brings terminfo, shell integration, `clone-in-kitty`, `kitten transfer`, `kitten clipboard`,
   and `share_connections yes` (a per-kitty-instance ControlMaster, cleaned on kitty quit). NO
   resume: a plain-tier window simply dies when the laptop sleeps; the herdr tier resumes by
   itself. Needs a
   `~/.config/kitty/ssh.conf` (none exists today) with `hostname coordinator` → `login_shell fish`
   because the fleet login shell is bash (kitty.conf comment, #236); otherwise you land in bash.
3. **Per-pane kitty windows from the laptop (`hk new/open/materialise` against the coordinator):**
   requires (a) a forwarded herdr socket: `ssh -L /run/user/1000/herdr-coord.sock:/home/tom/.config/herdr/herdr.sock coordinator`
   plus `HERDR_SOCKET_PATH`, and (b) proof that `herdr terminal attach` works over a forwarded
   unix socket — UNVERIFIED. **Q-10 default (2026-09-11 pm): tier 1 only; tier 3 would also
   need hk on the client, which R-16 forbids.** File it as a herdr-kitten issue if ever wanted.

OpenSSH side (`home/ssh.nix`): today no `ControlMaster`/`ControlPersist`/`ServerAlive*`
anywhere (VERIFIED grep). Two choices for plain `ssh`/`hk --host` from the laptop: (A) add to the
`coordinator` block (ssh_config directive names pass through `programs.ssh.settings` unchanged —
INFERRED, confirm against the pinned home-manager) `ControlMaster auto`, `ControlPath
~/.ssh/cm-%C`, `ControlPersist 10m`, `ServerAliveInterval 15`, **`ServerAliveCountMax 2`** — the
last line matters: after suspend the persisted master's TCP is dead and every `ssh
coordinator`/`hk --host` call blocks on it until interval × count kills it (15 × default 3 = 45 s;
with 2 → 30 s worst case); document `ssh -O exit coordinator` as the unstick. (B) drop
ControlMaster entirely and accept ~200 ms per plain `ssh` call, since herdr and kitten bring
their own multiplexing. **Default (B) (2026-09-11 pm)** — fewer moving parts on a thin client,
and with no hk on the client there is no `hk --host` call storm to amortise. Nothing to scope:
the registry-driven block is unchanged on every host.

Socket/remote-control implications: `allow_remote_control yes` + abstract `listen_on` stays
(it is what local `hk` gestures use); do NOT enable `forward_remote_control` (grants the remote
"full access to the local computer" and would not work with the abstract socket anyway). If tier
3 is ever wanted, the socket must move to a path (`unix:/run/user/1000/kitty-{kitty_pid}`) — a
separate ruling.

Control plane **(2026-09-11 pm, R-15)**: on the dock at home, `coordinator` = 10.42.0.2 via
`networking.hosts` and the registry alias, no tailnet involved; off-LAN the same address rides
the NAS's headscale subnet route (§4.3). ~~none of this works off-LAN unless the laptop shares a
tailnet with the coordinator~~ — it shares one with the NAS, which routes.

### 6.3 Agent → Tom's eyes (the seam the earlier draft missed)

Tom's skills open a bounded Chrome app window ON THE HOST WHERE THE AGENT RUNS:
`~/.claude/skills/md-artifact/SKILL.md:13,21,31` ("bounded Chrome app window (`--app` …)",
`artifact-view … → google-chrome --app`), and presentation-beta / publish-artifact reference the
same rung (VERIFIED). Agents keep running on the coordinator (§5.1 C-tier, §0 invariant 1), so
every "show me this doc" opens on DP-1 today and fails outright after step 11 (headless, no
`WAYLAND_DISPLAY`; R-13 makes this imminent, not eventual). Chrome on the client (A-1) does not help by itself: nothing forwards the
open. Options (Q-16): (a) `artifact-view` on the coordinator detects "no display" and runs `ssh
zenbook env WAYLAND_DISPLAY=wayland-1 google-chrome --app=file://…` — needs the snapshot dir
reachable from the laptop (NFS/`kitten transfer`/rsync) since `file://` is local; (b) make the
publish rung (tailnet/LAN URL under art.mecattaf.dev, TTL'd) the DEFAULT view path when the
agent host has no display, and the laptop opens the URL; (c) `xdg-open` forwarding over the
herdr pane (herdr has no such feature — INFERRED). **Q-16 default (2026-09-11 pm): (b) — the
publish rung becomes the default view path when the agent host has no display** (one predicate
in `artifact-view`, no new transport; the skill files live outside dotfiles, so this is a skills
change filed with the flip, step 10), (a) as a follow-up issue.

---

## 7. Peripheral migration to the Thunderbolt dock (R-7)

### 7.1 The dock itself

VERIFIED ABSENT: no source in dotfiles, omarchy-fleet or omarchy-nix names the dock model or
records any Type-C/TB4/USB4 test on the Duo. Every "peripheral through dock on the Zenbook"
behaviour below is UNTESTED. First action (O-1, Tom in person): plug the dock into the Duo while
it still runs Omarchy, run `lsusb`, `boltctl list`, `boltctl domains` (security level: `+iommu`
means zero-touch enrolment; otherwise one `boltctl enroll --policy auto <uuid>`), `wpctl status`.
Q-3.

### 7.2 Per device

| Device | Moves? | Config that follows | Notes |
|---|---|---|---|
| iContact Camera Pro `1bcf:2d3e` (webcam + mic) | YES | `hosts/coordinator/audio.nix` → `hosts/client/audio.nix` verbatim **(2026-09-11 pm, R-12)** (rule keyed on `node.name = alsa_input.usb-DCX-241206-FAY_iContact_Camera_Pro_01.00.00-02.analog-stereo`, `priority.session = 3000`; `alsa-utils`). Runtime repair `amixer -c Pro sset Mic 36% cap` must be re-run once on the laptop (WirePlumber state is per host). | Coordinator loses its only real mic: voxtype and Claude Code `/voice` on the coordinator go silent (§7.3). Coordinator keeps Ryzen HD Audio + Radeon HDMI only; delete `hosts/coordinator/audio.nix`. |
| Sound Blaster GS3 `041e:3298` | YES | Default sink is RUNTIME WirePlumber state — redo with one `wpctl set-default` on the laptop or add a twin `priority.session` rule for the sink in `audio.nix` (declarative; recommended). Volume knob = evdev kbd, handled by niri. | `niri/scripts/audio-route` `SPEAKER_SINK` name carries verbatim. |
| Sony INZONE Buds dongle `054c:0ec2` | YES | nothing declarative; `audio-route` and `bin/call-record` node names carry verbatim. | |
| Apple Magic Trackpad `05ac:0265` | YES (wired USB; no BT pairing exists on the coordinator) | `niri/input.kdl`: which libinput class the Duo assigns decides `mouse { accel-profile "flat" }` vs `touchpad { tap dwt natural-scroll clickfinger }` — verify with `libinput list-devices` on the laptop. | **Q-11 default (2026-09-11 pm): stays wired on the dock.** (BT pairing to the Duo's own AX211 CNVi controller remains possible later; the MediaTek dongle is NOT needed for that, see next row.) |
| MoErgo Glove80 Left `16c0:27db` | YES | `input.kdl` xkb `caps:none`, numlock — carries. | The daemon's Fn-lock/hotkeys apply to the Duo's own keyboard only. |
| MediaTek `0e8d:0717` | **NO — stays on the coordinator (or is retired)** | USB Bluetooth controller = the coordinator's `hci0` (VERIFIED §2.1). Fleet-wide `hardware.bluetooth.enable = true` (`modules/common.nix:255`) is what drives it; nothing else references it. | Moving it strips Bluetooth from the coordinator for no gain: the Zenbook has AX211 CNVi Bluetooth of its own (INFERRED from the platform; confirm `bluetoothctl list` on the laptop at step 7). Q-12 CLOSED; folded into Q-11. The earlier draft's "YES presumably" was wrong. |
| ASUS PA27JCV on DP-1 | STAYS on the coordinator until the flip (step 11), then **moves to the client's dock — Q-14 default (2026-09-11 pm)**; the second, already-unplugged panel is retired | kanshi `DuoDock`/`DuoDockDocked` (§4.4) | R-4, R-13. Whether the Duo drives a 5K@60 external display through this dock is UNTESTED (Q-3 — DP 1.4 / TB4 alt-mode on the Duo's port, and the dock's own DP output, both unknown); if it cannot, the panel is retired with the other and the profiles are deleted. The F10 design no longer depends on it (§5.2). |
| **Dock UNPLUG / TB re-auth failure after resume (new row)** | — | Nothing declarative: WirePlumber falls back to the Duo's internal codec for sink and source (runtime state; per-device defaults are remembered and restored on replug — INFERRED from WirePlumber behaviour), so Chrome/SoundCloud keep working. `audio-route` (`niri/scripts/audio-route:6-9`, VERIFIED hard-coded USB-serial node names), `call-record-menu` and the `volume` verb (`@DEFAULT_AUDIO_SINK@`) operate on names that vanish: the first two must guard on `wpctl status` containing their node names and print a one-line error in the popup rather than `pw-record` nothing. Glove80 + Magic Trackpad vanish (internal keyboard/touchpad take over; `input.kdl` covers both classes). The daemon is unaffected (its USB target `0b05:1b2c` is the Duo keyboard, not the dock; VERIFIED `zenbook-duo-daemon.nix:63`). Bolt re-authorization on replug is zero-touch only with `+iommu` (Q-3). | With the withdrawn output-off F10, there is no lockout case on unplug. |
| bolt | — | `modules/common.nix:256` `services.hardware.bolt.enable = true` is inherited by the client host. PR #369's `41fc8a0b` hunk would remove it fleet-wide, contradicting DECISIONS.md 2026-09-11 lines 57-58 "bolt stay[s] for ordinary USB4 peripherals" (VERIFIED). **Q-2 default (2026-09-11 pm): drop that hunk from #369 before merge.** Dock enrolment (step 7) unchanged. | |

### 7.3 Dictation (the hidden casualty)

voxtype is `hostName == "coordinator"`-gated and built as `onnx-migraphx` for the Strix GPU
(`home/voxtype.nix:14-16`); `hk voice text` has no `--host` (herdr-kitten `hk/voice.py`). After
the mic moves, the coordinator has no capture device and the laptop has no voxtype. Options for
Tom (Q-1): (a) voxtype on the laptop with a CPU/other backend, typing locally via `wtype` — works
into Chrome and into a kitty running `herdr --remote` (text is just keystrokes down the pty);
(b) keep a mic on the coordinator (e.g. leave the INZONE dongle there) and dictation stays
coordinator-side, typed into the focused herdr pane as today; (c) drop dictation for now.
**Q-1 default (2026-09-11 pm): (c) at the first switch** — and since the flip (R-13) removes the
coordinator's display right after, (b) is dead too: voxtype types into a focused Wayland window
that will not exist. (a) is a later issue (step 15), and it grows the client closure, which
R-16 discourages.

---

## 8. Dual-5K retirement and the coordinator headless flip (R-13: next, not eventually)

### 8.1 Delete now (R-4; "delete, don't comment out")

| Artefact | Action |
|---|---|
| `home/dot_config/kanshi/config` `profile Desktop` (DP-4 180° @0,0 + DP-1 @0,1440, gammarelay 4000/4000) and the four commented alternates | Replace with `profile Desk { output DP-1 mode 5120x2880@60 scale 2 position 0,0 … gammarelay 4000 }` so DP-1 stops sitting at logical 0,1440. **(2026-09-11 pm, R-13)** `Desk` lives only until the flip; the flip commit deletes it and the panel's profiles become the client's `DuoDock`/`DuoDockDocked` (§4.4). |
| `profile Triple` (DP-4 + DP-1 + HDMI-A-1) | Delete. |
| `profile Laptop` (eDP-1 scale 1.5, the Dell XPS) | Delete (the XPS lives in omarchy-fleet). |
| `Duo` scroll-era `scrollmsg` comment block | Delete. |
| `home/dot_config/niri/local.kdl` commented `output "DP-4" { scale 2.0 transform "180" }` | Delete the comment; keep the (mandatory) empty include. |
| `home/dot_config/waybar/pomodoro-bar.json` (`"output": "HDMI-A-1"`), whole legacy `waybar/` dir (not in configDirs) | Delete. |
| `home/dot_config/niri/window-rules.kdl` | No output references — nothing to do. `home/remote.nix` `vncOutput = null` already single-output-safe. |

### 8.2 The coordinator keeps until the flip (~~A-4~~ → R-13, steps 10–11)

Between the reboot (step 1) and the flip (step 11) — a window of hours, not weeks — the
coordinator keeps: niri + greetd autologin (`modules/common.nix:210-234`), wayvnc :5900 on
tailscale0 (unreachable from the client anyway, §4.3), Chrome, swaybg, kanshi with the
single-DP-1 `Desk` profile, piri, the herdr server (already linger-started, independent of
niri), voxtype (mic-less after step 7), all C-tier services. **(2026-09-11 pm)** The point of
this window is only to keep a lit console on the coordinator while the client is being proven.

### 8.3 The headless flip — which profile, and what is left afterwards

`modules/headless.nix` (`myHeadless`, VERIFIED) is an APPLIANCE profile: it forces off niri,
greetd, linger, rtkit, PipeWire, bluetooth, bolt, keyring, polkit, dconf, gvfs, udisks2,
power-profiles-daemon, fprintd, fwupd, portals, podman, empties `fonts.packages`, closes ssh on
all interfaces, caps zram. It is WRONG for the coordinator: the coordinator needs linger (herdr
server, tally, timers), podman (halogen client tooling, microvm host), PipeWire (only if a mic
stays), polkit, keyring (gcr-ssh-agent), and its firewall doors.

The right shape is the worker's 2026-09-11 form (`hosts/worker/default.nix:88-89`, header
comment VERIFIED): `programs.niri.enable = lib.mkForce false; services.greetd.enable =
lib.mkForce false;` — "Home Manager itself STAYS: tom's shell, atuin, the user timers and the
herdr/hk client are all real here; only the graphical session is absent. Console recovery is
the VT getty autologin modules/common.nix keeps on every host." For the coordinator that means,
at flip time: those two lines in `hosts/coordinator/default.nix`; `home/remote.nix` drops its
wayvnc unit automatically (mkIf niri); voxtype, piri, kanshi, swaybg, cliphist watchers,
Chrome PWAs and the whole Z-tier become inert or must be gated (`home/home.nix:93,509`
coordinator-only package extras need a "has display" predicate rather than `hostName ==
"coordinator"`); the herdr server must be restarted so its environment loses `WAYLAND_DISPLAY`
(§6.1); Chrome on the coordinator becomes headless-only tooling (`google-chrome-headless` dir
already exists in `~/.config`) and the agent-view seam (§6.3) must already be on its publish
path. **Third edit the earlier draft omitted:** `flake.nix:1942-1943` assert
`nixosConfigurations.coordinator.config.programs.niri.enable` and `…services.greetd.enable`,
and `:1939` asserts `coordinatorHome.systemd.user.services ? wayvnc` (VERIFIED) — the flip trips
all three, so it is NOT "one line later" until those asserts are re-keyed. Recommendation:
introduce a `myDisplay.enable` host option (true on coordinator today and on `client`, false
on worker/nas), key `home/remote.nix`, voxtype, piri, kanshi and the coordinator package extras
on it, and re-key the `flake.nix:1938-1944` asserts on the same option in the FIRST code step
(§10 step 3) — then the flip is one line later. ~~Not for today.~~ **(2026-09-11 pm, R-13): it
IS for today — the option lands in step 3 and the flip is steps 10–11, right after the seat is
proven in step 9.**

**What the coordinator is after the flip (2026-09-11 pm, R-9 + R-13, stated plainly):** no
compositor, no greeter, no wayvnc, no Remmina server profile, no VNC of any kind anywhere in the
fleet. Its ONLY inputs are (1) ssh — from the client over the LAN or, off-LAN, over the NAS
subnet route — and (2) the VT getty autologin `modules/common.nix` keeps on every host, which
is BLIND until a monitor and keyboard are physically re-plugged. Everything Tom runs still
runs there (herdr server, the agent seats, tally, halogen client, microvm host, caddy, atuin
server, printing, models, skills); the client only projects it. Consequences to execute in the
flip commit (step 10): `myDisplay.enable = false` in `hosts/coordinator/default.nix` (→ the
worker's two `mkForce false` lines by derivation); DELETE the wayvnc unit, the Remmina profile
generator and the `5900` door in `hosts/coordinator/tailscale.nix:92` (delete-don't-comment);
DELETE kanshi `Desk`; voxtype inert (Q-1 (c)); `home/home.nix:93,509` extras keep their
coordinator gate (they are CLI tools, not display things); restart `herdr.service` so panes lose
`WAYLAND_DISPLAY` (§6.1); Chrome stays as headless tooling (`google-chrome-headless` dir already
exists in `~/.config`); `artifact-view` default → publish rung (Q-16 (b)); the worker header's
"ONLY the coordinator has a display output" becomes "ONLY the client".

---

## 9. Known accepted defects and deferred items

| # | Item | Status |
|---|---|---|
| D-1 | Touch → output mapping: stock niri 26.04 maps all touch to ONE output; PR #1856 "Per-device touch and tablet config" OPEN, last activity 2026-06-19 (VERIFIED `gh pr view 1856 -R niri-wm/niri`; maintainer wants generalised device matching). Fork `stefanboca/niri 3b75b96` + overlay attr recoverable from `22eebdc0^:overlays/default.nix:33-65`, per-device blocks from `22eebdc0^:home/home.nix:168-185` (§4.2 touch row records both). | ACCEPTED (R-10). Mitigation: global `map-to-output "eDP-1"` in `niri-local.kdl`. **Recovery path recorded, not restored (R-17, 2026-09-11 pm).** |
| D-2 | Which ELAN digitiser is the top panel (`ELAN9008:00 04F3:425B` vs `ELAN9009:00 04F3:425A`): sway 2024 (`1e05c4c6`) and niri 2026 (`22eebdc0^`) pair them OPPOSITELY; never confirmed on metal (dotfiles#67). omarchy-fleet `LEDGER.md:383-404` (A-19, VERIFIED) already measured the strings on 2026-09-08 (`elan9008:00-04f3:425b`, `elan9009:00-04f3:425a`) and records that pairing needs BOTH panels lit, i.e. UNDOCKED — docked, Hyprland reports eDP-2 absent. | Read from the metal in O-1 before the wipe (undock, `hyprctl devices` + touch). |
| D-3 | VMD MTL016 boot stall (intermittent ~5 min boots); patch unvalidated; laptop on 6.18.40. **(2026-09-11 pm)** Presumed cause of the 17:40 Plymouth hang (§2.2 live status). Under R-14/R-16 every boot is expensive and rare, which is the argument for the in-place path (§4.5) and for placing the soak AFTER the flip (step 12). | Carry patch on 7.2.4 pin (Q-4 default); validate with repeated cold boots on battery (§10 step 12). |
| D-4 | IPU6 internal webcam: never configured for the Duo anywhere (platform `ipu6epmtl` INFERRED). | Irrelevant while the iContact moves to the dock. Deferred. |
| D-5 | Rotation/gestures: ntm never auto-started (historian: inert for its whole tenure); fleet rotate module Hyprland-only. | **OUT OF SCOPE TODAY (R-17, 2026-09-11 pm)**; stays deferred; no ntm restore in the sequence; `hardware.sensor.iio.enable` carried cheaply. |
| D-6 | Hibernate untested (no swap); upower PowerOff at 5%. | Accepted. |
| D-7 | Lid-close semantics: NOT a "watch" item — logind `HandleLidSwitchDocked` defaults to `ignore` whenever more than one display is connected, so lid-close suspends only when the keyboard is docked (§4.2 logind row, VERIFIED man page). Decision moved to Q-15. Remaining watch items: suspend/resume eDP-2 reassert timing; rfkill on dock transition; charge limit unset. | Q-15 decides; the rest: watch after flash. |
| D-8 | Hyprland `CBackend::create() failed!` one-shot abort on cold boot (fleet R39) — plausible common cause with GSC timing. | Watch `journalctl --user -u niri -b` on the first boots. |
| D-9 | Escrow (fleet R15/R28), identity-archive decryption rehearsal (`decryptionVerified:false`). | Fleet-side, not blocking the return. |
| D-10 | Plymouth failure on the ASUS (session C 12:13Z). | Uninvestigated; **(2026-09-11 pm)** dotfiles DOES use Plymouth (`modules/common.nix:58`, VERIFIED), so the client shows the same splash during a VMD stall. Watch. |
| D-11 | Thin-client fork gesture (ctrl+g) and per-pane kitty windows under `--remote` (herdr-kitten #9, mapping P62; tier 3 in §6.2); kitty gesture assets not delivered by nix (herdr-kitten #26) and `hk lane start` yielding a plain shell (#27) (VERIFIED `~/.config/kitty/hk-assets` absent on the coordinator). | **(2026-09-11 pm, R-16)** No longer a client item — the client carries no hk; herdr's `--remote-keybindings server` handles the keys. Remains a coordinator-side herdr-kitten debt (step 15 issues). |
| D-12 | The DEAD desktop tier (vicinae, rofi, rofimoji, wshowkeys, libnotify, notification daemon) — dead on the coordinator since July without complaint. | Q-7 default: fzf-in-kitty, delete the references (2026-09-11 pm). |
| D-13 | Kernel patch validity beyond 7.2.4; niri version drift (`config.kdl` comments say 25.11, binary is 26.04, blur rules assume ≥26.04). | Fix the stale comments when touching config.kdl. |
| D-14 | `open-webui` PWA entry (localhost:8080), `bin/worker-status` LAN path, `home/pi.nix` DS4 endpoint row, `/etc/local-models` DS4 symlinks. | Residue cleanups, separate commit. |

---

## 10. Implementation sequence — re-sequenced 2026-09-11 pm (R-13: flip right after the seat is proven)

Each step has a gate. **[Tom]** = in person (device is physically here, charging); **[agent]** =
code-writing agent (repo edits, builds, `nix flake check`); **[Tom+agent]** = agent prepares, Tom
executes the physical/root action. The morning sequence (15 steps, flip last) is superseded in
full; its step numbers are cited below as "(was N)" so cross-references in §5–§9 still resolve.
There is NO "decide Q-n" step any more (R-18): the defaults in §11 apply unless Tom says
otherwise before step 3.

| Step | Action | Gate (verify before the next step) |
|---|---|---|
| 1 [Tom] (was 1) | **Before the reboot:** herdr is linger-started with `resume_agents_on_restore = true` (`home/dot_config/herdr/config.toml:49-58`, VERIFIED; `home/herdr.nix:93-95` `Restart=on-failure`) — it will restore its session store and RELAUNCH every Claude Code / codex / pi conversation inside its panes on its own, with cc at 95% cap and cc3 unauthenticated (session A). So: inventory `herdr` panes; `herdr pane close <id>` every finished agent pane (config.toml doctrine); confirm which conversations should auto-resume; note the five background agents Tom stopped at 15:29Z stay stopped; clear pi's private `PI_CODING_AGENT_DIR` (session B). **Reboot the coordinator** = `sudo nixos-rebuild switch --flake .#coordinator` onto `7e544f5c` (A-5 CONFIRMED; PR #368 may merge first or after). Then the DECISIONS.md operator acts: `nmcli connection delete tb-fleet tb-fleet2 eth-fleet`; `rm -rf /var/lib/{flashnext-rdma,tb-link-heal,usb4-stream}`; stale failure markers; `local-models-prune` to five files. | `ssh worker hostname` resolves 10.42.0.5; `~/.ssh/config` shows `worker` HostName `worker`; `utility-model` reaches `http://worker:8731`; niri, herdr server, wayvnc, tally-daemon back up; DP-1 lit; **no unintended agent resumed** (`herdr` pane list matches the pre-reboot inventory). |
| 2 [Tom] (was 2) | **"OK to power the Zenbook Duo back on now."** It was last seen stuck on the Plymouth logo (§2.2 live status): power on, wait the full VMD-stall window (≥6 min) before judging, power-cycle once if still dark; it should take a DHCP lease from the NAS and answer as `zenbook-duo` on the LAN (`nix run ~/mecattaf/omarchy-fleet#fleet-ssh -- zenbook-duo hostname` from the coordinator, `fleet-ssh` VERIFIED `omarchy-fleet/flake.nix:74-99`). Then O-1 while it still runs Omarchy: **`ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key` must print the fleet key `…AoNjOhvz…` (R-14 gate)**; the first-ever dock test (§7.1, incl. whether the PA27JCV lights through the dock — Q-3/Q-14); the touch-panel pairing (D-2, UNDOCKED); what the Duo keyboard emits under `fn_lock` (§5.2 XF86 row); `lsblk -o NAME,PARTLABEL,FSTYPE,MOUNTPOINT` (expect `disk-main-ESP`/`disk-main-root`); `ls /var/lib/tailscale-fleet`; `bluetoothctl list`. Record results in a scratch note the agent can read. | Host key equals the registry (else STOP: R-14's premise is false); `boltctl domains` security string known; `lsusb` through the dock shows the five moving peripherals (the MediaTek stays); which ELAN is top known; keysyms known; partlabels as expected. If the laptop never answers after two stall windows, path B (§4.5) is the install path and O-1 is skipped. |
| 3 [agent] (was 4, now the FIRST code step) | dotfiles branch `client-seat`: **`myDisplay.enable` option first (R-13)** — true on coordinator (for now) and client, false on worker/nas; `programs.niri.enable`/`services.greetd.enable` derived from it; `home/remote.nix` split; `flake.nix:1938-1944` asserts re-keyed on it. Then §4.1 I-1…I-8: registry row `client` with the REUSED fleet public key (no placeholder, no mint), roll-call `["client" "coordinator" "nas" strixWorker]`, `clientHome` asserts (herdr absent, **hk absent**, wayvnc absent, tally/voxtype off, atuin sync off), deploy node `client`, secrets tiers (`clientOnly`, wifi-lan gate `"client"` in / `"worker"` out), `hosts/client/{default,hardware,disko,audio}.nix` with the worker-style header and the superseded worker header prose, headscale rail (I-8), `networking.hosts`, ssh.nix `client` alias + `needsJump`; §4.2 hardware layer + `modules/zenbook-duo-daemon.nix` + `pkgs/zenbook-duo-daemon.nix` + `pkgs/patches/vmd-mtl016-7.2.4.patch` (Q-4 default: 7.2.4 pin + patch); §4.4 home layer (niri-local.kdl `client` branch, kanshi `Duo`/`DuoDocked`/`DuoDock`/`DuoDockDocked`/`Desk`, **R-16 gates: hk, PWAs, printing, Nautilus, wf-recorder, dcal-daemon off the client**, Mod+Return = bare `herdr --remote` on the client, F10 backlight toggle, XF86 twins, media without cliamp, `brightness` `-n` fix + `off|restore` verb, `audio-route`/`call-record-menu` node guards, `clipboard`/launcher/F9 on fzf with rofi refs deleted (Q-7), lid `HandleLidSwitchDocked = "ignore"` everywhere (Q-15 default), voxtype chords unbound on the client (Q-1)); §8.1 deletions; §6.1 nvim osc52 gate; `hosts/nas/update-center.nix` hosts += `"client"` (cache warm only); `hosts/nas/omarchy-update-publish.py:19` `DEVICES` → `("xps",)` + the usage string; **a DECISIONS.md entry for R-1…R-18** (the historian notes DECISIONS.md has ZERO zenbook entries today — this is the first). Delete `hosts/coordinator/audio.nix`. | `nix flake check` green; `nix build .#nixosConfigurations.client.config.system.build.toplevel` (kernel build is long; the NAS did it in ~4 h for 7.2.4 — build on the NAS/worker or start early); coordinator closure still builds with `myDisplay.enable = true`; `nix eval .#nixosConfigurations.client.config.services.tailscale.extraUpFlags` shows the Funnel login server and `--accept-routes`; no `tailscale-authkey-client.age` exists. |
| 4 [Tom+agent] (was 6, minus the mint) | `nix develop -c agenix -r` (O-5) with the `client` recipient = the fleet public key; commit. ~~Mint the new host key … Mint `tailscale-authkey-zenbook-duo.age`~~ — nothing is minted (R-14, R-15). | `agenix -r` re-wrote `env`, `ssh-user-key`, `atuin-key`, `tom-password-hash`, `wifi-lan`; `wifi-lan.age` recipients are exactly `editors ++ coordinatorOnly ++ clientOnly` (worker DROPPED — DECISIONS.md act (4) discharged) and `modules/secrets.nix:434-442` no longer lists `"worker"`; `nix flake check` green. |
| 5 [Tom+agent] (was 5) | NAS: switch the NAS onto the branch (or cherry-pick) so `DEVICES = ("xps",)` is live — MUST precede the omarchy-fleet O-4 cleanup (step 13). headscale (O-3): `headscale nodes list` (node 4 present); `headscale nodes list-routes` → approve `10.42.0.0/24` from the NAS node if not approved; optional `headscale nodes rename -i 4 client`; expire stray fleet preauth keys. ~~headscale node 4 delete~~ (R-15). O-9 scratchpad/JSONL scrub. | `omarchy-update-publish` with no `--devices` succeeds for xps alone; node 4 still listed; the subnet route shows approved; `c-users.txt` gone. |
| 6 [Tom] (was 7, path changed) | **Install — path A (§4.5):** on the laptop (still Omarchy) as root: `mkdir -p /var/lib/tailscale && cp -a /var/lib/tailscale-fleet/tailscaled.state /var/lib/tailscale/tailscaled.state && chmod 0600 …` (I-8; then edit `ControlURL` to the Funnel URL the way `fleet-endpoint-migrate.py` does, or accept `--force-reauth` + a fresh preauth key on first `tailscale up`). From the coordinator: `nixos-rebuild switch --flake ~/mecattaf/dotfiles#client --target-host root@<lan-ip>` (closure built in step 3, so this is a copy + activation). Reboot once. Path B only if the laptop cannot be reached or does not come back: `nixos-anywhere … --extra-files <bundle>` with the private host key and the tailscale state extracted first (§4.5 B), kexec with the radio modules unloaded, never `--generate-hardware-config`, lease matched on MAC `a0:b3:39:06:75:a7`. Then O-6 residue removal by hand. | The §4.5 gate for the path taken: `hostname` = `client`; `ssh client` from the coordinator with NO TOFU prompt; `/run/agenix` populated; greetd → niri as tom; `thomas-6ghz` associated; `tailscale status` shows `100.64.0.4` (or the re-enrolled node); `systemctl --failed` empty; omarchy generation listed as rollback (A). |
| 7 [Tom] (was 8) | Dock + peripherals: plug the dock; `boltctl list` (enrol if not `+iommu`); `wpctl status` shows GS3 default sink + iContact default source; `amixer -c Pro sset Mic 36% cap`; Shift+F9 audio-route; F6-F8; Glove80 and Magic Trackpad (wired, Q-11) in `libinput list-devices`; `bluetoothctl list` shows the Duo's own controller. The MediaTek dongle STAYS on the coordinator. **The coordinator now has no keyboard or pointer**: until step 11 it is a lit niri host reachable by ssh only; keep a spare keyboard within reach for the VT getty. | Five peripherals enumerate; audio in/out works from Chrome; the coordinator still has a way in. |
| 8 [Tom] (was 9) | Dual-eDP + daemon: undock the keyboard → eDP-2 lights, kanshi `Duo` applies; dock → eDP-2 off, `DuoDocked`; F1/F2 from BOTH keyboards; F10 darkens both panels and F10/F2 restores; lid close = ignore (Q-15 default) in both states; touch on the top panel (global map). | `niri msg outputs` matches the state; `journalctl -u zenbook-duo-daemon` clean; `systemctl --failed` empty (asusd, screenpad mask); no dark-screen lockout. |
| 9 [Tom] (was 10) | **Seat proof — the R-13 trigger:** Mod+Return opens `herdr --remote coordinator` (projector); run the OSC 52 checks (a) AND (b) from §6.1 → (a) lands in `cliphist list`, (b) is LOST with focus on Chrome; copy from Claude Code in a remote pane → paste into Chrome on the client; `kitten ssh coordinator` lands in fish; ctrl+b / ctrl+shift+o handled by herdr's server-side keybindings (no hk on the client); `herdr --version` on the client equals the coordinator's. ~~Remmina `coordinator (VNC)` shows DP-1~~ — not a gate (A-3 narrowed). | (a), Claude copy, kitten ssh pass; (b) is documented as the accepted focus-gate defect; versions equal; herdr keybindings work. **When this row is green the client is Tom's seat and the flip proceeds immediately.** |
| 10 [agent] (was 15's code half) | **Flip commit** on the same branch: `myDisplay.enable = false` in `hosts/coordinator/default.nix`; DELETE the wayvnc unit, Remmina profile generator, the `5900` door (`hosts/coordinator/tailscale.nix:92`), kanshi `Desk`, the coordinator-side Remmina package; voxtype inert (Q-1 (c)); worker header prose → "ONLY the client has a display output"; `artifact-view` default → publish rung (Q-16 (b), skills tree); DECISIONS.md: "coordinator headless 2026-09-11; no VNC in the fleet". | `nix flake check` green (asserts now expect niri/greetd/wayvnc OFF on the coordinator, ON/absent on the client); coordinator closure builds; `grep -rn 5900 hosts/ home/` empty. |
| 11 [Tom] (was 15's physical half) | **Execute the flip:** `sudo nixos-rebuild switch --flake .#client`? — no: on the COORDINATOR, `sudo nixos-rebuild switch --flake .#coordinator` (from a `kitten ssh coordinator` window on the client, so the switch is driven from the seat); `systemctl --user restart herdr` so panes lose `WAYLAND_DISPLAY`; unplug DP-1 from the coordinator and plug it into the client's dock (Q-14 default → kanshi `DuoDock` applies). From now on the coordinator's inputs are ssh and a blind VT getty (§8.3). | herdr `--remote` from the client unaffected across the switch (reconnects); tally timers unaffected; OSC 52 copies still arrive; `ss -ltn` on the coordinator has no `:5900`; no `wl-copy` callers left in remote panes; `artifact-view` from a coordinator agent reaches the client via the publish rung; `niri msg outputs` on the client shows three outputs (or two, and the panel is retired per Q-14). |
| 12 [Tom] (was 11) | Boot-defect soak: 5 cold boots on battery, note any >60 s boot (`systemd-analyze`). Placed AFTER the flip so the flip is not held hostage to a ~25 min soak. | D-3 validated or the patch is re-based/dropped (Q-4). |
| 13 [agent] (was 12) | PR: `client-seat` → `worker-remote-wired` → **must reach `main`** (the nightly builds `github:mecattaf/dotfiles/main` only, I-5 — cache warmth, no activation). omarchy-fleet O-4 cleanup PR (AFTER step 5's NAS `DEVICES` edit is live). omarchy-nix O-10 entry. | PRs green and on main; NAS nightly build includes `client` (`attic` has its closure); the xps publish still works. |
| 14 [Tom] (new, R-15) | **Off-LAN proof:** take the client to a phone hotspot: `tailscale status` (control reached through Funnel 8443 — first real off-LAN laptop, `docs/nas/personal-tailscale.md:50`), `ip route get 10.42.0.2` → `dev tailscale0`, `ssh coordinator`, Mod+Return projector, OSC 52 (a). Back on `thomas-6ghz`: `ip route get 10.42.0.2` → wifi device, tailnet idle. | Both rows pass. If the subnet route is not approved or the control URL is unreachable, fall back to §4.3 shape (2) and file it. |
| 15 [agent, later] (was 14) | Follow-ups as issues (session A heuristic: issues, not handoffs): dictation on the client (Q-1 (a)), agent-view seam option (a) (§6.3), rotation/gestures (D-5, out of scope today), journal-upload admission (Q-8), lan-mouse/thunderbolt-net if the Mac is paired (Q-17, out of scope), herdr-kitten #26/#27 (coordinator-side), SoundCloud PWA / Nautilus on the client if R-16's default bites, ~~tailnet rail (Q-5)~~ closed, ~~tier-3 hk socket forwarding (Q-10)~~ closed. | Issues filed in the repo where each lives (dotfiles / herdr-kitten). |

---

## 11. What still blocks, and the defaults for everything else (R-18, 2026-09-11 pm)

**Nothing blocks step 1 or step 2.** The one-line answer is in the header: OK to power the
Zenbook Duo back on now. The single question that can still change the work is Q-3, and even
it has a default. Everything else is CLOSED with the default the agent takes; Tom overturns any
of them by saying so before step 3.

| ID | Status (2026-09-11 pm) | Default the agent takes | Changes |
|---|---|---|---|
| **Q-3** | **OPEN** — the dock model is unknown and no source records a Type-C/TB4 test on the Duo (§7.1). | Proceed as if the dock enumerates everything and drives the PA27JCV; step 2 measures it. If the Duo's port cannot drive the dock: peripherals go on a USB-C hub (R-7 unchanged in intent), the PA27JCV is retired and the `DuoDock*` profiles are deleted. | Step 2 gate; §7; Q-14's shape. |
| Q-1 | closed with default | (c) no dictation at the first switch; voxtype inert on the coordinator at the flip; (a) is a later issue. | §7.3, step 3, step 10. |
| Q-2 | closed with default | drop the bolt hunk from #369 before merge. | §7.2 bolt row. |
| Q-4 | closed with default | pin `linuxPackages_7_2` (7.2.4) + the MTL016 patch, the NAS way. | §4.2 kernel row; step 12 soak. |
| Q-5 | **ANSWERED by R-15** | (b) NAS headscale, node 4 kept, kernel-mode tailscale with `--accept-routes`, coordinator via the NAS subnet route off-LAN, direct on the LAN; no `Match`/`ProxyJump`. | §4.3, I-8, O-3, step 14. |
| Q-6 | closed with default | keep the daemon's eDP-1 → eDP-2 backlight sync (per-panel Shift+F1/F2 stays ineffective on eDP-2). | daemon config in step 3. |
| Q-7 | closed with default | fzf-in-kitty for Mod+D / Mod+V / F9; `vicinae` not added; rofi/rofimoji/wshowkeys references and scripts deleted. | §5.2, step 3. |
| Q-8 | closed with default | no journal-upload admission for the client. | I-7. |
| Q-9 | CLOSED | #353 has no bearing on §6. | — |
| Q-10 | closed with default | tier 1 only (`herdr --remote`); tier 3 would need hk on the client, which R-16 forbids. | §6.2. |
| Q-11 | closed with default | Magic Trackpad stays wired on the dock. | §7.2. |
| Q-12 | CLOSED | the MediaTek dongle is the coordinator's `hci0` and stays. | §7.2. |
| Q-13 | CLOSED, both halves | A-1 CONFIRMED (R-16: Chrome local on the client, kept on the coordinator); A-5 CONFIRMED (the reboot is the switch onto `7e544f5c`). | step 1. |
| Q-14 | closed with default | DP-1's PA27JCV moves to the client's dock at the flip → kanshi `DuoDock`/`DuoDockDocked`; the second, already-unplugged panel is retired. Recorded in the DECISIONS.md entry with R-1…R-18. | §4.4, §7.2, step 11. |
| Q-15 | closed with default | `HandleLidSwitchDocked = "ignore"` everywhere; F10 (backlight toggle) is the explicit verb; no `switch-events` hook unless step 8 shows the eDP-1-off migration to be a real nuisance. | §4.2 logind row, step 3, step 8 gate. |
| Q-16 | closed with default | the publish rung is the default view path when the agent host has no display; `ssh client google-chrome --app` forwarding is a later issue. | §6.3, step 10. |
| Q-17 | closed with default | the MacBook Air M5 is out of scope for dotfiles. | — |
| NPU | closed with default | DROP `hardware.cpu.intel.npu.enable` (§4.2). | step 3. |
| Install path | closed with recommendation | path A, in place (§4.5); B only if A cannot reach or boot the laptop. | step 6. |

---

## Appendix: source map

- Research reports (scratchpad, 2026-09-11): `r-session-A.md`, `r-session-B.md`, `r-session-C.md`,
  `r-git-archaeology.md`, `r-fleet-hardware.md`, `r-coordinator-desktop.md`, `r-thin-client-tech.md`,
  `r-dotfiles-tenure.md` (the historian; folded in 2026-09-11 pm: update-center never had the
  zenbook, `fleet-hosts.nix` twins-only, three-way roll-call, worker header supersession, wayvnc
  absence as a reversal of precedent, catch-up-leg ruling `4698216d`, DECISIONS.md has no
  zenbook entry).
- Added 2026-09-11 pm (R-12…R-18 verification): dotfiles `hosts/nas/headscale.nix:185-200,300-332`
  (subnet route, login-server placement), `hosts/nas/default.nix:116-121` (Funnel),
  `docs/nas/personal-tailscale.md:50,125-126`, `home/ssh.nix:1-107` (whole file), `home/herdr.nix:52-77`,
  `home/home.nix:88-100,165-182,258-260,305-314,384-396,505-516`, `modules/common.nix:20,53-58,205-240`,
  `modules/secrets.nix:24-36,165-182`, `hosts/coordinator/atuin.nix:5-14`, `hosts/coordinator/tailscale.nix:85-93`,
  `flake.nix:1936-1946,2385-2420,2470-2486`, `git show 77eac406^:{modules/mesh-registry.nix,hosts/zenbook-duo/{default,disko}.nix}`,
  `git show 22eebdc0^:{home/home.nix:156-188,overlays/default.nix:33-66}`, `~/.ssh/known_hosts:25`;
  omarchy-fleet `modules/fleet-registry.nix` (whole), `modules/fleet-rail.nix:8,23-24,31-38,63-108`,
  `profiles/fleet-common.nix:48`, `lib/laptop-disko.nix`, `modules/fleet-common.nix:48-49`,
  `docs/flash.md:10,16,95-98,135-152`, `docs/offboarding.md:19-27`, `docs/fleet-endpoint-migration.md:133-136,198-231`,
  `scripts/fleet-endpoint-migrate.py:23,49-50,79,102,141`, `docs/zenbook-duo-boot-2026-09-10.md:1-8`,
  `flake.nix:74-99`; `LEDGER.md` grep for the host-key gate result (empty).
- dotfiles (HEAD `7e544f5c`): `flake.nix:1829-1953,2385-2416,2480-2481`, `modules/common.nix:52,82-83,117,210-234,255-256,298-323`, `modules/gc-retention.nix:41`, `hosts/coordinator/atuin.nix:10`, `hosts/coordinator/services.nix:221`, `hosts/coordinator/nas-client.nix:276,383`, `hosts/nas/omarchy-update-publish.py:19,217`, `home/dot_config/niri/{misc,window-rules}.kdl`, `home/dot_config/herdr/config.toml:49-58`, `home/dot_config/niri/scripts/audio-route:6-9`, `DECISIONS.md:57-58,79-80`, `AGENTS.md:20-24`,
  `modules/headless.nix`, `modules/mesh-registry.nix`, `modules/fleet-hosts.nix`, `modules/secrets.nix`,
  `secrets.nix:43-113`, `hosts/worker/default.nix:1-80`, `hosts/coordinator/{audio,tailscale}.nix`,
  `hosts/nas/{update-center,omarchy-update-center,journal,headscale,kernel}.nix`, `home/{home,ssh,remote,herdr,voxtype}.nix`,
  `home/dot_config/kanshi/config`, `home/dot_config/niri/{config,binds,startup,input}.kdl`,
  `home/dot_config/niri/scripts/sleep-monitors`, `home/dot_config/fish/conf.d/remote.fish`,
  `home/dot_config/kitty/kitty.conf`, `home/dot_local/bin/{brightness,clipboard,clip2path}`.
- dotfiles history: `77eac406^` (host, registry row, secrets tiers, ssh alias, update-center, flake),
  `22eebdc0^` (ntm, niri-pr1856 overlay, niri-local.kdl branch), `e1f3f312`, `1e05c4c6`, `c0ebbf71`,
  `061b5be7`, `ef70e0a6`, `f32289cb`, `03a49294`, `41fc8a0b` + `0fce0cae` (PR #369, unmerged, head `0fce0cae`).
- omarchy-fleet (HEAD `62ce751`): `profiles/zenbook-duo.nix`, `hosts/zenbook-duo/hardware.nix`,
  `modules/zenbook-duo-daemon.nix`, `modules/zenbook-duo-rotate.nix`, `modules/fleet-registry.nix`,
  `pkgs/zenbook-duo-daemon.nix`, `pkgs/patches/vmd-mtl016-7.2.4.patch`, `docs/{offboarding,handover,flash,zenbook-duo-boot-2026-09-10,zenbook-duo-research,fleet-endpoint-migration}.md`, `LEDGER.md`.
- herdr-kitten: `hk/{kittyc,verbs,remote,herdrc,voice,predicate}.py`, `bin/hk:228-236`, `docs/mapping.md` P22-28, P56-63.
- omarchy-fleet `LEDGER.md:383-404` (A-19); omarchy-nix `FINALIZATION.md:1-10`.
- Store artefacts read on the coordinator: `…-niri-26.04/bin/niri` (selection-denial string), `…-niri-26.04-doc/…/Configuration:-Switch-Events.md`, `…-systemd-261.2-man/…/logind.conf.5.gz`, `…-fish-4.7.1/…/fish_clipboard_copy.fish`, `…-neovim-unwrapped-0.12.4/…/provider/clipboard.vim`, `herdr --default-config`, `brightnessctl --help`, `niri msg output --help`.
- Upstream sources cited by the critique and NOT re-read here (tagged INFERRED wherever used): niri `src/layout/mod.rs` (`MonitorSet::NoOutputs`), kanshi `main.c` (`apply_profile` early return, profile/head count match), PegasisForever/zenbook-duo-daemon `src/secondary_display.rs` / `src/virtual_keyboard.rs` / `src/keyboard_usb.rs`, Linux `drivers/gpu/drm/i915/display/intel_backlight.c`, herdr.dev `connecting-machines`.
- Session transcripts consulted through the scratchpad extracts: `c-users.txt` (session C, Tom's turns), `sessA-user.txt`/`sessA-assistant.txt`, `sessB-user.txt`/`sessB-assistant.txt`.
- Live probes on the coordinator: `niri --version`, `niri msg outputs`, `niri validate`, `wpctl status`,
  `/sys/bus/usb/devices`, `/sys/class/bluetooth/hci0`, `bluetoothctl devices`, `brightnessctl -l`, `/proc/<herdr>/environ`, `gh pr list`,
  `gh pr view 1856 -R niri-wm/niri`, `gh issue view 353`, `~/.ssh/known_hosts`, `~/.config/kitty/hk-assets`, `herdr --version`.

## Appendix: critique findings disputed or applied with correction (revision of 2026-09-11, 47 findings)

All 47 findings were checked against the cited paths on the coordinator before editing. 46 hold
and are applied above. Disputes and corrections:

- Disputed (in part) — "There is no flake check named `home-profiles`": there IS one,
  `flake.nix:1829` (`home-profiles =`) built by `pkgs.runCommand "home-profiles"` at `:1953`
  (VERIFIED); the herdr asserts the finding lists (1858-1860, 1899, 1924, 1930) live INSIDE it.
  The doc keeps the name and now cites the lines; the INFERRED tag was dropped as the finding
  asked.
- Correction — the finding on PR #369 says the `9c:bf:0d:01:cc:65` pin is "in that second
  commit"; `git log -S'9c:bf:0d:01:cc:65' 7e544f5c..0fce0cae` returns BOTH `0fce0cae` and
  `41fc8a0b` (the string is touched by both), so the doc says "the worker Ethernet-MAC pin in
  `0fce0cae`" only for the dnsmasq reservation that commit's subject names.
- Correction — the passcode finding counts "two six-digit values" on `c-users.txt:94`; the line
  was confirmed to contain passcode digits (count not re-verified beyond "present"); values were
  not reproduced anywhere in this document.
- Not re-verified (upstream source not on this machine; kept as INFERRED where used): the
  niri `NoOutputs` layout state, kanshi `apply_profile`/head-count behaviour, the daemon's
  500 ms copy loop and uinput key emission, i915 backlight-off-at-zero, herdr.dev reconnect and
  multi-client statements, and the live `ssh -o BatchMode=yes coordinator 'command -v herdr'`
  probe (replaced by a local check of `/etc/profiles/per-user/tom/bin/herdr`; agents may not ssh
  to other hosts, and ssh to self was not exercised).
- Not applied as worded — "delete c-users.txt / redact the JSONL line" was scheduled as O-9
  rather than performed: this revision is read-only on repos and transcripts.

## Provenance

- Research reports (scratchpad `/tmp/claude-1000/-home-tom/93dc2790-9d43-4f70-916e-515ab0a83159/scratchpad/`):
  `r-session-A.md`, `r-session-B.md`, `r-session-C.md`, `r-git-archaeology.md`,
  `r-fleet-hardware.md`, `r-coordinator-desktop.md`, `r-thin-client-tech.md`
  (+ `r-dotfiles-tenure.md`, written after the first draft, not cited above).
- Session transcripts: Claude `2ae71708-871b-4786-b378-9bdfbbdce543`
  (`/home/tom/.claude/projects/-home-tom/`, 2026-09-10 → 09-11); Claude
  `b98d7c74-9c62-4ed8-b0f8-93d282e3e843`
  (`/home/tom/.claude-work/projects/-home-tom-mecattaf-dotfiles/`, 2026-09-11); Codex
  `01a08a20-4e41-7ec2-802a-269b3428bd23` (`/home/tom/.codex/sessions/2026/09/10/`, 2026-09-10).
- Critique lenses applied in this revision (47 findings): **repo-truth** (17: line references,
  commit hashes, gates, rulings already made), **thin-client-design** (12: F10/backlight,
  output-off lockout, XF86 keys, brightness floor, focus-gated OSC 52, herdr version skew,
  Mod+Return spelling, fish/nvim/Claude clipboard paths, ControlMaster after sleep, lid
  semantics, dock unplug), **completeness** (18: Q-5 vs the 09-10 ruling, tailscale0-scoped
  doors, passcode exposure, MediaTek = hci0, XF86 keys, agent-view seam, issue #353, agency
  vision, omarchy-nix fate, publisher DEVICES ordering, pull path, herdr auto-resume at reboot,
  flake display asserts, coordinator keyboard, PA27JCV fate, wifi-lan rekey, hk-assets,
  session A threads).
- Revised on the coordinator, 2026-09-11, read-only against dotfiles HEAD `7e544f5c`,
  omarchy-fleet HEAD `62ce751`, omarchy-nix; nothing committed.
- **Revision 2, 2026-09-11 afternoon:** folded in rulings R-12…R-18 (hostname `client`,
  headless next, no key recreation, headscale rail, near-zero updates, seat semantics,
  orchestration style) and the historian's report. Sections touched: header, §0, §1 (R-3/R-9
  annotated, R-12…R-18 added, A-1/A-3/A-4/A-5/A-6 resolved), §2.1, §2.2 (live status, rail
  facts, host-key provenance), §2.3, §3 (O-1, O-3, O-5, O-6, O-7, O-9), §4 (framing table, I-1…I-8,
  §4.2 verdicts, §4.3 rail/ssh/firewall, §4.4, new §4.5 install path), §5.1, §5.2, §6.1–6.3,
  §7.2–7.3, §8 (8.2, 8.3), §9 (D-1, D-3, D-5, D-10, D-11, D-12), §10 (re-sequenced, 15 steps,
  flip at 10–11), §11 (one open question + defaults), appendix. Same read-only discipline;
  nothing committed; the file is untracked and keeps its name.
