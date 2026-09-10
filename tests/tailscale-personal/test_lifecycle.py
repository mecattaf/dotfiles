"""Opt-in real USER-systemd lifecycle test; never touches network/system units.

Usage: python3 test_lifecycle.py <evaluated-fixtures.json>
Creates uniquely named runtime mock units, tests the actual dependency edges
from the evaluated module, and removes only those units and its temporary files.
Run outside a Nix build sandbox with an authorized, running user manager.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def action(root, role, event):
    root = Path(root)
    ready = root / "address-ready"
    if event == "ready":
        ready.touch()
        return
    if event == "stop":
        ready.unlink(missing_ok=True)
        return
    if role == "firewall" and (root / "fail-firewall").exists():
        raise RuntimeError("Intentional mock firewall failure")
    if role == "caddy" and not ready.exists():
        raise RuntimeError("Caddy started before container postStart assigned its address")
    counter = root / role
    counter.write_text(str(int(counter.read_text()) + 1 if counter.exists() else 1))


if len(sys.argv) > 1 and sys.argv[1] == "--fixture-action":
    action(*sys.argv[2:])
    sys.exit(0)


def main():
    with open(sys.argv[1], encoding="utf-8") as stream:
        lifecycle = json.load(stream)["tls"]["lifecycle"]
    ctl = ["systemctl", "--user"]
    subprocess.run(ctl + ["show-environment"], check=True, stdout=subprocess.DEVNULL)
    with tempfile.TemporaryDirectory(prefix="personal-lifecycle-") as directory:
        root = Path(directory)
        prefix = root.name
        roles = {"nftables": "firewall", "container@nas-saas": "container", "caddy": "caddy"}
        names = {key + ".service": prefix + "-" + role + ".service" for key, role in roles.items()}
        units = list(names.values())
        script = str(Path(__file__).resolve())
        python = str(Path(sys.executable).resolve())

        def call(*args, check=True):
            return subprocess.run(ctl + list(args), check=check, capture_output=True, text=True)

        def count(role):
            path = root / role
            return int(path.read_text()) if path.exists() else 0

        def active(expected):
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                states = call("show", "--property=ActiveState", "--value", *units).stdout.split()
                counts = [count(role) for role in roles.values()]
                if states == ["active"] * 3 and counts == [expected] * 3:
                    return
                time.sleep(0.05)
            raise AssertionError(("Units did not settle", states, counts, expected))

        def inactive(unit):
            state = call("show", "--property=ActiveState", "--value", unit).stdout.strip()
            assert state in ("inactive", "failed"), (unit, state)

        for key, role in roles.items():
            edges = lifecycle[key]
            lines = ["[Unit]", "Description=Disposable personal-tailnet lifecycle verification"]
            for source, directive in [("after", "After"), ("requires", "Requires"),
                                      ("bindsTo", "BindsTo"), ("partOf", "PartOf")]:
                dependencies = [names[x] for x in edges[source] if x in names]
                if dependencies:
                    lines.append(directive + "=" + " ".join(dependencies))
            lines += ["[Service]", "Type=oneshot", "RemainAfterExit=yes",
                      f'ExecStart="{python}" "{script}" --fixture-action "{root}" {role} start']
            if role == "container":
                lines += [f'ExecStartPost="{python}" "{script}" --fixture-action "{root}" {role} ready',
                          f'ExecStop="{python}" "{script}" --fixture-action "{root}" {role} stop']
            parents = [names[x] for x in edges["wantedBy"] if x in names]
            if parents:
                lines += ["[Install]", "WantedBy=" + " ".join(parents)]
            (root / names[key + ".service"]).write_text("\n".join(lines) + "\n")

        try:
            # All names derive from the newly allocated temporary directory.
            # No persistent unit paths, real firewall, container or Caddy touched.
            call("link", "--runtime", *(str(root / unit) for unit in units))
            call("enable", "--runtime", names["container@nas-saas.service"], names["caddy.service"])
            call("daemon-reload")
            firewall = names["nftables.service"]
            call("start", firewall)
            active(1)

            call("restart", firewall)
            active(2)

            call("stop", firewall)
            for unit in units:
                inactive(unit)
            call("start", firewall)
            active(3)

            call("stop", firewall)
            (root / "fail-firewall").touch()
            assert call("start", firewall, check=False).returncode != 0
            for unit in units:
                inactive(unit)
            assert count("container") == 3 and count("caddy") == 3
            (root / "fail-firewall").unlink()
            call("reset-failed", *units, check=False)
            call("start", firewall)
            active(4)
            print("PASS: startup ordering, restart propagation, stop/start recovery, failure/recovery")
        finally:
            call("stop", *units, check=False)
            call("disable", "--runtime", *units, check=False)
            call("reset-failed", *units, check=False)
            call("daemon-reload", check=False)
            # Runtime enable/link should have been removed by disable. Fail
            # visibly if cleanup was incomplete, rather than deleting broadly.
            runtime = Path(os.environ["XDG_RUNTIME_DIR"]) / "systemd/user"
            leftovers = [str(runtime / unit) for unit in units if (runtime / unit).is_symlink()]
            if leftovers:
                raise RuntimeError("Mock-unit cleanup incomplete: " + ", ".join(leftovers))
    print("Removed the three temporary user units and their uniquely allocated fixture directory.")


if __name__ == "__main__":
    main()
