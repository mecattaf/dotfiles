# HANDOFF — Huion Note X10 → `client` → `coordinator:~/Paper/inbox`

**From:** Claude Code session on `client` (2026-09-13, session `4231dd92-1251-4d46-bffd-365f0c42cb71`)
**To:** the Claude session working in `~/mecattaf/dotfiles` on `coordinator`
**Your job:** make the Huion → client → coordinator pipeline **permanent and automatic, declared entirely in dotfiles**, then prove it end to end on the real hardware. OCR is **out of scope**; it will be built later on the coordinator and will consume `~/Paper/inbox`.

You have SSH access to `client` (10.42.0.16, pinned DHCP lease) for all testing. Tom is available to open, write on and press the button on the notepad when you ask.

---

## 0. TL;DR

- **Proven in this session:** the manual pipeline, end to end on real hardware. A reverse-engineered BLE extractor pulls handwritten pages off the Huion over Bluetooth, and each page lands as SVG/PNG/JSON (strokes with pressure). It needs:
  1. the extractor repo, **pinned** to `6f3f5e73fbb776dabeea54f54b411690a1c14091`;
  2. a **2-line BlueZ patch** (still required on BlueZ 5.86);
  3. unbinding the notepad from `hid-generic` **on every connect**, via a udev rule.
- **Nothing is declared yet.** Every piece was temporary and **has been removed**. `client` is back on stock `bluetooth.service`. The notepad **stays paired, bonded and trusted** in `/var/lib/bluetooth`, so you do not need to pair it again.
- **Your deliverable:** a `client`-gated module that provides:
  1. the patched `hardware.bluetooth.package`;
  2. a udev rule that unbinds `hid-generic` **and** starts a sync service;
  3. a sync service with a lock that dumps (clearing the device) into a local holding folder, then rsyncs to `coordinator:~/Paper/inbox/<timestamp>/`, deleting the local copy only after the push succeeds;
  4. a retry timer for anything left in the holding folder;
  5. the thin-stroke render fix;
  6. a `DECISIONS.md` entry.

  Then deploy and run the acceptance tests in §7.

---

## 1. Tom's intent (verbatim where it matters)

- **Daily use:** "keep writing normally into it whether i m indoors or outdoors, pressing the button on the next page event, and then when i m near that laptop just open the huion note so that it syncs".
- **"the huion IS the inbox!"** Synced pages go to **`~/Paper/inbox/` on the coordinator**, not `intake/`, which holds printable markdown and belongs to the print loop.
- **"auto-sync is indeed wanted but let's have this setup the right way from dotfiles side first".** No hand-run daemons, no scratch scripts.
- **Clearing synced pages from the device:** "this is indeed desirable".
- **Stroke width:** Tom chose sample **(b), thin**, i.e. `stroke-width` **1.2** on the extractor's 900 px canvas (default 2.5). See `test-sync-output/width-test/`.
- **"everything that has been written on the huion has been for testing purpose".** The 3 pages currently on the device are disposable. The first real sync may clear them and push them to the inbox, or you can clear them first; either is fine.
- **Topology:** `client` is the thin client. Everything that thinks runs on `coordinator`, and Mod+Return on the client is a herdr window into it. The Bluetooth radio is on the client, so this sync is a **deliberate, narrow exception** to "the client runs nothing". Record it in `DECISIONS.md`.

---

## 2. Hardware and environment facts (verified on the metal)

| Fact | Value | How verified |
|---|---|---|
| Device name | `Huion Note-X10` | BLE scan |
| BT address | `25:6C:20:F5:D8:25` (public) | `bluetoothctl info` |
| Pairing state | Paired: yes, Bonded: yes, Trusted: yes (stored in `client:/var/lib/bluetooth`) | `bluetoothctl info` after restore |
| HID id when connected | `0005:256C:8251.<instance>` (instance increments each reconnect: `.000E`, `.0010`, `.0012`) | `/sys/bus/hid/devices` |
| Input handlers it gets | `sysrq kbd event…` (BlueZ HOGP registers it as a **keyboard**) | `/proc/bus/input/devices` |
| GATT (notes) | service `ffe0`; `ffe1` notify = handle `0x0027` (char0026); `ffe2` write/indicate = handle `0x002b` (char002a) | GATT dump in session |
| Device limits (MAX_DATA) | `max_x=28200 max_y=37400 max_press=8191` | live `cd 95` reply |
| Client BT adapter | Intel AX211, controller `A0:B3:39:06:75:AB` | `bluetoothctl show` |
| BlueZ | 5.86 (stock nixpkgs, `/nix/store/2h46qdsjjin30m4apdhwapwvchn1gc7m-bluez-5.86`) | `bluetoothctl --version` |
| Stock bug present in 5.86 | `src/shared/att.c` lines 1081–1089 still `io_shutdown` on a duplicate request | read nixpkgs tarball source |
| Client system | `nixos-system-client-26.11.20260723.e2587ca` | `/run/current-system` |
| client → coordinator | `coordinator` = `10.42.0.2` (`networking.hosts` in `hosts/client/default.nix`); `ssh -o BatchMode=yes coordinator` works as `tom` with `~/.ssh/id_ed25519`; rsync on both | tested |
| Coordinator `~/Paper` | `inbox/` (empty, referenced nowhere in dotfiles), `intake/` (9 md docs, print loop), `jobs/` (251), `outbox/` (empty), `src/` (1) | `ls` over ssh |
| Dotfiles checkouts | coordinator `~/mecattaf/dotfiles` = `1214c6d9` **main** (canonical); client `~/mecattaf/dotfiles` = `54c17bed` branch `client-fan-quiet`; client `~/dotfiles` = stale `882ddd0d` (ignore) | `git rev-parse` |

---

## 3. Operating the notepad (for Tom and for your tests)

- **Open the cover = on.** The LED goes solid green, which means offline recording. Blue means a host is connected in the official app's live mode; we never saw blue, and the extractor doesn't need it. **Close the cover = off/sleep**, and the link drops.
- **The single button (top right) = "page done / new page".** Strokes before the press stay on page N, strokes after go to N+1. **Verified:** a double press created no empty page.
- **Only the right-hand side is digitised,** inside the dotted border of the official pad (roughly 14 × 19 cm, estimated from the coordinate range assuming 5080 LPI). The left side is just the cover. The loose "panel" in the box is **for pen-tablet mode only** and has no role in note sync.
- **Writing more on a page that was synced with `--keep` appends:** the earlier strokes come back byte-identical, followed by the new ones (verified twice).
- **The repo's docs say "note mode = folio cover closed". That is WRONG for this unit.** The sync works with the cover **open, light green**, and when closed the device is asleep.
- **On opening,** BlueZ auto-reconnects the trusted, bonded device with no scan or connect needed. **Verified:** `Connected: yes` was already true before the sync script tried to connect.

---

## 4. What the extractor is and how to run it

**Repo:** <https://github.com/Reginleif88/huion-note-x10-ble> (MIT), pinned to `6f3f5e73fbb776dabeea54f54b411690a1c14091`.
- An offline copy without `.git` is in `artifacts/reference/huion-note-x10-ble@6f3f5e7/`.
- Relevant parts:
  - `huion_notes/` — the extractor package
  - `huion_ble_driver.py` — imported by `huion_notes/transport.py` for `BLEConnection`
  - `patches/fix-duplicate-mtu-request.patch`
  - `99-huion-note-x10.rules`
  - `docs/offline-note-protocol.md`
  - `docs/notes/journey.md` (the HOGP analysis is around lines 994–1170)
- **The README is stale in places:**
  - it references `modules/huion-ble.nix`, which doesn't exist;
  - it says "cover closed";
  - it says the device connects "unbonded".

**CLI:** `python3 -m huion_notes dump -o OUT [--mac MAC] [--pin PIN] [--keep] [--verbose]`
- **Needs:** `PYTHONPATH=<repo root>`, Python with `dbus-fast`, and `magick` (ImageMagick) on PATH for PNGs.
- **Output:** `OUT/page{N}-{DD}-{MM}.{svg,png,json}`. The JSON is `{page,max_x,max_y,max_press,strokes:[[{x,y,press,pen_down}]]}`.
- **Default behaviour:** after SVG and JSON are confirmed on disk, it sends `DELETE_PAGE (0x8b)` per page, then `CLEAR_CACHE (0x8c)`. `--keep` skips that. Incomplete pages are never deleted.
- **The empty error `error: dump failed: ` is an `asyncio.TimeoutError`,** whose text is empty. In this session it always meant HOGP had silenced notifications, or the pairing authorization was still pending (§5).

**Successful protocol trace** (`artifacts/logs/trace3.log`, 2 pages, about 6.3 s):
```
>> cd 81 08 00 00 00 00 ed          VERIFY_CONNECT
<< cd 81 06 16 7a 45                challenge
>> cd 82 08 42 fe 3d 00 ed          VERIFY_RESULT
<< cd 82 04 01                      ok (no PIN set)
>> cd 95 …  << cd 95 0b 28 6e 00 18 92 00 ff 1f   MAX_DATA 28200/37400/8191
>> cd 96 08 01 03 … / cd 96 08 03 02 …          packet distance
>> cd 86 08 00 …   << cd 86 05 72 02            page 0: 0x0272 = 626 packets → cd 87 stream
>> cd 86 08 01 …   << cd 86 05 32 00            page 1: 50 packets
>> cd 86 08 02 …   << cd 86 05 00 00            count 0 → stop
```

---

## 5. The three blockers found, in the order hit (all must be handled declaratively)

### 5.1 BlueZ duplicate-MTU disconnect → patch BlueZ (REQUIRED)
- **Symptom:** the X10 sends a duplicate ATT MTU request and stock BlueZ drops the link.
- **Evidence the patch is used:** the patched daemon logged `Received request while another is pending: 0x02 (dropping duplicate)` during a successful connection.
- **The patch** is the repo's file, and it applies cleanly to 5.86 (confirmed in the build log: `applying patch …fix-duplicate-mtu-request.patch`):
  ```diff
  --- a/src/shared/att.c
  +++ b/src/shared/att.c
  @@ -1080,12 +1080,10 @@
   		 */
   		if (chan->in_req) {
   			DBG(att, "(chan %p) Received request while "
  -					"another is pending: 0x%02x",
  +					"another is pending: 0x%02x "
  +					"(dropping duplicate)",
   					chan, opcode);
  -			io_shutdown(chan->io);
  -			bt_att_unref(chan->att);
  -
  -			return false;
  +			return true;
   		}
   
   		chan->in_req = true;
  ```
- **Build used in the session** (`artifacts/scripts/bluez-patched.nix`), output `/nix/store/n4sihvfbvc4dn0qzwm3vnnn25pv9wq04-bluez-5.86`:
  ```nix
  pkgs.bluez.overrideAttrs (old: { patches = (old.patches or [ ]) ++ [ ./fix-duplicate-mtu-request.patch ]; })
  ```
- **Declare** it through `hardware.bluetooth.package`, gated to `client`. Only the Bluetooth service package changes, so nothing that depends on `bluez` gets rebuilt.

### 5.2 Pairing authorization prompt → one-time, ALREADY DONE
- **Symptom:** the X10's HID service triggers a "just works" pairing (`user_confirm_request_callback … confirm_hint 1` → `Agent.RequestAuthorization`).
  - **With no agent:** `No agent available for request type 2` → `device_confirm_passkey: Operation not permitted`, followed by a reconnect loop every ~2 s.
  - **With a stdin-less `bluetoothctl` agent:** the prompt `Accept pairing (yes/no)` hangs forever, `ServicesResolved` never becomes true, and the extractor fails with `Connected but GATT services not resolved`.
- **Fix used:** a `bluetoothctl` agent fed from a FIFO, answering `yes` (`artifacts/scripts/bt-agent-restart.sh`). The device then became **Paired and Bonded**.
- **After bonding, reconnects raised no further prompts** (checked in the agent log). **Do not add a permanent agent.**
- **Document the manual re-pair procedure** in the module comment, for when the bond is lost (new adapter, `/var/lib/bluetooth` wiped, device reset). Run as `tom` on client with the notepad open:
  ```
  bluetoothctl
  agent NoInputNoOutput
  default-agent
  scan on          # wait for "Huion Note-X10"
  trust 25:6C:20:F5:D8:25
  connect 25:6C:20:F5:D8:25
  # answer "yes" at "Accept pairing (yes/no)"
  ```

### 5.3 HOGP / hid-generic claims the device → unbind on EVERY connect (REQUIRED)
- **Symptom:** after connecting, BlueZ's HID-over-GATT creates a uhid device `0005:256C:8251.*` bound to `hid-generic`, which registers as a keyboard. The extractor's notifications then stall and the dump times out.
- **Evidence:**
  - the first dump attempts timed out with the empty error;
  - an otherwise identical run right after `echo 0005:256C:8251.000E > /sys/bus/hid/drivers/hid-generic/unbind` succeeded;
  - a dump right after a reconnect **with a manual unbind a moment too late** failed, and the retry succeeded;
  - with the repo's udev rule loaded, the sync after closing and reopening **succeeded on the first try**, and sysfs showed `driver=none` on the fresh `.0012` instance.
- **Rule used** (verbatim from the repo; it passed `udevadm verify`):
  ```
  SUBSYSTEM=="hid", KERNEL=="0005:256C:8251.*", RUN+="/bin/sh -c 'echo %k > /sys/bus/hid/drivers/hid-generic/unbind 2>/dev/null || true'"
  ```
- **Declare** it via `services.udev.extraRules` on `client`. The repo's other line (`uinput` group) is for the live pen driver and **not needed**; Tom doesn't want tablet mode.
- **Note:** `UserspaceHID=true` does NOT stop HOGP (per the repo journal). Disabling the `input` plugin globally would also break the Zenbook Duo's Bluetooth keyboard (`D9:D8:5B:AC:01:05`), so **do not** do that. Use the unbind.

---

## 6. Target design (what to declare)

Put it in its own module, e.g. `hosts/client/huion.nix`, imported from `hosts/client/default.nix`, with a fat header comment in the house style. Things to decide:
- system service vs user service;
- file layout;
- anything this sketch gets wrong for the tree's conventions.

The **house conventions** in `DECISIONS.md`/`AGENTS.md` win over this sketch.

### 6.1 Package the extractor
```nix
huionSrc = pkgs.fetchFromGitHub {
  owner = "Reginleif88"; repo = "huion-note-x10-ble";
  rev = "6f3f5e73fbb776dabeea54f54b411690a1c14091";
  hash = lib.fakeHash;               # fill from the first build error
};
# Thin strokes (Tom's pick "b"): patch the render width at build time.
huionSrcPatched = pkgs.runCommand "huion-note-x10-ble-src" { } ''
  cp -r ${huionSrc} $out; chmod -R u+w $out
  substituteInPlace $out/huion_notes/render.py --replace-fail 'stroke-width="2.5"' 'stroke-width="1.2"'
'';
py = pkgs.python3.withPackages (ps: [ ps.dbus-fast ]);
huion-notes = pkgs.writeShellApplication {
  name = "huion-notes";
  runtimeInputs = [ py pkgs.imagemagick ];
  text = ''PYTHONPATH=${huionSrcPatched} exec python3 -m huion_notes "$@"'';
};
```
- `render.py` line 30 is currently `paths.append(f'<path d="{d}" fill="none" stroke="#111" stroke-width="2.5"/>')`. Check that `--replace-fail` matches it.
- The PNG is produced from the SVG by ImageMagick, so it inherits the width.
- Consider adding `stroke-linecap="round" stroke-linejoin="round"` too; the session's (b) sample used them. Optional.

### 6.2 Sync script (`huion-sync`)
```
set -euo pipefail
exec 9>"$XDG_RUNTIME_DIR/huion-sync.lock" (or /run/huion-sync.lock); flock -n 9 || exit 0
SPOOL=~tom/.local/state/huion/spool
ts=$(date +%Y-%m-%d_%H%M%S); out=$SPOOL/$ts; mkdir -p "$out"
sleep 3                                    # let BlueZ resolve services + udev unbind land (connect() itself waits ≤8 s)
huion-notes dump --mac 25:6C:20:F5:D8:25 -o "$out" || rc=$?   # NO --keep: device is cleared after local save
rmdir "$out" 2>/dev/null || true           # "no offline pages found" leaves it empty
# push every spooled batch (this one + any earlier failures), oldest first
for d in "$SPOOL"/*/; do
  rsync -a --remove-source-files -e 'ssh -o BatchMode=yes -o ConnectTimeout=5' "$d" "coordinator:Paper/inbox/$(basename "$d")/" && rmdir "$d"
done
```
- **Ordering is intentional.** The extractor deletes pages from the device after the **local** save, which the tool can't delay until after the push. The local holding folder is the durability buffer, so a coordinator that's down or unreachable costs nothing.
- **Filenames:** `page{N}-{DD}-{MM}` restarts at `page1` after every clearing sync, so **per-sync timestamp folders are mandatory**. Without them, two syncs on the same day overwrite each other.
- **Inbox layout Tom approved:** `coordinator:~/Paper/inbox/<YYYY-MM-DD_HHMMSS>/page{N}-DD-MM.{svg,png,json}`. Nothing else should live in `inbox/`.
- **A dump failure after a partial save** leaves complete pages locally and incomplete ones on the device (the tool's own guarantee). Push whatever exists and exit non-zero so the journal shows it.
- **Optional:** a desktop notification on the client (niri session) with the page count. Nice to have, not required.

### 6.3 Trigger (auto-sync)
- **Add to the udev rule** so the connect event also starts the service:
  ```
  SUBSYSTEM=="hid", KERNEL=="0005:256C:8251.*", ACTION=="add", RUN+="/bin/sh -c 'echo %k > /sys/bus/hid/drivers/hid-generic/unbind 2>/dev/null || true'", TAG+="systemd", ENV{SYSTEMD_WANTS}+="huion-sync.service"
  ```
  - Each reconnect creates a **new** HID instance (`.000E` → `.0010` → `.0012`), so `add` fires once per opening.
  - **Unverified:** whether `SYSTEMD_WANTS` works for this virtual `uhid` device. If it doesn't, use `RUN+="${pkgs.systemd}/bin/systemctl --no-block start huion-sync.service"`.
- **System vs user service:** a system `huion-sync.service` with `User=tom` is simplest for a udev trigger, since it needs tom's SSH key for rsync and read access to the system D-Bus for BlueZ (fine as a normal user). Keep `Type=oneshot` and make it idempotent.
- **Retry timer:** e.g. `OnBootSec=2min`, `OnUnitActiveSec=15min`, running **only the push loop**, for when the coordinator was unreachable. It must never dump; the dump happens only when the notepad connects.

### 6.4 Gating and records
- **Everything is `client`-only:** `networking.hostName == "client"`, or simply live under `hosts/client/`. The flake's home-profiles check asserts coordinator-only things are absent on client, so keep this at NixOS level under `hosts/client/`, not in `home/` behind a hostname check, unless the tree's conventions say otherwise.
- **Add a `DECISIONS.md` entry (2026-09-13).** Its substance:
  - the Huion Note X10 is the paper inbox;
  - the client runs a patched `bluez` and a udev-triggered one-shot sync, because the BT radio is on the client;
  - pages go to `coordinator:~/Paper/inbox/<ts>/`;
  - the device is cleared after the local save;
  - OCR is a later coordinator-side consumer.

  Also update the "WHAT IT IS NOT" list in `hosts/client/default.nix`: the client is no longer purely "not a server of anything", and it now has one sync unit.
- **Deploy** per the tree's documented path, one of:
  - Tom, docked: `sudo nixos-rebuild switch --flake github:mecattaf/dotfiles/main#client`
  - from the coordinator: `nixos-rebuild switch --flake .#client --target-host root@10.42.0.16`

  Check DECISIONS R-18 for which is current.

---

## 7. Acceptance tests (run in order, on the metal, via `ssh client`)

1. **Patched BlueZ active:**
   - `systemctl status bluetooth` shows ExecStart pointing at the **patched** store path, not `…2h46qdsj…-bluez-5.86`.
   - `grep -a -c 'dropping duplicate' <that>/libexec/bluetooth/bluetoothd` returns `1`.
2. **Bond survived deploy:** `bluetoothctl info 25:6C:20:F5:D8:25` shows Paired/Bonded/Trusted yes. If not, re-pair per §5.2 with Tom.
3. **Unbind on connect:** ask Tom to open the notepad.
   - `ls /sys/bus/hid/devices/ | grep 256C` shows the new instance.
   - `readlink /sys/bus/hid/devices/0005:256C:8251.*/driver` returns nothing (unbound).
4. **Auto-sync fires:**
   - `journalctl -u huion-sync -b` shows exactly one run per opening.
   - The device's current pages (3 disposable test pages, unless already cleared) appear in `coordinator:~/Paper/inbox/<ts>/` with thin strokes.
   - The local holding folder ends empty.
5. **Device cleared:**
   - ask Tom to close, reopen and do nothing new → the journal shows "no offline pages found", no inbox folder is created, and the holding folder is empty.
6. **Real flow:** Tom writes page A, presses the button, writes page B, closes it. Later, "near the laptop", he opens it → one new inbox folder with exactly `page1` (A) and `page2` (B).
7. **Coordinator down:**
   1. temporarily block the push (e.g. point `ssh` at a bad host via a test override, or stop sshd on the coordinator *only if Tom agrees*);
   2. write and sync a page → pages are kept in the holding folder, the journal shows the push failed, and the device is cleared;
   3. restore → the retry timer (or next opening) delivers them, and the holding folder empties.
8. **Zenbook Duo BT keyboard unaffected:** `D9:D8:5B:AC:01:05` still connects when the keyboard is detached.
9. **Reboot client** → steps 3–4 still work with no manual action.

---

## 8. Gotchas we hit (save yourself the time)

- **Never kill processes with `pkill -f`/`pgrep -f` from a shell command that contains the pattern.** It matches its own shell and kills your command (exit 144). This happened twice. Kill by `pgrep -x` plus a `/proc/<pid>/cmdline` check (see `artifacts/scripts/bt-restore.sh`).
- **A stdin-less `bluetoothctl` agent hangs on yes/no prompts.** Feed it from a FIFO if you ever need an interactive agent again.
- **Hand-running `bluetoothctl … scan on` evicts and re-adds unrelated devices.** That's harmless noise in the logs.
- **D-Bus activation:** if you hand-run `bluetoothd`, start it **before** anything touches `org.bluez`, or activation brings the stock unit back. With the declared package this is moot.
- **The launcher `huion-x10-notes.sh`** uses `nix-shell` to supply `dbus_fast` and pauses pen-driver user units. Don't use it in the declared service; call `python3 -m huion_notes` with a Nix-built Python (§6.1).
- **`magick` must be on PATH,** or the PNGs are silently skipped (the SVG and JSON are still written).
- **Official Huion docs:** open = on/green, close = off; the one button = new page. Keep ink inside the dotted border.

---

## 9. What is in this bundle

```
huion/
├── HANDOFF.md                         ← this file
├── session/4231dd92-….jsonl           ← full transcript of the client-side session
├── test-sync-output/                  ← every test sync (disposable content, useful as fixtures)
│   ├── page1-13-09.*                  sync 1: 1 page, 86 strokes
│   ├── run2/                          sync 2: same page, 159 strokes (append test)
│   ├── run3/                          sync 3: page1 190 + page2 16 (button test)
│   ├── run4/                          sync 4: page1 190 + page2 16 + page3 37 (reconnect + udev rule test)
│   ├── delta-run1-run2.*, delta-run2-run3-page1.*   grey=old, red=new stroke diffs
│   └── width-test/                    stroke-width samples a/b/c/d — Tom picked b (1.2 @ 900px)
└── artifacts/
    ├── scripts/                       session's temporary tooling (NOT for dotfiles; reference only)
    │   ├── bluez-patched.nix          the patched-bluez build expression
    │   ├── bt-patched-start.sh        swap in hand-run patched bluetoothd + agent
    │   ├── bt-agent-restart.sh        FIFO-fed agent (answer pairing prompts)
    │   ├── bt-restore.sh              undo all of the above (PID-safe)
    │   ├── sync-test.sh               one sync attempt with state printout
    │   └── dump_traced.py             runs huion_notes unchanged, logs every frame
    ├── logs/
    │   ├── trace1.log, trace3.log     frame-level traces of successful dumps
    │   ├── bt-agent.log               pairing prompt + bond
    │   └── bluetoothd-patched.log     full debug log of the patched daemon (all attempts)
    └── reference/huion-note-x10-ble@6f3f5e7/   offline copy of the pinned repo (no .git)
```

## 10. Current state of `client` at handoff

- **Bluetooth:** stock `bluetooth.service` active (`/nix/store/2h46qdsjjin30m4apdhwapwvchn1gc7m-bluez-5.86`). No hand-run daemon, no agent, no `/run/udev/rules.d` rule.
- **Huion:** Paired, Bonded, Trusted. Until the patched BlueZ is deployed, opening the notepad near the client will just cycle connect/disconnect, which is harmless.
- **Device contents:** 3 test pages (190/16/37 strokes), all disposable.
- **Files:** nothing else from this session is installed on the client outside `~/huion` and the Nix store build outputs (collectable garbage).
