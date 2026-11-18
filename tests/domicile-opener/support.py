"""Shared stand-ins for the desktop opener tests: a fake kitty-persist, a fake
kitty, and loaders for the extension-less scripts. Nothing here reaches a
desktop, a Kitty, ssh or the real kitty-persist."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile

REPO = Path(__file__).resolve().parents[2]
BIN = Path(os.environ.get("DOMICILE_OPENER_BIN", REPO / "home/dot_local/bin"))
AGENT_WINDOWS = Path(os.environ.get("DOMICILE_AGENT_WINDOWS", REPO / "modules/imagine-helpers/agent-windows"))
IMAGINE = Path(os.environ.get("DOMICILE_IMAGINE_SRC", REPO / "pkgs/client-desktop/imagine/src/imagine"))


def load(path, name):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def executable(path, body):
    path.write_text(f"#!{sys.executable}\n" + body)
    path.chmod(0o755)
    return path


# The fake kitty-persist appends its argv to calls.jsonl and answers from a
# script: codes.json is a list of exit codes taken in turn (the last one
# repeats); list.json is what `list --json` and `list --all --json` print.
FAKE_PERSIST = r'''
import json, os, sys
from pathlib import Path
root = Path(os.environ["FAKE_ROOT"])
with (root / "calls.jsonl").open("a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\n")
command = sys.argv[1]
if command == "list":
    records = json.loads((root / "list.json").read_text())
    if "--all" not in sys.argv:
        records = [r for r in records if r.get("state") == "running"]
    print(json.dumps(records))
    raise SystemExit(0)
if command == "forget":
    raise SystemExit(0)
state = root / "codes.json"
codes = json.loads(state.read_text())
code = codes[0]
if len(codes) > 1:
    state.write_text(json.dumps(codes[1:]))
raise SystemExit(code)
'''

FAKE_KITTY = r'''
import json, os, sys
from pathlib import Path
with (Path(os.environ["FAKE_ROOT"]) / "kitty.jsonl").open("a") as log:
    log.write(json.dumps({"argv": sys.argv[1:],
                          "scrubbed": [k for k in ("CLAUDECODE", "HERDR_PANE_ID", "CODEX_THREAD_ID") if k not in os.environ]}) + "\n")
'''


class Fakes:
    def __init__(self):
        self.dir = tempfile.TemporaryDirectory()
        self.root = Path(self.dir.name)
        self.program = executable(self.root / "kitty-persist", FAKE_PERSIST)
        self.kitty = executable(self.root / "kitty", FAKE_KITTY)
        self.codes([0])
        self.listing([])

    def codes(self, values):
        (self.root / "codes.json").write_text(json.dumps(values))

    def listing(self, records):
        (self.root / "list.json").write_text(json.dumps(records))

    def env(self, **extra):
        env = dict(os.environ, FAKE_ROOT=str(self.root), DOMICILE_PERSIST_PROGRAM=str(self.program),
                   DOMICILE_PERSIST_KITTY=str(self.kitty))
        for key in ("DOMICILE_PERSIST_ON_EXIT", "DOMICILE_PERSIST_ON_GONE", "DOMICILE_PERSIST_HOST"):
            env.pop(key, None)
        env.update(extra)
        return env

    def calls(self):
        path = self.root / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def windows(self):
        path = self.root / "kitty.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def close(self):
        self.dir.cleanup()


def record(sid, state="running", clients=0, labels=None, resumed=None, cwd="", launch_cwd="/srv/project"):
    return {"v": 1, "id": sid, "state": state, "clients": clients, "labels": labels or {},
            "resumed": resumed, "cwd": cwd, "launch_cwd": launch_cwd, "label": "", "title": "",
            "agent": None}
