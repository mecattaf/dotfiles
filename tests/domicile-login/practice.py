#!/usr/bin/env python3
"""Headless failure/rescue/exit/re-entry proof. Run under runtime-test + dbus-run-session."""
import argparse
import json
import os
from pathlib import Path
import runpy
import shlex
import subprocess
import sys
import time

from test_lifecycle import ROOT, isolated


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recovery", type=Path, required=True)
    parser.add_argument("--kitty", type=Path, required=True)
    parser.add_argument("--receipts", type=Path, required=True)
    args = parser.parse_args()
    if Path("/proc/1/comm").read_text().strip() != "bwrap":
        sys.exit("Use runtime-test -- dbus-run-session -- python3 tests/domicile-login/practice.py ...")
    if not os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
        sys.exit("A private dbus-run-session bus is required")
    work = args.receipts.resolve()
    work.mkdir(parents=True)
    env = isolated(work)
    env.update(OZONE="headless", RUST_LOG="warn,domicile_compositor=debug")
    # No XDG_VTNR: upstream leaves graphical-session management to the host.
    values = runpy.run_path(str(args.recovery))
    domicile = values["DOMICILE"]
    config = work / "config/domicile/domicile.tsx"
    config.parent.mkdir()
    candidate = (ROOT / "home/dot_config/domicile/domicile.tsx").read_text()
    config.write_text(candidate)
    events = []

    def event(what, **fields):
        entry = dict(event=what, **fields)
        events.append(entry)
        (work / "events.json").write_text(json.dumps(events, indent=2) + "\n")
        print(json.dumps(entry), flush=True)

    def run(argv, name, expected=0):
        result = subprocess.run(list(map(str, argv)), env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=70)
        (work / (name + ".log")).write_text(result.stdout)
        if result.returncode != expected:
            raise RuntimeError(f"{name}: exit {result.returncode}: {result.stdout}")
        return result.stdout

    event("engine-abi", status="UNSUPPORTED",
          note="Cached-engine behavior is not matched-native-engine qualification.")
    desk = monitor = terminal = None
    handles = []

    def start(name):
        nonlocal desk, monitor
        logfile = work / (name + ".log")
        log = logfile.open("w")
        handles.append(log)
        desk = subprocess.Popen([domicile], env=env, stdout=log, stderr=subprocess.STDOUT)
        env["DOMICILE_SOCK"] = str(Path(env["XDG_RUNTIME_DIR"]) / f"domicile-ipc.{desk.pid}.sock")
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            if desk.poll() is not None:
                raise RuntimeError(f"{name}: launcher exited {desk.returncode}; see {logfile}")
            if "domicile is up" in logfile.read_text():
                break
            time.sleep(0.1)
        else:
            raise RuntimeError(f"{name}: desktop never became ready; see {logfile}")
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            which = run([domicile, "which-shell"], name + "-which-shell")
            if "/splash/" not in which:
                break
            time.sleep(0.2)
        else:
            raise RuntimeError("The configured shell never replaced the splash")
        monitor_log = (work / (name + "-monitor.log")).open("w")
        handles.append(monitor_log)
        monitor = subprocess.Popen([domicile, "monitor", "login-practice", "1280x800"],
                                   env=env, stdin=subprocess.PIPE, stdout=monitor_log,
                                   stderr=subprocess.STDOUT)
        time.sleep(3)
        event(name, pid=desk.pid, socket=env["DOMICILE_SOCK"], shell=which.strip())

    def screenshot(name):
        run([domicile, "screenshot", work / (name + ".png")], name + "-screenshot")

    def stop(name):
        run([args.recovery, "exit"], name + "-exit")
        result = desk.wait(timeout=20)
        # release 67c29a99 intentionally reports a caught SIGTERM as exit 1.
        # Require its exact diagnostic, retain the whole log, and report the code.
        if result != 1 or "the desktop exited (interrupted)" not in (work / (
                "first-start.log" if name == "first-stop" else "second-start.log")).read_text():
            raise RuntimeError(f"Unexpected launcher shutdown result {result}")
        if Path(env["DOMICILE_SOCK"]).exists():
            raise RuntimeError("Graceful shutdown left its control socket behind")
        if monitor:
            monitor.stdin.close()
            monitor.wait(timeout=10)
        event(name, launcher_exit=result, reason="intentional SIGTERM interruption", socket_removed=True)

    try:
        run([args.recovery, "check"], "initial-check")
        start("first-start")
        screenshot("01-good-desktop")
        # A local native client gives independent proof that rescue preserves windows.
        counter = work / "window-counter.log"
        terminal_log = (work / "terminal.log").open("w")
        handles.append(terminal_log)
        # The compositor has separate app and chrome sockets. Read the public
        # session record instead of guessing from similarly named log lines.
        session_file = Path(env["XDG_RUNTIME_DIR"]) / f"domicile-{desk.pid}/session.json"
        session = json.loads(session_file.read_text())
        display = session["wayland_display"]
        event("native-app-display", display=display,
              chrome_display=session["chrome_wayland_display"])
        client_env = dict(env, WAYLAND_DISPLAY=display)
        command = ("i=0; while true; do printf '%s\\n' \"$i\" >> "
                   + shlex.quote(str(counter)) + '; i=$((i+1)); sleep 1; done')
        terminal = subprocess.Popen([str(args.kitty), "--title", "Recovery proof",
                                     "--override", "linux_display_server=wayland",
                                     "-e", "sh", "-c", command],
                                    env=client_env, stdout=terminal_log, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline and not counter.exists():
            if terminal.poll() is not None:
                raise RuntimeError("Native proof window exited; see terminal.log")
            time.sleep(0.1)
        if not counter.exists():
            raise RuntimeError("Native proof window did not start")
        time.sleep(2)
        before = counter.read_text().splitlines()[-1]
        screenshot("02-native-window")
        connected = (work / "first-start.log").read_text()
        if (f"app client connected pid={terminal.pid}" not in connected
                or "toplevel drew -> app_appeared" not in connected):
            raise RuntimeError("The native proof window did not connect and map as an app")

        # Reproduce the unguarded semantic failure seen in earlier practice.
        bad = candidate.replace("ownedChords({ keybindings });", "")
        bad = bad.replace("  ...kept,", '  ...kept,\n  "Shift+Meta+Return": exec("false"),')
        config.write_text(bad)
        time.sleep(4)
        screenshot("03-semantic-error")
        event("bad-live-edit", counter=counter.read_text().splitlines()[-1])
        run([args.recovery, "status"], "status")
        run([args.recovery, "rescue"], "rescue")
        time.sleep(4)
        screenshot("04-rescue")
        after = counter.read_text().splitlines()[-1]
        if terminal.poll() is not None or int(after) <= int(before):
            raise RuntimeError("Native window did not survive rescue")
        event("rescue-preserved-native-window", native_pid=terminal.pid,
              counter_before=before, counter_after=after)

        config.write_text(candidate)
        time.sleep(4)
        run([args.recovery, "check"], "fixed-check")
        screenshot("05-fixed")
        event("config-fixed")
        stop("first-stop")
        # A client started by this practice driver is outside upstream's app scopes.
        if terminal.poll() is None:
            terminal.terminate()
        terminal.wait(timeout=10)
        start("second-start")
        screenshot("06-reentered")
        stop("second-stop")
        event("PASS", boundary="headless, private HOME/config/state/runtime/bus; no user manager")
    except BaseException as error:
        event("FAIL", reason=str(error))
        raise
    finally:
        # Only processes created by this driver; no pkill, service stop or reset-failed.
        if desk and desk.poll() is None:
            desk.terminate()
            try:
                desk.wait(timeout=15)
            except subprocess.TimeoutExpired:
                event("cleanup-failure", pid=desk.pid, reason="launcher did not stop after SIGTERM")
        if monitor:
            if monitor.stdin and not monitor.stdin.closed:
                monitor.stdin.close()
            try:
                monitor.wait(timeout=10)
            except subprocess.TimeoutExpired:
                event("cleanup-failure", pid=monitor.pid, reason="monitor did not exit")
        if terminal and terminal.poll() is None:
            terminal.terminate()
            try:
                terminal.wait(timeout=10)
            except subprocess.TimeoutExpired:
                event("cleanup-failure", pid=terminal.pid, reason="native window did not stop")
        for handle in handles:
            handle.close()


if __name__ == "__main__":
    main()
