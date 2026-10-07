"""Real Herdr integration exercised only inside smoke.py's private namespaces."""
import json
import os
from pathlib import Path
import runpy
import shlex
import sys


def exercise(directory, metadata, start, run, wait_for, ipc, receipts):
    directory = Path(directory)
    config = directory / "config/herdr"
    config.mkdir()
    runtime = Path(os.environ["XDG_RUNTIME_DIR"])
    socket = runtime / "herdr-smoke.sock"
    assert not socket.exists(), "The isolated test socket must be fresh"
    # No shell init files, plugin registry or restored live sessions are used.
    inert = directory / "inert-shell"
    inert.write_text(f"#!{sys.executable}\nimport sys\nprint('Isolated Herdr smoke shell; input is never executed.', flush=True)\nfor line in sys.stdin:\n    print('literal input: '+line, flush=True)\n")
    inert.chmod(0o755)
    herdr = str(Path(metadata["herdr"]) / "bin/herdr")
    config_path = config / "config.toml"
    config_path.write_text(f'''onboarding = false
[terminal]
default_shell = {json.dumps(str(inert))}
shell_mode = "non_login"
new_cwd = {json.dumps(str(directory / "work"))}
[update]
version_check = false
manifest_check = false
[keys]
prefix = "ctrl+b"
[ui]
prompt_new_workspace_name = true
[theme]
name = "terminal"
''')
    private = {
        "HERDR_CONFIG_PATH": str(config_path),
        "HERDR_SOCKET_PATH": str(socket),
        "HERDR_CLIENT_LOG": str(config / "herdr-client.log"),
    }
    os.environ.update(private)
    # The client bypasses auto-discovery and auto-start: it can only attach to
    # the explicit test socket. Its environment is embedded because Sway's
    # environment predates this helper's setup.
    projector = directory / "local-projector"
    projector.write_text("#!/bin/sh\nexec env " + " ".join(shlex.quote(k + "=" + v) for k, v in private.items()) + " " + shlex.quote(herdr) + " client\n")
    projector.chmod(0o755)
    os.environ["HERDR_PROJECTOR"] = str(projector)
    start("herdr-server", [herdr, "server"])
    wait_for(socket.exists, "private Herdr API socket")

    def snapshot():
        value = json.loads(run([herdr, "api", "snapshot"], capture_output=True).stdout)
        return value.get("result", {}).get("snapshot", value)

    initial = snapshot()
    bridge = runpy.run_path(str(Path(__file__).resolve().parents[2] / "home/dot_local/bin/herdr-picker"))
    ipc("workspace number 3")
    node, created = bridge["ensure_projector"]()
    assert created, "First action should open exactly one new projector"
    # The helper returns its pre-mark node; query the live tree after creation.
    live = next(n for n, w in bridge["projectors"](bridge["tree"]()) if n["id"] == node["id"])
    label = next(mark.removeprefix("herdr-label-") for mark in live["marks"] if mark.startswith("herdr-label-"))
    wait_for(lambda: any(w.get("label") == label for w in snapshot()["workspaces"]), "new named Herdr workspace")
    after = snapshot()
    (directory / "herdr-initial.json").write_text(json.dumps(initial, indent=2))
    (directory / "herdr-after-create.json").write_text(json.dumps(after, indent=2))
    # A brand-new empty server creates its initial workspace on first attach.
    assert len(after["workspaces"]) == max(1, len(initial["workspaces"])) + 1
    assert sum(w.get("label") == label for w in after["workspaces"]) == 1
    second, created_again = bridge["ensure_projector"]()
    assert not created_again and second["id"] == node["id"], "Repeated Mod+Return must reuse its projector"
    assert len(snapshot()["workspaces"]) == len(after["workspaces"])
    bridge["workspace_action"]("close")
    parked = next((n, w) for n, w in bridge["projectors"](bridge["tree"]()) if n["id"] == node["id"])
    assert parked[1]["name"] == "__i3_scratch"
    bridge["workspace_action"]("restore")
    reopened = next((n, w) for n, w in bridge["projectors"](bridge["tree"]()) if n["id"] == node["id"])
    assert reopened[1]["num"] == 3
    assert len(snapshot()["workspaces"]) == len(after["workspaces"])
    pane_ids = {(p["pane_id"], p["terminal_id"]) for p in snapshot()["panes"]}
    ipc(f'[con_id={int(node["id"])}] kill')
    wait_for(lambda: not any(n["id"] == node["id"] for n, w in bridge["projectors"](bridge["tree"]())), "fixture Kitty detaches")
    assert {(p["pane_id"], p["terminal_id"]) for p in snapshot()["panes"]} == pane_ids
    ipc("workspace number 3")
    reconnected, opened = bridge["ensure_projector"](create_workspace=False)
    assert opened and reconnected["id"] != node["id"]
    assert {(p["pane_id"], p["terminal_id"]) for p in snapshot()["panes"]} == pane_ids
    assert len(snapshot()["workspaces"]) == len(after["workspaces"])
    (directory / "herdr-fixture-snapshot.json").write_text(json.dumps(snapshot(), indent=2))
    (directory / "logs/herdr-client-screen.log").write_text(bridge["kitty"](reconnected, "get-text", "--match", "recent:0", "--extent", "screen"))
    receipts.append("Real isolated Herdr: verified new-workspace dialog → unique name submission; second action reuses one projector; park/reopen and Kitty detach/reconnect preserve pane and terminal identities.")
