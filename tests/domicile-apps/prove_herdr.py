"""Real Herdr, private server and PTYs; all pane content is a fixture.
Usage: runtime-test -- python3 tests/domicile-apps/prove_herdr.py OUTDIR
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from test_routing import Terminal, BIN

out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=False)
home = out / "home"
config = home / ".config/herdr"
config.mkdir(parents=True)
herdr = shutil.which("herdr")
recorder = out / "fixture-shell"
recorder.write_text("""#!/usr/bin/env python3
import os, pathlib, sys, tty
pane = os.environ.get("HERDR_PANE_ID","unknown")
path = pathlib.Path(os.environ["FIXTURE_INPUT"]) / (pane + ".input")
print("FIXTURE SHELL " + pane, flush=True)
tty.setraw(0)
while True:
 data = os.read(0,4096)
 if not data: break
 with path.open("ab") as f: f.write(data)
 os.write(1,data)
""")
recorder.chmod(0o755)
body = f'''onboarding = false
[terminal]
default_shell = "{recorder}"
shell_mode = "non_login"
[update]
version_check = false
manifest_check = false
[ui]
prompt_new_workspace_name = false
'''
(config / "config.toml").write_text(body)
(config / "desktop-client.toml").write_text(body)
env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"),
           XDG_STATE_HOME=str(home / ".local/state"), XDG_CACHE_HOME=str(home / ".cache"),
           HERDR_CONFIG_PATH=str(config / "config.toml"), TERM="xterm-256color",
           FIXTURE_INPUT=str(out))
for key in tuple(env):
    if key.startswith("HERDR_") and key != "HERDR_CONFIG_PATH":
        del env[key]

clients = []
server_log = (out / "server.log").open("w")
server = subprocess.Popen([herdr, "server"], env=env, stdout=server_log, stderr=server_log)
receipt = {"herdr": herdr, "checks": {}, "boundary": "private local server; no real NAS transport"}
def api(*args):
    p = subprocess.run([herdr, *args], env=env, capture_output=True, text=True, timeout=10)
    if p.returncode:
        raise RuntimeError((args, p.stderr))
    return json.loads(p.stdout)
def client():
    t = Terminal([herdr, "client"], env)
    clients.append(t)
    return t
def got(pane, text):
    p = out / (pane + ".input")
    end = time.monotonic()+8
    while time.monotonic()<end:
        if p.exists() and text in p.read_bytes():
            return
        time.sleep(.05)
    raise AssertionError((pane,text,p.read_bytes() if p.exists() else "no input"))
try:
    for _ in range(100):
        if "api socket:" in (out / "server.log").read_text():
            break
        if server.poll() is not None:
            raise RuntimeError((out / "server.log").read_text())
        time.sleep(.05)
    old = api("workspace", "create", "--cwd", str(home), "--label", "OLD FIXTURE", "--no-focus")
    (out / "old-created.json").write_text(json.dumps(old, indent=2))
    oldpane = old["result"]["root_pane"]["pane_id"]
    a = client()
    a.expect("FIXTURE SHELL")
    a.send("OLD-CLIENT")
    got(oldpane,b"OLD-CLIENT")
    fresh = api("workspace", "create", "--cwd", str(home), "--label", "FRESH FIXTURE", "--no-focus")
    (out / "fresh-created.json").write_text(json.dumps(fresh, indent=2))
    freshpane = fresh["result"]["root_pane"]["pane_id"]
    a.send("STILL-OLD")
    got(oldpane,b"STILL-OLD")
    b = client()
    b.expect("FIXTURE SHELL")
    b.send("NEW-VIEW-DEFAULT")
    got(oldpane,b"NEW-VIEW-DEFAULT")
    receipt["checks"]["background_create_does_not_bind_new_view"] = True
    # Default menu: ordinary first keys are local, while both clients/panes live.
    before = api("api", "snapshot")
    menu = Terminal([str(BIN / "domicile-terminal")], env)
    clients.append(menu)
    menu.expect("local / nas / quit >")
    menu.send("FIRST-ORDINARY-KEYS\n")
    menu.expect("No action.")
    after = api("api", "snapshot")
    for pane in (oldpane, freshpane):
        p = out / (pane + ".input")
        assert not p.exists() or b"FIRST-ORDINARY-KEYS" not in p.read_bytes()
    assert before["result"]["snapshot"]["workspaces"] == after["result"]["snapshot"]["workspaces"]
    receipt["checks"]["default_first_keys_stay_local_and_topology_unchanged"] = True
    menu.send("quit\n")
    # Explicit remote choice through the unchanged projector, with fake SSH and
    # a local client shim into this REAL private server. No credentials/network.
    fake = out / "bin"
    fake.mkdir()
    (fake / "ssh").write_text("#!/bin/sh\nexit 0\n")
    (fake / "ssh").chmod(0o755)
    shim = "#!/usr/bin/env python3\nimport os,sys,json\nfrom pathlib import Path\n"
    shim += "assert sys.argv[1:] == ['--remote','nas','--remote-keybindings','server']\n"
    shim += "Path(" + repr(str(out / "remote-argv.json")) + ").write_text(json.dumps(sys.argv[1:]))\n"
    shim += "os.execv(" + repr(herdr) + ", [" + repr(herdr) + ", 'client'])\n"
    (fake / "herdr").write_text(shim)
    (fake / "herdr").chmod(0o755)
    routeenv = env | {"PATH": str(fake) + ":" + env["PATH"]}
    routed = Terminal([str(BIN / "domicile-terminal")], routeenv)
    clients.append(routed)
    routed.expect("local / nas / quit >")
    routed.send("nas\n")
    routed.expect("Type ATTACH nas")
    assert not (out / "remote-argv.json").exists()
    routed.send("ATTACH nas\n")
    routed.expect("FIXTURE SHELL")
    routed.send("EXPLICIT-REMOTE")
    got(oldpane, b"EXPLICIT-REMOTE")
    a.send("EXISTING-CLIENT-UNCHANGED")
    got(oldpane, b"EXISTING-CLIENT-UNCHANGED")
    routed.send(b"\x02q")
    routed.expect("back at LOCAL control")
    routed.send("quit\n")
    receipt["checks"]["explicit_mock_transport_reaches_real_existing_fixture_pane"] = True
    receipt["checks"]["explicit_attach_preserves_existing_client_destination"] = True
    # Only private fixtures: establish why public focus is unsafe for a launcher.
    api("workspace", "focus", fresh["result"]["workspace"]["workspace_id"])
    time.sleep(.4)
    a.send("A-RETARGETED")
    got(freshpane,b"A-RETARGETED")
    b.send("B-RETARGETED")
    got(freshpane,b"B-RETARGETED")
    receipt["checks"]["public_focus_retargets_both_existing_clients"] = True
    receipt["old_pane"] = oldpane
    receipt["fresh_pane"] = freshpane
    (out / "snapshot.json").write_text(json.dumps(api("api", "snapshot"), indent=2))
finally:
    for i,t in enumerate(clients):
        t.read()
        (out / f"client-{i}.ansi").write_bytes(t.output)
        t.close()
    if server.poll() is None:
        # This explicit process is OUR isolated server, never an inherited server.
        subprocess.run([herdr, "server", "stop"], env=env, capture_output=True, timeout=20)
        server.wait(timeout=20)
    receipt["server_exit"] = server.returncode
    server_log.close()
    (out / "receipt.json").write_text(json.dumps(receipt, indent=2)+"\n")
print(json.dumps(receipt, indent=2))
