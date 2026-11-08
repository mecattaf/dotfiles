#!/usr/bin/env bash
# runtime-test -- env DOMICILE_BIN=/absolute/package/bin/domicile \
#   dbus-run-session -- bash tests/domicile-apps/practice.sh OUTDIR
# DOMICILE_BIN is optional; an explicitly supplied invalid path never falls back.
set -euo pipefail
[[ $# == 1 ]] || { echo 'usage: [DOMICILE_BIN=/absolute/binary] practice.sh NEW_OUTDIR' >&2; exit 2; }
D_REQUESTED="${DOMICILE_BIN-/nix/store/sz1pfpfw4wjyxbi6w7ils7nwip8kajy1-domicile/bin/domicile}"
[[ "$D_REQUESTED" == /* && -f "$D_REQUESTED" && -x "$D_REQUESTED" ]] || {
  echo 'DOMICILE_BIN must be an absolute path to an executable file' >&2
  exit 2
}
D=$(realpath -e -- "$D_REQUESTED")
export PRACTICE_DOMICILE_REQUESTED="$D_REQUESTED" PRACTICE_DOMICILE_BINARY="$D"
OUT=$(realpath -m -- "$1")
[[ ! -e "$OUT" ]] || { echo 'OUTDIR must be new' >&2; exit 2; }
mkdir -p "$OUT"/{home/Documents,config/domicile,cache,state/domicile,data,frames}
ROOT=$(pwd)
K=/nix/store/fp1riv1kn4h0n1zvdan0xd1zk0rx5vxa-kitty-0.48.2/bin
C=/nix/store/3gnf9mp296kf6k3dckvlwjxmgwcaadr1-google-chrome-156.0.8078.47/bin
N=/nix/store/ns08k5ay3dz235mm9g1hahirx72zhyc1-nautilus-50.2.2/bin
export HOME="$OUT/home" XDG_CONFIG_HOME="$OUT/config" XDG_CACHE_HOME="$OUT/cache"
export XDG_DATA_HOME="$OUT/data" XDG_STATE_HOME="$OUT/state"
export XDG_DATA_DIRS="/nix/store/cwaxgdj59phlv6hc6rfqfd7m3hdxvjly-gsettings-desktop-schemas-50.1/share/gsettings-schemas/gsettings-desktop-schemas-50.1:$N/../share"
export PATH="$ROOT/home/dot_local/bin:$K:$C:$N:$PATH" GSK_RENDERER=cairo
unset HERDR_ENV HERDR_CONFIG_PATH HERDR_SOCKET_PATH HERDR_SESSION HERDR_PANE_ID

# Read-only readiness probes are confined to these fixture Kitty sockets in the
# runtime-test namespace. Production launchers enable no remote-control socket.
mkdir -p "$XDG_CONFIG_HOME/kitty"
cat > "$XDG_CONFIG_HOME/kitty/kitty.conf" <<KITTY
allow_remote_control socket-only
listen_on unix:$XDG_RUNTIME_DIR/apps-kitty-{kitty_pid}
KITTY
printf 'Fixture notes only. No personal files.\n' > "$HOME/Documents/fixture-notes.txt"
printf 'A second fixture document.\n' > "$HOME/Documents/fixture-tasks.txt"
cat > "$OUT/browser-fixture.html" <<'HTML'
<!doctype html><meta charset="utf-8"><title>Chrome fixture — Domicile apps</title>
<style>body{font:22px monospace;background:#faf8f5;color:#292524;margin:40px}button{font:inherit;padding:8px 16px;border:1px solid #777;background:#fff}p{line-height:1.5}</style>
<p>Google Chrome on Domicile</p><p>Fixture content only. Private browser profile.</p>
<button onclick="this.textContent='Painted and clicked'">Click fixture</button>
HTML
export OUT ROOT
python3 - <<'PY'
import hashlib,json,os,pathlib
out=pathlib.Path(os.environ["OUT"])
binary=pathlib.Path(os.environ["PRACTICE_DOMICILE_BINARY"])
build={
 "selected_by":"DOMICILE_BIN" if "DOMICILE_BIN" in os.environ else "default",
 "requested_binary":os.environ["PRACTICE_DOMICILE_REQUESTED"],
 "binary":str(binary),
 "package":str(binary.parent.parent) if binary.parent.name == "bin" else None,
 "sha256":hashlib.sha256(binary.read_bytes()).hexdigest(),
}
# Persist identity before starting the desktop, including if the practice fails.
(out/"domicile-build.json").write_text(json.dumps(build,indent=2)+"\n")
(out/"config/domicile/domicile.tsx").write_text('''
import { runManganese } from "@domicile-desktop/manganese";
import { DEFAULT_KEYBINDINGS, exec } from "@domicile-desktop/manganese-window-management/keyboard/commands";
import { ownedChords } from "@domicile-desktop/sdk/own-keybindings";
const { "Meta+Shift+Return": _lock, ...kept } = DEFAULT_KEYBINDINGS;
const keybindings = { ...kept,
  "Meta+Return": exec("domicile-apps", "terminal"),
  "Meta+Shift+Return": exec("domicile-apps", "rescue"),
  "Meta+b": exec("domicile-apps", "chrome", "--no-first-run", "--no-default-browser-check", "--password-store=basic", '''+json.dumps("--user-data-dir="+str(out/"chrome-profile"))+''', '''+json.dumps((out/"browser-fixture.html").as_uri())+'''),
  "Meta+e": exec("domicile-apps", "files", '''+json.dumps(str(out/"home/Documents"))+'''),
};
ownedChords({ keybindings });
export const Shell = runManganese({keybindings:{keybindings}});
''')
(out/"state/domicile/remote-desktop.json").write_text(json.dumps({
 "apps-fixture-token":{"app_id":"drive.apps-fixture","devices":{"keyboard":True,"pointer":False,"touchscreen":False},"clipboard":False}}))
PY
cd "$HOME"
DESK='' FR='' HS=''
down() {
  touch "$OUT/stop-frames"
  if [[ -n "$FR" ]]; then wait "$FR" || true; fi
  if [[ -n "$HS" ]] && kill -0 "$HS" 2>/dev/null; then "$H" server stop > "$OUT/herdr-stop.json"; wait "$HS"; fi
  if [[ -n "$DESK" ]] && kill -0 "$DESK" 2>/dev/null; then kill -TERM "$DESK"; wait "$DESK" || true; fi
}
trap down EXIT

# A real private Herdr server. Fake endpoints below replace NETWORK only; the
# projector, gate, native client, server, UI and shells execute for real.
H=$(command -v herdr)
mkdir -p "$OUT/config/herdr" "$OUT/fake-bin"
cat > "$OUT/config/herdr/config.toml" <<'TOML'
onboarding = false
[terminal]
default_shell = "/run/current-system/sw/bin/fish"
shell_mode = "non_login"
[update]
version_check = false
manifest_check = false
[ui]
prompt_new_workspace_name = true
TOML
cp "$OUT/config/herdr/config.toml" "$OUT/config/herdr/desktop-client.toml"
"$H" server > "$OUT/herdr-server.log" 2>&1 &
HS=$!
for ((i=0;i<100;i++)); do
  [[ -S "$OUT/config/herdr/herdr.sock" ]] && break
  sleep .05
done
"$H" workspace create --cwd "$HOME" --label "Existing fixture" --no-focus > "$OUT/herdr-created.json"
export H
python3 - <<'PY'
import json,os,pathlib
out=pathlib.Path(os.environ["OUT"])
real=os.environ["H"]
(out/"fake-bin/herdr").write_text("#!/usr/bin/env python3\nimport json,os,sys,pathlib\n"
 "assert sys.argv[1:] == ['--remote','nas','--remote-keybindings','server']\n"
 "pathlib.Path("+repr(str(out/"herdr-remote-argv.json"))+").write_text(json.dumps(sys.argv[1:]))\n"
 "os.execv("+repr(real)+", ["+repr(real)+", 'client'])\n")
(out/"fake-bin/ssh").write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> "+str(out/"fake-ssh.log")+"\nexit 0\n")
for name in ("ssh","herdr"): (out/"fake-bin"/name).chmod(0o755)
PY
export PATH="$OUT/fake-bin:$PATH" HERDR_PROJECTOR_SSH="$OUT/fake-bin/ssh"
OZONE=headless "$D" > "$OUT/desktop.log" 2>&1 &
DESK=$!
for ((i=0;i<900;i++)); do
  grep -q 'domicile is up' "$OUT/desktop.log" && break
  kill -0 "$DESK" 2>/dev/null || { cat "$OUT/desktop.log"; exit 1; }
  sleep .1
done
grep -q 'domicile is up' "$OUT/desktop.log"
export DOMICILE_SOCK=$(sed -n 's/^DOMICILE_SOCK=//p' "$OUT/desktop.log" | head -1)
export WAYLAND_DISPLAY=$(sed -n 's/.*display="\(wayland-[0-9]*\)".*/\1/p' "$OUT/desktop.log" | head -1)
for ((i=0;i<120;i++)); do
  shell=$("$D" which-shell 2>/dev/null || true)
  [[ -n "$shell" && "$shell" != *splash* ]] && break
  sleep .5
done
sleep 5
B=org.freedesktop.impl.portal.desktop.domicile
P=/org/freedesktop/portal/desktop
I=org.freedesktop.impl.portal.RemoteDesktop
S=/org/freedesktop/portal/desktop/session/apps_fixture/s1
busctl --user call "$B" "$P" "$I" CreateSession 'oosa{sv}' /r/1 "$S" drive.apps-fixture 0
busctl --user call "$B" "$P" "$I" SelectDevices 'oosa{sv}' /r/2 "$S" drive.apps-fixture 1 restore_data '(suv)' domicile 1 s apps-fixture-token
timeout 20 busctl --user call "$B" "$P" "$I" Start 'oossa{sv}' /r/3 "$S" drive.apps-fixture "" 0
key() { busctl --user call "$B" "$P" "$I" NotifyKeyboardKeycode 'oa{sv}iu' "$S" 0 "$1" "$2" >/dev/null; sleep .08; }
chord() { local i; for i in "$@"; do key "$i" 1; done; for ((i=$#;i>0;i--)); do key "${!i}" 0; done; }
shot() { "$D" screenshot "$OUT/$1.png"; }

CONTROL_SOCKET=''
wait_new_menu() {
  local n socket
  for ((n=0;n<120;n++)); do
    for socket in "$XDG_RUNTIME_DIR"/apps-kitty-*; do
      [[ -S "$socket" && "$socket" != "$CONTROL_SOCKET" ]] || continue
      if timeout 2 "$K/kitty" @ --to "unix:$socket" get-text \
        > "$OUT/$1.txt" 2>> "$OUT/kitty-readiness.log"; then
        if grep -Fq 'local / nas / quit >' "$OUT/$1.txt"; then
          CONTROL_SOCKET="$socket"
          sleep .3
          return 0
        fi
      fi
    done
    sleep .1
  done
  echo 'Fixture terminal menu did not become ready' >&2
  return 1
}
wait_first_key_result() {
  local n
  for ((n=0;n<120;n++)); do
    if timeout 2 "$K/kitty" @ --to "unix:$CONTROL_SOCKET" get-text \
      > "$OUT/local-first-keys.txt" 2>> "$OUT/kitty-readiness.log"; then
      grep -Fq 'No action. Enter local, nas or quit.' "$OUT/local-first-keys.txt" && return 0
    fi
    sleep .1
  done
  echo 'Fixture first keys were not observed in the LOCAL menu' >&2
  return 1
}
(
  n=0
  while [[ ! -e "$OUT/stop-frames" ]]; do
    file=$(printf '%s/frames/frame-%04d.png' "$OUT" "$n")
    timeout 5 "$D" screenshot "$file" >/dev/null 2>>"$OUT/capture.log"
    date --iso-8601=ns >> "$OUT/frame-times.txt"
    n=$((n+1))
    sleep .5
  done
) &
FR=$!
sleep 1
chord 125 28
wait_new_menu local-first-menu
shot 01-local-control
for code in 30 48 46 28; do key "$code" 1; key "$code" 0; done
wait_first_key_result
shot 02-first-keys-local
[[ ! -e "$OUT/fake-ssh.log" && ! -e "$OUT/herdr-remote-argv.json" ]]
chord 125 42 28
sleep 3
shot 03-local-rescue
# "echo local" + Enter in this private fixture's local shell.
for code in 18 46 35 24 57 38 24 46 30 38 28; do key "$code" 1; key "$code" 0; done
sleep 1
shot 04-rescue-executed
chord 125 48
sleep 8
shot 05-chrome
chord 125 18
sleep 6
shot 06-nautilus

# New terminal defaults local. A human's explicit selection is simulated here
# only on private fixture windows. No production launcher generates keystrokes.
chord 125 28
wait_new_menu local-nas-menu
shot 07-local-nas-selection
for code in 49 30 31 28; do key "$code" 1; key "$code" 0; done # nas: the only attach action
sleep 4
shot 08-herdr-existing-fixture
chord 29 48 # native Ctrl+B prefix
chord 42 49 # native Shift+N: new workspace
sleep 2
shot 09-herdr-native-new-prompt
for code in 33 19 18 31 35 28; do key "$code" 1; key "$code" 0; done # fresh
sleep 3
shot 10-herdr-fresh-shell

# Actual ordinary input after the native fresh-workspace selection. Read back
# that explicit pane and the old pane independently; never use API focus/run.
for code in 18 46 35 24 57 33 19 18 31 35 28; do key "$code" 1; key "$code" 0; done # echo fresh
sleep 3
shot 11-herdr-fresh-command
fresh_id=$("$H" pane list | jq -r '.result.panes[] | select(.focused) | .pane_id')
"$H" pane read "$fresh_id" --source recent-unwrapped --lines 20 > "$OUT/herdr-fresh-read.txt"
"$H" pane read w1:p1 --source recent-unwrapped --lines 20 > "$OUT/herdr-old-read.txt"
"$H" workspace list > "$OUT/herdr-after-native-new.json"
"$H" pane list > "$OUT/herdr-pane-destinations.json"

ps -eo pid,ppid,args > "$OUT/processes.txt"
sleep 1
touch "$OUT/stop-frames"
wait "$FR"
FR=''
ffmpeg -nostdin -y -framerate 2 -i "$OUT/frames/frame-%04d.png" -c:v libx264 -pix_fmt yuv420p "$OUT/apps.mp4" > "$OUT/encoding.log" 2>&1
ffprobe -v error -show_entries stream=width,height,nb_frames -show_entries format=duration -of json "$OUT/apps.mp4" > "$OUT/video.json"
python3 - <<'PY'
import hashlib,json,os,pathlib
out=pathlib.Path(os.environ["OUT"])
files=[p for p in sorted(out.iterdir()) if p.suffix in (".png",".mp4")]
fresh=(out/"herdr-fresh-read.txt").read_text()
old=(out/"herdr-old-read.txt").read_text()
assert "echo fresh" in fresh and "\nfresh\n" in fresh
assert "echo fresh" not in old
receipt={"kind":"real Domicile headless and Herdr server/client; fake SSH/remote dispatch; fixture HOME; no NAS connection",
 "domicile":json.loads((out/"domicile-build.json").read_text()),
 "artifacts":{p.name:{"bytes":p.stat().st_size,"sha256":hashlib.sha256(p.read_bytes()).hexdigest()} for p in files},
 "recording":"sampled screenshots at nominal 2 fps; frame-times.txt records actual capture times",
 "projector_policy":{"change":"herdr-projector gained HERDR_PROJECTOR_RECONNECT=0 for one attach attempt",
 "legacy_default":"automatic reconnect remains enabled by default; covered by test_existing_projector_callers_still_reconnect_by_default"},
 "checks":{"ordinary_first_keys_stayed_local":True,"native_fresh_shell_executed_command":True,"old_fixture_pane_did_not_receive_command":True},
 "visual_review":"pending","hardware":"Zenbook untested; no deployment"}
(out/"receipt.json").write_text(json.dumps(receipt,indent=2)+"\n")
PY
echo "$OUT"
