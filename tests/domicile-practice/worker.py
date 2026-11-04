#!/usr/bin/env python3
"""Isolated, bounded headless Domicile checks. Invoke through run-nas.py."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import time
import traceback

BASE = "/nix/store/sz1pfpfw4wjyxbi6w7ils7nwip8kajy1-domicile/bin/domicile"
KITTY = "/nix/store/fp1riv1kn4h0n1zvdan0xd1zk0rx5vxa-kitty-0.48.2/bin/kitty"
CHROME = "/nix/store/3gnf9mp296kf6k3dckvlwjxmgwcaadr1-google-chrome-156.0.8078.47/bin/google-chrome-stable"
NAUTILUS = "/nix/store/ns08k5ay3dz235mm9g1hahirx72zhyc1-nautilus-50.2.2/bin/nautilus"
RECORDER = "/nix/store/41visbgk83xmxrp0f88bqvx34khv66al-wf-recorder-0.6.0/bin/wf-recorder"
B = "org.freedesktop.impl.portal.desktop.domicile"
P = "/org/freedesktop/portal/desktop"
I = "org.freedesktop.impl.portal.RemoteDesktop"
S = P + "/session/practice/s1"


def digest(path):
    with Path(path).open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def atomic(path, value):
    path = Path(path)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(value, indent=2) + "\n")
    tmp.replace(path)


def processes():
    result = {}
    for path in Path("/proc").glob("[0-9]*/stat"):
        try:
            raw = path.read_text()
            fields = raw[raw.rfind(")") + 2:].split()
            pid = int(path.parent.name)
            argv = (path.parent / "cmdline").read_bytes().decode(errors="replace").split("\0")[:-1]
            # Some Nix launchers rewrite Chromium argv into a single process title.
            if len(argv) == 1 and " --" in argv[0]:
                argv = shlex.split(argv[0])
            result[pid] = {"pid": pid, "ppid": int(fields[1]), "state": fields[0],
                           "start": int(fields[19]), "argv": argv}
        except (OSError, ValueError, IndexError):
            pass
    return result


def living(identity):
    now = processes().get(identity["pid"])
    return now and now["start"] == identity["start"] and now["state"] != "Z"


def descendants(table, roots):
    owned = set(roots)
    while True:
        new = {pid for pid, row in table.items() if row["ppid"] in owned}
        if new <= owned:
            return {pid: table[pid] for pid in owned if pid in table}
        owned |= new


def send_owned(identity, sig):
    # The caller can only supply an identity collected from its own child tree.
    if not living(identity):
        return
    fd = os.pidfd_open(identity["pid"])
    try:
        if living(identity):
            signal.pidfd_send_signal(fd, sig)
    finally:
        os.close(fd)


def until(predicate, timeout, interval=0.25):
    end = time.monotonic() + timeout
    while True:
        value = predicate()
        if value:
            return value
        if time.monotonic() >= end:
            return None
        time.sleep(min(interval, max(0, end - time.monotonic())))


class Harness:
    def __init__(self, a):
        self.a = a
        self.work = a.output.resolve()
        self.source = Path(__file__).resolve().parent
        self.env = {}
        self.children = []
        self.owned = {}
        self.serial = 0
        self.desk = None
        self.log = None
        self.capture_active = False
        self.session_no = 0
        self.recording_supported = False
        self.recorders = []
        self.receipt = {"schema": 1, "result": "running", "started": time.time(),
                        "backend": "OZONE=headless; CPU; no GPU passthrough",
                        "checks": [], "capabilities": {}, "boundaries": [
                            "No physical greetd/PAM/VT, Intel panels, libinput or real keyboard proof.",
                            "Key input uses the private RemoteDesktop portal backend, not libei.",
                            "No activation, live service calls, credentials or Herdr attachment.",
                            "Frame sequences are explicitly not live recordings.",
                            "The generated key table is a fixture, not an integrated branch acceptance."],
                        "files": {}, "intentional_faults": []}

    def event(self, kind, **data):
        with (self.work / "events.jsonl").open("a") as f:
            f.write(json.dumps({"time": time.time(), "monotonic": time.monotonic(),
                                "kind": kind, **data}) + "\n")

    def save(self):
        atomic(self.work / "receipt.json", self.receipt)

    @contextmanager
    def check(self, name):
        row = {"name": name, "started": time.time(), "status": "running"}
        self.receipt["checks"].append(row)
        self.save()
        self.event("check-start", name=name)
        try:
            yield row
        except Exception as e:
            row.update(status="fail", reason=str(e), traceback=traceback.format_exc())
            self.event("check-fail", name=name, reason=str(e))
        else:
            row["status"] = "pass"
            self.event("check-pass", name=name)
        finally:
            row["duration_s"] = round(time.time() - row["started"], 3)
            self.save()
            print(json.dumps(row), flush=True)

    def command(self, argv, timeout=10):
        self.serial += 1
        log = self.work / "raw" / (str(self.serial).zfill(4) + ".log")
        self.event("command", argv=list(map(str, argv)), log=str(log.relative_to(self.work)))
        started = time.monotonic()
        # Log to disk directly: no pipe can deadlock if a failed child talks a lot.
        with log.open("wb") as out:
            proc = subprocess.Popen(list(map(str, argv)), env=self.env, cwd=self.work,
                                    stdout=out, stderr=subprocess.STDOUT)
            try:
                rc = proc.wait(timeout)
            except subprocess.TimeoutExpired:
                identity = processes().get(proc.pid)
                self.event("command-timeout", pid=proc.pid, argv=list(map(str, argv)))
                if identity:
                    send_owned(identity, signal.SIGTERM)
                try:
                    rc = proc.wait(2)
                except subprocess.TimeoutExpired:
                    if identity:
                        send_owned(identity, signal.SIGKILL)
                    rc = proc.wait(2)
                return 124, log.read_text(errors="replace")
        self.event("command-end", rc=rc, duration_s=time.monotonic() - started)
        return rc, log.read_text(errors="replace")

    def spawn(self, argv, name):
        log = (self.work / "raw" / (name + ".log")).open("wb")
        proc = subprocess.Popen(list(map(str, argv)), env=self.env, cwd=self.work,
                                stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT)
        log.close()
        self.children.append(proc)
        self.event("spawn", argv=list(map(str, argv)), pid=proc.pid, log=name)
        return proc

    def observe(self, name=None):
        table = processes()
        # Remember each identity while still parented; only those exact identities
        # may later be cleaned up if an application is reparented on shutdown.
        roots = [p.pid for p in self.children if p.poll() is None]
        tree = descendants(table, roots)
        for pid, row in tree.items():
            self.owned[(pid, row["start"])] = row
        if name:
            atomic(self.work / (name + "-processes.json"), list(tree.values()))
        return tree

    def setup(self):
        host = json.loads((self.work / "isolation-expectations.json").read_text())
        runtime = Path(os.environ["XDG_RUNTIME_DIR"])
        actual = {k: os.readlink("/proc/self/ns/" + k) for k in ("pid", "ipc")}
        runtime_stat = runtime.stat()
        actual["runtime_devino"] = [runtime_stat.st_dev, runtime_stat.st_ino]
        assert actual["pid"] != host["pid"], "refusing live PID namespace"
        assert actual["ipc"] != host["ipc"], "refusing live IPC namespace"
        assert actual["runtime_devino"] != host["runtime_devino"], "refusing live runtime directory"
        assert not (runtime / "systemd/private").exists(), "live user manager visible"
        for name in ("home/Documents", "home/.local/bin", "config/domicile", "cache", "data",
                     "state/domicile", "raw", "shots", "media"):
            (self.work / name).mkdir(parents=True, exist_ok=True)
        # Deliberate allowlist: no token, SSH, Herdr, session-manager or agent env.
        paths = [str(self.work / "home/.local/bin")]
        paths += [str(Path(x).parent) for x in (self.a.kitty, self.a.chrome, self.a.nautilus)]
        paths += ["/run/current-system/sw/bin", "/etc/profiles/per-user/tom/bin", "/usr/bin", "/bin"]
        self.env = {"PATH": ":".join(paths), "HOME": str(self.work / "home"),
                    "XDG_CONFIG_HOME": str(self.work / "config"),
                    "XDG_CACHE_HOME": str(self.work / "cache"),
                    "XDG_DATA_HOME": str(self.work / "data"),
                    "XDG_STATE_HOME": str(self.work / "state"), "XDG_RUNTIME_DIR": str(runtime),
                    "XDG_DATA_DIRS": "/run/current-system/sw/share:/etc/profiles/per-user/tom/share",
                    "LANG": "C.UTF-8", "OZONE": "headless", "GSK_RENDERER": "cairo",
                    "RUST_LOG": "warn,domicile_compositor=debug", "PRACTICE_WORK": str(self.work),
                    "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(runtime / "practice-bus")}
        atomic(self.work / "isolation-observed.json", actual)
        self.receipt["isolation"] = actual
        self.receipt["core_policy"] = {"limits": resource.getrlimit(resource.RLIMIT_CORE),
                                       "pattern": Path("/proc/sys/kernel/core_pattern").read_text().strip(),
                                       "note": "Unchanged; system coredumps remain in the host journal/store."}
        for key in ("domicile", "kitty", "chrome", "nautilus"):
            value = Path(getattr(self.a, key)).resolve()
            assert value.is_file() and os.access(value, os.X_OK), str(value)
            self.receipt["files"][key] = {"path": str(value), "sha256": digest(value)}
        settings = {"kitty": self.a.kitty, "chrome": self.a.chrome, "nautilus": self.a.nautilus,
                    "commands": {}}
        if self.a.commands:
            settings["commands"] = json.loads(Path(self.a.commands).read_text())
            assert all(k in ("terminal", "rescue", "browser", "files") and isinstance(v, list)
                       and v and all(isinstance(s, str) for s in v)
                       for k, v in settings["commands"].items()), "commands must be argv arrays"
        self.command_overrides = settings["commands"]
        atomic(self.work / "settings.json", settings)
        for name in ("notes.txt", "budget.txt", "todo.txt"):
            (self.work / "home/Documents" / name).write_text("Disposable Domicile practice.\n")
        helper = self.work / "home/.local/bin/domicile-apps"
        if self.a.apps_helper:
            shutil.copyfile(self.a.apps_helper, helper)
            self.receipt["files"]["apps_helper"] = {"path": self.a.apps_helper, "sha256": digest(helper)}
        else:
            # A tiny exec bridge gives supplied configs the same public helper seam.
            helper.write_text("#!/bin/sh\nexec " + shlex.quote(str(Path(sys.executable).resolve())) + " "
                              + shlex.quote(str(self.source / "practice-app.py")) + ' "$@"\n')
        helper.chmod(0o700)
        shutil.copyfile(helper, self.work / "tested-apps-helper")
        # Relative ~/ launch paths cannot accidentally attach to a real workspace.
        for name in ("herdr", "herdr-sway-projector", "herdr-picker", "ssh"):
            trap = self.work / "home/.local/bin" / name
            trap.write_text('#!/bin/sh\necho "practice: live transport is forbidden" >&2\nexit 77\n')
            trap.chmod(0o700)
        self.config = self.work / "config/domicile/domicile.tsx"
        if self.a.config:
            original = Path(self.a.config).resolve()
            self.config = original
            shutil.copyfile(original, self.work / "supplied-config.tsx")
        else:
            actions = {"Meta+Return": "terminal", "Meta+Shift+Return": "rescue",
                       "Meta+b": "browser", "Meta+e": "files"}
            lines = ['import { runManganese } from "@domicile-desktop/manganese";',
                     'import { DEFAULT_KEYBINDINGS, exec } from "@domicile-desktop/manganese-window-management/keyboard/commands";',
                     'import { ownedChords } from "@domicile-desktop/sdk/own-keybindings";',
                     'const { "Meta+Shift+Return": _lock, ...kept } = DEFAULT_KEYBINDINGS;',
                     'const keybindings = { ...kept,']
            lines += [json.dumps(k) + ': exec("domicile-apps", ' + json.dumps(v) + '),' for k, v in actions.items()]
            lines += ['};', 'ownedChords({ keybindings });',
                      'export const Shell = runManganese({ keybindings: { keybindings } });']
            self.config.write_text("\n".join(lines) + "\n")
        shutil.copyfile(self.config, self.work / "tested-config.tsx")
        self.receipt["files"]["config"] = {"path": str(self.config), "sha256": digest(self.config),
                                            "fixture": not bool(self.a.config)}
        if self.a.config:
            self.receipt["boundaries"][-1] = "Supplied config checked with the supplied chord plan and disposable app commands."
        self.expectations = {}
        if self.a.expectations:
            self.expectations = json.loads(Path(self.a.expectations).read_text())
            assert all(k in ("terminal", "rescue", "browser", "files") and isinstance(v, list)
                       and v and all(isinstance(s, str) for s in v)
                       for k, v in self.expectations.items()), "expectations must be substring arrays"
        atomic(self.work / "expectations.json", self.expectations)
        self.chords = {"terminal": [125, 28], "rescue": [125, 42, 28],
                       "browser": [125, 48], "files": [125, 18]}
        if self.a.chords:
            self.chords.update(json.loads(Path(self.a.chords).read_text()))
        atomic(self.work / "chords.json", self.chords)
        bus_config = self.work / "private-bus.conf"
        bus_config.write_text('<busconfig><type>session</type><auth>EXTERNAL</auth><listen>'
                              + self.env["DBUS_SESSION_BUS_ADDRESS"] + '</listen>'
                              + '<policy context="default"><allow send_destination="*"/>'
                              + '<allow receive_sender="*"/><allow own="*"/></policy></busconfig>')
        self.spawn(["dbus-daemon", "--nofork", "--nopidfile", "--config-file=" + str(bus_config)], "private-bus")
        assert until(lambda: (runtime / "practice-bus").is_socket(), 5), "private bus did not start"
        self.save()

    def start(self, name):
        self.desktop_name = name
        token = {"practice-token": {"app_id": "practice.headless", "devices": {
            "keyboard": True, "pointer": False, "touchscreen": False}, "clipboard": False}}
        atomic(self.work / "state/domicile/remote-desktop.json", token)
        self.env.pop("DOMICILE_SOCK", None)
        self.env.pop("WAYLAND_DISPLAY", None)
        self.desk = self.spawn([self.a.domicile, "--config", self.config], name)
        self.log = self.work / "raw" / (name + ".log")
        began = time.monotonic()
        def ready():
            self.observe()
            text = self.log.read_text(errors="replace")
            if self.desk.poll() is not None:
                raise AssertionError("Domicile exited " + str(self.desk.returncode) + "; see " + str(self.log))
            sock = re.search(r"^DOMICILE_SOCK=(.+)$", text, re.M)
            display = re.search(r'display="(wayland-[0-9]+)"', text)
            if sock:
                self.env["DOMICILE_SOCK"] = sock[1]
            if display:
                self.env["WAYLAND_DISPLAY"] = display[1]
            return "domicile is up" in text and sock and display
        assert until(ready, self.a.startup_timeout, 0.5), "startup timeout"
        def shell():
            rc, text = self.command([self.a.domicile, "which-shell"], 4)
            return text.strip() if rc == 0 and text.strip() and "splash" not in text else None
        shell_path = until(shell, self.a.startup_timeout, 1)
        assert shell_path, "shell build timed out"
        # which-shell identifies the loaded shell, not renderer readiness. Let it
        # paint before the bounded screenshot + real action checks below.
        time.sleep(self.a.settle)
        self.event("desktop-ready", duration_s=time.monotonic() - began, shell=shell_path)
        return {"ready_s": round(time.monotonic() - began, 3), "shell": shell_path,
                "pid": self.desk.pid}

    def bus(self, method, signature, *args):
        rc, text = self.command(["busctl", "--address=" + self.env["DBUS_SESSION_BUS_ADDRESS"],
                                 "call", B, P, I, method, signature, *map(str, args)], 20)
        assert rc == 0, method + ": " + text
        return text

    def session(self):
        self.session_no += 1
        self.session_path = S + str(self.session_no)
        self.bus("CreateSession", "oosa{sv}", "/r/1", self.session_path, "practice.headless", 0)
        self.bus("SelectDevices", "oosa{sv}", "/r/2", self.session_path, "practice.headless", 1,
                 "restore_data", "(suv)", "domicile", 1, "s", "practice-token")
        text = self.bus("Start", "oossa{sv}", "/r/3", self.session_path, "practice.headless", "", 0)
        assert text.startswith("ua{sv} 0"), "portal refused private seed: " + text

    def chord(self, keys):
        pressed = []
        try:
            for key in keys:
                self.bus("NotifyKeyboardKeycode", "oa{sv}iu", self.session_path, 0, key, 1)
                pressed.append(key)
                time.sleep(0.06)
        finally:
            for key in reversed(pressed):
                self.bus("NotifyKeyboardKeycode", "oa{sv}iu", self.session_path, 0, key, 0)
                time.sleep(0.06)

    def shot(self, name):
        assert not self.capture_active, "concurrent capture forbidden"
        path = self.work / "shots" / (name + ".png")
        self.capture_active = True
        try:
            rc, text = self.command([self.a.domicile, "screenshot", path], 6)
            assert rc == 0 and path.exists(), "screenshot failed: " + text
            assert path.read_bytes()[:8] == b"\x89PNG\r\n\x1a\n", "invalid PNG"
            self.event("screenshot", path=str(path.relative_to(self.work)))
        finally:
            self.capture_active = False
        return path

    def require_quiet_capture(self):
        assert not self.capture_active, "screenshot still active; refuse crash load"
        assert all(p.poll() is not None for p in self.recorders), "recorder still active; refuse crash load"

    def engine(self):
        rows = self.observe()
        candidates = [r for r in rows.values() if any(a.startswith("--domicile-broker-socket") for a in r["argv"])
                      and not any(a.startswith("--type=") for a in r["argv"]) and r["state"] != "Z"]
        assert len(candidates) == 1, "expected one owned engine: " + repr(candidates)
        return candidates[0]

    def app_rows(self, action):
        rows = self.observe()
        def match(row):
            args = row["argv"]
            if not args or row["state"] == "Z":
                return False
            if action in self.expectations:
                values = [v.format(work=str(self.work), home=str(self.work / "home"))
                          for v in self.expectations[action]]
                return all(v in "\0".join(args) for v in values)
            if action in ("terminal", "rescue"):
                return "practice-" + action in args and any("kitty" in s for s in args[:2])
            if action == "browser":
                return ("--user-data-dir=" + str(self.work / "chrome")) in args and "about:blank" in args
            return any("nautilus" in s for s in args[:2]) and str(self.work / "home/Documents") in args
        return [r for r in rows.values() if match(r)]

    def counter(self):
        path = self.work / "counter.jsonl"
        if not path.exists():
            return []
        return [json.loads(x) for x in path.read_text().splitlines() if x]

    def probe_recorder(self):
        capability = {"backend": "wf-recorder (wlr-screencopy)", "status": "unavailable"}
        self.receipt["capabilities"]["live_recording"] = capability
        if not Path(self.a.recorder).is_file():
            capability["reason"] = "recorder executable absent"
            return
        path = self.work / "media/live-probe.mkv"
        proc = self.spawn([self.a.recorder, "--no-damage", "-f", path], "live-probe")
        self.recorders.append(proc)
        self.capture_active = True
        try:
            time.sleep(3)
            identity = self.observe().get(proc.pid)
            if proc.poll() is None and identity:
                send_owned(identity, signal.SIGINT)
            try:
                rc = proc.wait(4)
            except subprocess.TimeoutExpired:
                if identity:
                    send_owned(identity, signal.SIGTERM)
                try:
                    rc = proc.wait(3)
                except subprocess.TimeoutExpired:
                    self.event("recorder-probe-wedged", pid=proc.pid, cleanup="SIGKILL after INT/TERM deadlines")
                    if identity:
                        send_owned(identity, signal.SIGKILL)
                    rc = proc.wait(2)
            probe_rc, text = self.command(["ffprobe", "-v", "error", "-count_frames", "-show_streams",
                                           "-show_format", "-of", "json", path], 8)
            capability.update(exit=rc, probe_exit=probe_rc, probe_log=text)
            if probe_rc == 0:
                info = json.loads(text)
                frames = max([int(s.get("nb_read_frames", "0")) for s in info["streams"]] or [0])
                seconds = float(info.get("format", {}).get("duration", 0))
                self.recording_supported = rc == 0 and frames >= 10 and seconds >= 1
            capability["status"] = "supported" if self.recording_supported else "unsupported-on-tested-backend"
            if not self.recording_supported:
                capability["reason"] = "A failed, zero/one-frame or too-short take is not a live recording. Raw attempt retained."
        finally:
            self.capture_active = False
            self.save()

    def feature(self, name, action):
        # Strictly bounded capture. No threads, no polling loop, and never run
        # this while killing/rejoining the engine.
        rec = None
        if self.recording_supported:
            rec = self.spawn([self.a.recorder, "--no-damage", "-f", self.work / "media" / (name + "-live.mkv")], name + "-recorder")
            self.recorders.append(rec)
        shots = []
        stamps = []
        try:
            shots.append(self.shot(name + "-before")); stamps.append(time.monotonic())
            result = action()
            for i in range(2):
                time.sleep(1)
                shots.append(self.shot(name + "-after-" + str(i))); stamps.append(time.monotonic())
        finally:
            if rec:
                row = self.observe().get(rec.pid)
                if row and rec.poll() is None:
                    send_owned(row, signal.SIGINT)
                try:
                    rec.wait(5)
                except subprocess.TimeoutExpired:
                    if row:
                        send_owned(row, signal.SIGKILL)
                    rec.wait(2)
                    raise AssertionError("feature recorder failed to stop; failed take retained")
                rc, probe = self.command(["ffprobe", "-v", "error", "-count_frames", "-show_streams",
                                          "-show_format", "-of", "json",
                                          self.work / "media" / (name + "-live.mkv")], 8)
                info = json.loads(probe) if rc == 0 else {}
                valid = rec.returncode == 0 and rc == 0 and any(int(s.get("nb_read_frames", "0")) >= 10 for s in info.get("streams", []))
                atomic(self.work / "media" / (name + "-live.json"), {"kind": "live-recording",
                       "valid": valid, "recorder_exit": rec.returncode, "probe_exit": rc, "probe": info})
                assert valid, "invalid feature live recording; raw failed take retained"
        if len(shots) >= 2:
            listing = self.work / "media" / (name + ".concat")
            # Absolute scratch paths use only orchestrator-generated safe names.
            text = ""
            for i, path in enumerate(shots):
                text += "file '" + str(path) + "'\n"
                text += "duration " + str(stamps[i+1] - stamps[i] if i+1 < len(stamps) else 1) + "\n"
            text += "file '" + str(shots[-1]) + "'\n"
            listing.write_text(text)
            rc, log = self.command(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "concat",
                                    "-safe", "0", "-i", listing, "-vf", "fps=10,scale=960:-2,format=yuv420p",
                                    "-c:v", "libvpx-vp9", "-cpu-used", "6", "-threads", "2", "-an",
                                    self.work / "media" / (name + "-frame-sequence.webm")], 30)
            assert rc == 0, "frame sequence encoding failed: " + log
            atomic(self.work / "media" / (name + ".json"), {"kind": "timed-frame-sequence-not-live",
                   "captures": len(shots), "offsets_s": [round(t - stamps[0], 3) for t in stamps]})
        return result

    def launch(self, action):
        before = {r["pid"] for r in self.app_rows(action)}
        self.chord(self.chords[action])
        rows = until(lambda: [r for r in self.app_rows(action) if r["pid"] not in before], 15)
        assert rows, "no new owned " + action + " process; inspect application logs/launches"
        if action in ("terminal", "rescue") and not self.a.apps_helper and action not in self.command_overrides:
            def ticking():
                tree = descendants(processes(), [r["pid"] for r in rows])
                return any(c["pid"] in tree and c["time"] > time.time() - 3 for c in self.counter())
            assert until(ticking, 5), "new Kitty's own child is not ticking"
        self.observe(action)
        return {"pids": [r["pid"] for r in rows], "argv": rows[0]["argv"]}

    def shutdown(self, receipt_row):
        self.observe(self.desktop_name + "-shutdown-before")
        before = descendants(processes(), [self.desk.pid])
        identity = before[self.desk.pid]
        self.event("intentional-shutdown", pid=self.desk.pid, signal="SIGTERM")
        send_owned(identity, signal.SIGTERM)
        rc = self.desk.wait(12)
        # The CLI treats interruption as status 1 by design (supervise.rs).
        assert rc in (0, 1), "unexpected shutdown status " + str(rc)
        remaining = until(lambda: not [r for pid, r in before.items() if pid != self.desk.pid and living(r)], 8)
        leftovers = [r for pid, r in before.items() if pid != self.desk.pid and living(r)]
        atomic(self.work / (self.desktop_name + "-shutdown-leftovers.json"), leftovers)
        receipt_row.update(exit=rc, leftover_processes=leftovers)
        self.event("shutdown-observed", desktop=self.desktop_name, exit=rc, leftovers=leftovers)
        assert remaining, "owned desktop descendants survived shutdown; evidence preserved"
        return {"exit": rc, "remaining": len(leftovers), "note": "SIGTERM status 1 is the CLI's intentional interruption result"}

    def run(self):
        with self.check("isolation-and-inputs") as row:
            self.setup()
            row["namespaces"] = self.receipt["isolation"]
        if self.receipt["checks"][0]["status"] != "pass":
            return
        with self.check("broken-startup-actionable") as row:
            broken = self.work / "broken-startup.tsx"
            broken.write_text('export const Shell = runManganese({ keybindings: {\n')
            proc = self.spawn([self.a.domicile, "--config", broken], "broken-startup")
            rc = proc.wait(30)
            text = (self.work / "raw/broken-startup.log").read_text(errors="replace")
            assert rc > 0, "broken startup did not exit nonzero"
            assert "did not build" in text and re.search(r"expected|error|failed", text, re.I), "no actionable config diagnostic"
            assert "domicile is up" not in text, "broken config started a desktop"
            row.update(exit=rc, diagnostic=text[-1800:], diagnostic_names_file="broken-startup.tsx" in text,
                       limit="CLI gives a syntax reason but this baseline omits the config filename.")
        with self.check("clean-startup") as row:
            row.update(self.start("desktop-first"))
            self.session()
            row["screenshot"] = str(self.shot("startup").relative_to(self.work))
        if not self.desk or self.desk.poll() is not None or "DOMICILE_SOCK" not in self.env:
            return
        self.probe_recorder()
        for action in ("terminal", "rescue", "browser", "files"):
            name = "disabled-lock-chord-rescue-kitty" if action == "rescue" else "launch-" + action
            with self.check(name) as row:
                row.update(self.feature(action, lambda: self.launch(action)))
                if action == "rescue":
                    row["limit"] = "Former stock lock chord executes rescue Kitty; no PAM/physical lock claim."
        with self.check("engine-crash-recovery") as row:
            assert all(self.app_rows(a) for a in ("terminal", "rescue", "browser", "files")), "need every real app first"
            # One before, then a quiet log/process-only recovery window. No
            # screenshot command or recorder may overlap the intentional crash.
            self.shot("crash-before")
            time.sleep(1)
            self.require_quiet_capture()
            before_apps = {a: self.app_rows(a) for a in ("terminal", "rescue", "browser", "files")}
            if not self.counter():
                # A supplied helper may open an ordinary shell. Add a separate
                # disposable counter witness without invoking any live transport.
                witness = self.spawn([self.a.kitty, "--title", "practice-heartbeat", "--config", "NONE", "--",
                                      sys.executable, self.source / "practice-app.py", "counter"], "heartbeat")
                assert until(lambda: self.counter(), 8), "counter witness failed"
                row["separate_counter_witness_pid"] = witness.pid
            before_counter = len(self.counter())
            engine = self.engine()
            self.observe("crash-before")
            start_log = len(self.log.read_bytes())
            started = time.monotonic()
            fault = {"pid": engine["pid"], "start": engine["start"], "argv": engine["argv"],
                     "signal": "SIGKILL", "reason": "engine recovery experiment; no core expected from SIGKILL"}
            self.receipt["intentional_faults"].append(fault)
            self.save()
            self.event("intentional-engine-crash", **fault)
            send_owned(engine, signal.SIGKILL)
            def rejoined():
                self.observe()
                if self.desk.poll() is not None:
                    raise AssertionError("desktop launcher exited during recovery")
                log = self.log.read_bytes()[start_log:].decode(errors="replace")
                return "rejoined the engine" in log
            assert until(rejoined, self.a.recovery_timeout, 0.1), "engine did not rejoin; NO screenshot retry/load applied"
            row["rejoin_s"] = round(time.monotonic() - started, 3)
            time.sleep(3)
            new = self.engine()
            assert new["pid"] != engine["pid"] or new["start"] != engine["start"]
            for action, rows in before_apps.items():
                assert all(living(r) for r in rows), action + " process lost during crash"
            assert len(self.counter()) > before_counter + 1, "terminal counter stopped"
            row["old_engine_pid"] = engine["pid"]
            row["new_engine_pid"] = new["pid"]
            row["surviving_app_pids"] = {k: [r["pid"] for r in v] for k, v in before_apps.items()}
            # Only now verify rendering and keys. A failed capture stays a failure.
            self.shot("crash-after-rejoin")
            row["keys_after_rejoin"] = self.launch("rescue")
            self.shot("crash-after-rescue")
            self.observe("crash-after")
        with self.check("clean-shutdown") as row:
            row.update(self.shutdown(row))
        # Reentry uses the same private HOME/config/cache; it must not attach to
        # stale sockets or resurrect the first desk's apps.
        if self.desk.poll() is not None:
            with self.check("re-entry") as row:
                row.update(self.start("desktop-second"))
                self.session()
                row["rescue"] = self.launch("rescue")
                self.shot("reentry-rescue")
            with self.check("second-shutdown") as row:
                row.update(self.shutdown(row))

    def finish(self):
        self.observe("final-before-cleanup")
        alive = [r for r in self.owned.values() if living(r)]
        # Bus, any leaked owned applications, failed probe or timed-out startup.
        # No process-name kill and no signals to a PID found outside this tree.
        for sig in (signal.SIGTERM, signal.SIGKILL):
            for row in reversed(alive):
                try:
                    send_owned(row, sig)
                except ProcessLookupError:
                    pass
            until(lambda: not any(living(r) for r in alive), 3)
        for proc in self.children:
            try:
                proc.wait(1)
            except subprocess.TimeoutExpired:
                pass
        atomic(self.work / "cleanup.json", {"owned_before": alive,
               "remaining": [r for r in alive if living(r)]})
        self.receipt["cleanup_remaining"] = [r for r in alive if living(r)]
        failed = bool(self.receipt["cleanup_remaining"]) or any(r["status"] != "pass" for r in self.receipt["checks"])
        expected = {"isolation-and-inputs", "broken-startup-actionable", "clean-startup", "launch-terminal",
                    "disabled-lock-chord-rescue-kitty", "launch-browser", "launch-files", "engine-crash-recovery",
                    "clean-shutdown", "re-entry", "second-shutdown"}
        completed = {r["name"] for r in self.receipt["checks"]}
        self.receipt["missing_checks"] = sorted(expected - completed)
        self.receipt["result"] = "fail" if failed or expected - completed else "pass"
        self.receipt["ended"] = time.time()
        self.receipt["duration_s"] = round(self.receipt["ended"] - self.receipt["started"], 3)
        self.save()
        lines = ["Domicile isolated headless practice: " + self.receipt["result"], ""]
        lines += [r["status"].upper() + " " + r["name"] + " (" + str(r.get("duration_s")) + "s)" for r in self.receipt["checks"]]
        lines += ["", "Live recording: " + self.receipt["capabilities"].get("live_recording", {}).get("status", "not probed"),
                  "*-frame-sequence.webm files are timed screenshots, NOT live recordings.", ""]
        lines += self.receipt["boundaries"]
        (self.work / "SUMMARY.txt").write_text("\n".join(lines) + "\n")
        inventory = {}
        # Keep minidumps even though bulk disposable profiles are not archived.
        for folder in ("state", "home", "chrome"):
            for path in (self.work / folder).rglob("*.dmp"):
                target = self.work / "crash-evidence" / path.relative_to(self.work)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
        for folder in ("raw", "shots", "media", "source", "crash-evidence"):
            for path in (self.work / folder).rglob("*"):
                if path.is_file():
                    inventory[str(path.relative_to(self.work))] = {"size": path.stat().st_size, "sha256": digest(path)}
        atomic(self.work / "manifest.json", inventory)
        print("\n".join(lines), flush=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    entry = p.add_mutually_exclusive_group(required=True)
    entry.add_argument("--enter", action="store_true", help="capture host identity then use runtime-test")
    entry.add_argument("--inside", action="store_true", help=argparse.SUPPRESS)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--domicile", default=BASE)
    p.add_argument("--config", help="trusted absolute module path (read only); omit for safe fixture")
    p.add_argument("--apps-helper", help="trusted domicile-apps script copied to fake ~/.local/bin")
    p.add_argument("--commands", help="JSON action -> disposable argv override for fixture launcher")
    p.add_argument("--expectations", help="JSON action -> argv substrings; {work}/{home} placeholders")
    p.add_argument("--chords", help="JSON action -> evdev keycode list override")
    p.add_argument("--kitty", default=KITTY)
    p.add_argument("--chrome", default=CHROME)
    p.add_argument("--nautilus", default=NAUTILUS)
    p.add_argument("--recorder", default=RECORDER)
    p.add_argument("--startup-timeout", type=float, default=120)
    p.add_argument("--recovery-timeout", type=float, default=30)
    p.add_argument("--settle", type=float, default=6)
    a = p.parse_args()
    if a.enter:
        assert socket.gethostname() == "strix-coordinator", "compute host must be strix-coordinator"
        wrapper = Path.home() / ".local/bin/runtime-test"
        assert wrapper.is_file() and shutil.which("bwrap"), "runtime-test and bubblewrap required; no fallback"
        a.output = a.output.resolve()
        a.output.mkdir(parents=True, exist_ok=False)
        Path(a.output / "raw").mkdir()
        expectations = {k: os.readlink("/proc/self/ns/" + k) for k in ("pid", "ipc")}
        stat = Path("/run/user/" + str(os.getuid())).stat()
        expectations["runtime_devino"] = [stat.st_dev, stat.st_ino]
        atomic(a.output / "isolation-expectations.json", expectations)
        source = a.output / "source"
        source.mkdir()
        for path in Path(__file__).resolve().parent.iterdir():
            if path.is_file():
                shutil.copyfile(path, source / path.name)
        provenance = {"hostname": socket.gethostname(), "started": time.time(),
                      "argv": sys.argv, "wrapper_sha256": digest(wrapper)}
        for label, cmd in (("head", ["git", "rev-parse", "HEAD"]),
                           ("status", ["git", "status", "--short"]),
                           ("disk", ["df", "-h", "/"])):
            provenance[label] = subprocess.check_output(cmd, text=True)
        atomic(a.output / "provenance.json", provenance)
        cmd = [str(wrapper), "--", sys.executable, str(source / "worker.py")]
        cmd += ["--inside" if arg == "--enter" else arg for arg in sys.argv[1:]]
        raise SystemExit(subprocess.call(cmd))
    harness = Harness(a)
    try:
        harness.run()
    except BaseException:
        (a.output / "unexpected-error.txt").write_text(traceback.format_exc())
        harness.receipt["checks"].append({"name": "unexpected-harness-error", "status": "fail", "traceback": traceback.format_exc()})
    finally:
        harness.finish()
    raise SystemExit(0 if harness.receipt["result"] == "pass" else 1)


if __name__ == "__main__":
    main()
