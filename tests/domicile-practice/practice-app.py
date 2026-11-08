#!/usr/bin/env python3
"""Fixture applications only. No NAS, Herdr, SSH or account profiles."""
import json
import os
from pathlib import Path
import sys
import time

if sys.argv[1] == "counter":
    path = Path(os.environ["PRACTICE_WORK"]) / "counter.jsonl"
    n = 0
    while True:
        line = json.dumps({"pid": os.getpid(), "n": n, "time": time.time()})
        with path.open("a") as f:
            f.write(line + "\n")
        print("DOMICILE PRACTICE", n, flush=True)
        n += 1
        time.sleep(0.5)

work = Path(os.environ["PRACTICE_WORK"])
settings = json.loads((work / "settings.json").read_text())
action = sys.argv[1]
commands = settings["commands"]
argv = commands.get(action)
if argv is None:
    if action in ("terminal", "rescue"):
        argv = [settings["kitty"], "--title", "practice-" + action,
                "--config", "NONE", "--", sys.executable, __file__, "counter"]
    elif action == "browser":
        argv = [settings["chrome"], "--user-data-dir=" + str(work / "chrome"),
                "--no-first-run", "--no-default-browser-check", "--no-sandbox",
                "--disable-background-networking", "--disable-sync",
                "--disable-component-update", "--disable-extensions",
                "--ozone-platform=wayland", "about:blank"]
    elif action == "files":
        argv = [settings["nautilus"], "--new-window", str(work / "home/Documents")]
    else:
        raise SystemExit("unknown fixture action: " + action)
# Overrides are argv arrays, never shell strings. Python format placeholders
# let a command plan name this run's disposable profiles and marker files.
argv = [s.format(work=str(work), home=str(work / "home"), python=sys.executable,
                 app=__file__) for s in argv]
with (work / "launches.jsonl").open("a") as f:
    f.write(json.dumps({"action": action, "pid": os.getpid(), "argv": argv,
                        "time": time.time()}) + "\n")
os.execvpe(argv[0], argv, os.environ)
