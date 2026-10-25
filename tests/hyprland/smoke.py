#!/usr/bin/env python3
"""Real Hyprland + native Solid shell on an isolated nested GPU desktop.

No physical display/input devices or live runtime sockets enter the test.
Every process log and screenshot is retained, including failures.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[2]


def run(argv, **kwargs):
    return subprocess.run([str(a) for a in argv], check=True, text=True,
                          timeout=kwargs.pop("timeout", 30), **kwargs)


def wait_for(check, label, seconds=30):
    until = time.monotonic() + seconds
    while time.monotonic() < until:
        value = check()
        if value:
            return value
        time.sleep(.1)
    raise AssertionError(f"Timeout waiting for {label}")


def prepare(directory, shell, nested_library=None):
    expr = f'''let f = builtins.getFlake {json.dumps(str(ROOT))};
      c = f.nixosConfigurations.client.config; h = c.home-manager.users.tom;
    in {{ parent = f.nixosConfigurations.client.pkgs.sway.outPath;
      hyprland = c.programs.hyprland.package.outPath;
      waylandInfo = f.nixosConfigurations.client.pkgs.wayland-utils.outPath;
      localConfig = h.xdg.configFile."hyprland-local.conf".text;
      theme = h.xdg.configFile."themes/noir/hyprland.conf".text;
      kittyTheme = h.xdg.configFile."themes/noir/kitty.conf".text;
    }}'''
    meta = json.loads(run(["nix", "eval", "--impure", "--json", "--expr", expr], capture_output=True).stdout)
    meta["shell"] = str(shell.resolve())
    meta["nestedLibrary"] = str(nested_library.resolve()) if nested_library else None
    (directory / "metadata.json").write_text(json.dumps(meta, indent=2))
    for name in ["config", "data", "cache", "state", "logs", "empty-apps"]:
        (directory / name).mkdir()
    cfg = directory / "config"
    (cfg / "parent-sway.conf").write_text("output * mode 1440x900 scale 1\ndefault_border none\nxwayland disable\nseat seat0 fallback true\n")
    shutil.copytree(ROOT / "home/dot_config/hypr", cfg / "hypr")
    (cfg / "hypr/startup.conf").write_text("# Test: no services, desktop settings or applications autostart.\n")
    (cfg / "session.conf").write_text("# Test: never import environment into a user manager.\n")
    (cfg / "hyprland-local.conf").write_text(meta["localConfig"] + "\nmonitor = , 1440x900@60, auto, 1\n")
    (cfg / "theme").mkdir()
    (cfg / "theme/hyprland.conf").write_text(meta["theme"])
    (cfg / "theme/kitty.conf").write_text(meta["kittyTheme"])
    main = (cfg / "hypr/hyprland.conf").read_text()
    main = main.replace("/etc/hypr/physical-session.conf", str(cfg / "session.conf"))
    main = main.replace("~/.config/", f"{cfg}/")
    (cfg / "hypr/hyprland.conf").write_text(main + "\ndebug:disable_logs = false\ndebug:enable_stdout_logs = true\n")
    (directory / "dbus.conf").write_text('''<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>
<policy context="default"><allow send_destination="*"/><allow send_type="error" send_requested_reply="false"/><allow receive_sender="*"/><allow receive_type="error" receive_requested_reply="false"/><allow own="*"/></policy></busconfig>\n''')
    return meta


def exercise(directory):
    meta = json.loads((directory / "metadata.json").read_text())
    runtime = Path(os.environ["XDG_RUNTIME_DIR"])
    assert not (runtime / "bus").exists(), "Live user bus is visible"
    assert not list(Path("/dev/dri").glob("card*")), "Physical display devices exposed"
    assert not Path("/dev/input").exists(), "Physical input devices exposed"
    children, logs, results = [], [], []

    def start(name, argv, env=None):
        log = (directory / "logs" / f"{name}.log").open("w")
        logs.append(log)
        proc = subprocess.Popen([str(a) for a in argv], env=env, stdout=log, stderr=subprocess.STDOUT)
        children.append((name, proc))
        return proc

    def alive(proc, label):
        if proc.poll() is not None:
            raise AssertionError(f"{label} exited {proc.returncode}; see {directory / 'logs'}")

    try:
        parent_env = {**os.environ, "WLR_BACKENDS": "headless", "WLR_HEADLESS_OUTPUTS": "1",
                      "WLR_RENDERER": "gles2", "WLR_RENDER_DRM_DEVICE": os.environ["TEST_RENDER_NODE"],
                      "WLR_LIBINPUT_NO_DEVICES": "1"}
        parent = start("parent-sway", [meta["parent"] + "/bin/sway", "--unsupported-gpu",
                       "--config", directory / "config/parent-sway.conf"], env=parent_env)

        def parent_socket():
            alive(parent, "Parent Sway")
            return next((p for p in runtime.glob("wayland-*") if p.is_socket()), None)

        parent_path = wait_for(parent_socket, "isolated parent compositor")
        os.environ["WAYLAND_DISPLAY"] = parent_path.name
        os.environ["HYPRLAND_NO_SD_VARS"] = "1"
        hypr_env = dict(os.environ)
        if meta["nestedLibrary"]:
            hypr_env["LD_LIBRARY_PATH"] = meta["nestedLibrary"]
        hypr = start("hyprland", [meta["hyprland"] + "/bin/Hyprland", "--config", directory / "config/hypr/hyprland.conf"], env=hypr_env)

        def hypr_socket():
            alive(hypr, "Hyprland")
            return next((p for p in (runtime / "hypr").glob("*/.socket.sock") if p.is_socket()), None)

        socket = wait_for(hypr_socket, "Hyprland IPC")
        os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = socket.parent.name
        hyprctl = meta["hyprland"] + "/bin/hyprctl"

        def query(name):
            return json.loads(run([hyprctl, "-j", name], capture_output=True).stdout)

        def ready():
            alive(hypr, "Hyprland")
            try:
                return query("monitors")
            except (subprocess.SubprocessError, ValueError):
                return None

        monitors = wait_for(ready, "Hyprland output")
        nested = wait_for(lambda: next((p for p in runtime.glob("wayland-*") if p.is_socket() and p != parent_path), None), "nested Wayland socket")
        os.environ["WAYLAND_DISPLAY"] = nested.name
        (directory / "monitors.json").write_text(json.dumps(monitors, indent=2))
        info = run([meta["waylandInfo"] + "/bin/wayland-info"], capture_output=True)
        (directory / "wayland-globals.txt").write_text(info.stdout)
        assert "ext_background_effect_manager_v1" in info.stdout, "Missing standard background-effect protocol"
        assert "zwlr_output_manager_v1" in info.stdout, "Missing existing Kanshi protocol"
        errors = run([hyprctl, "configerrors"], capture_output=True).stdout.strip()
        assert not errors, errors
        compatibility = " using TEST-ONLY Aquamarine registry-version clamp" if meta["nestedLibrary"] else ""
        results.append("Actual Hyprland0.56 parsed delivered config and started nested on a render-only GPU node" + compatibility + ".")

        fixture = start("kitty-fixture", ["kitty", "--config", "NONE", "--class", "desktop-shell-fixture", "--title", "Shell integration fixture", "-o", "shell_integration=disabled", "-e", sys.executable, "-c",
                    "import sys,time; sys.stdout.write('\\033[2J\\033[H' + ''.join(''.join('\\033[48;2;' + ('210;210;210' if (x+y)%2 else '25;25;25') + 'm  ' for x in range(200)) + '\\033[0m\\n' for y in range(100))); sys.stdout.flush(); time.sleep(300)"])
        clients = wait_for(lambda: [c for c in query("clients") if c["class"] == "desktop-shell-fixture"], "real kitty window")
        address = clients[0]["address"]
        run([hyprctl, "dispatch", "movetoworkspacesilent", f"2,address:{address}"], capture_output=True)
        run([hyprctl, "dispatch", "workspace", "2"], capture_output=True)
        assert any(c["address"] == address and c["workspace"]["id"] == 2 for c in query("clients"))
        results.append("Real kitty window moves to and focuses workspace2 through Hyprland IPC.")

        def layers():
            return json.dumps(query("layers"))

        bar = start("shell-bar", [meta["shell"], "bar"])

        def has_bar():
            alive(bar, "Native shell")
            return "desktop-shell-bar" in layers()

        wait_for(has_bar, "native Solid layer-shell bar")
        time.sleep(1)
        run(["grim", directory / "bar.png"])
        results.append("Native Solid GPUIX bar maps as layer-shell and renders alongside kitty.")
        for mode in ["launcher", "controls", "windows"]:
            view = start(f"shell-{mode}", [meta["shell"], mode])
            def visible():
                alive(view, mode)
                return f"desktop-shell-{mode}" in layers()
            wait_for(visible, f"native {mode}")
            time.sleep(.5)
            run(["grim", directory / f"{mode}.png"])
            if mode == "controls":
                measure_blur(directory, query, hyprctl, hypr, view)
            run([meta["shell"], mode], capture_output=True)
            wait_for(lambda: view.poll() is not None, f"{mode} toggle closes its own process")
            assert view.returncode == 0, f"{mode} exit {view.returncode}"
            results.append(f"Native {mode} renders and repeated command closes its own popup.")
        alive(fixture, "Kitty fixture")
        alive(bar, "Shell bar")
        alive(hypr, "Hyprland")
        (directory / "results.json").write_text(json.dumps(results, indent=2))
        print("\n".join(results), flush=True)
    finally:
        for log_path in (runtime / "hypr").glob("*/hyprland.log"):
            shutil.copy2(log_path, directory / "logs" / "hyprland-runtime.log")
        for name, child in reversed(children):
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
                    print(f"{name} needed SIGKILL", file=sys.stderr)
            elif child.returncode != 0:
                print(f"{name} exited unexpectedly: {child.returncode}", file=sys.stderr)
        for log in logs:
            log.close()
        print(f"Full test evidence retained: {directory}", flush=True)


def find_layer(value, namespace):
    if isinstance(value, dict):
        if value.get("namespace") == namespace:
            return value
        for child in value.values():
            found = find_layer(child, namespace)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = find_layer(child, namespace)
            if found:
                return found
    return None


def cpu_ticks(pid):
    # After ')' the first field is proc stat field 3; utime/stime are 14/15.
    fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
    return int(fields[11]) + int(fields[12])


def measure_blur(directory, query, hyprctl, compositor, popup):
    layer = find_layer(query("layers"), "desktop-shell-controls")
    assert layer, "Controls surface disappeared before blur proof"
    (directory / "blur-surface.json").write_text(json.dumps(layer, indent=2))
    x, y, w, h = (int(layer[k]) for k in ["x", "y", "w", "h"])
    box = (x + 10, y + 10, x + w - 10, y + h - 10)
    shots = {}
    cpu = {}
    for name, enabled in [("off", "false"), ("on", "true")]:
        run([hyprctl, "keyword", "decoration:blur:enabled", enabled], capture_output=True)
        time.sleep(.6)
        shot = directory / f"blur-{name}.png"
        run(["grim", shot])
        shots[name] = Image.open(shot).convert("RGB").crop(box)
        before = {"compositor": cpu_ticks(compositor.pid), "popup": cpu_ticks(popup.pid)}
        start = time.monotonic()
        time.sleep(2)
        elapsed = time.monotonic() - start
        hz = os.sysconf("SC_CLK_TCK")
        cpu[name] = {key: {"cpu_seconds": (cpu_ticks(proc.pid)-before[key])/hz,
                          "wall_seconds": elapsed}
                     for key, proc in [("compositor", compositor), ("popup", popup)]}
    difference = ImageChops.difference(shots["off"], shots["on"])
    mean_difference = sum(ImageStat.Stat(difference).mean) / 3
    def edge_energy(img):
        gray = img.convert("L")
        shifted = ImageChops.offset(gray, 1, 0)
        return ImageStat.Stat(ImageChops.difference(gray, shifted)).mean[0]
    metrics = {"region": box, "mean_absolute_rgb_difference": mean_difference,
               "horizontal_edge_energy_off": edge_energy(shots["off"]),
               "horizontal_edge_energy_on": edge_energy(shots["on"]),
               "idle_cpu_samples": cpu,
               "scope": "One nested GPU renderer run; not a production performance benchmark."}
    (directory / "blur-metrics.json").write_text(json.dumps(metrics, indent=2))
    assert mean_difference > .05, "Enabling compositor blur made no measurable surface-pixel difference"
    assert metrics["horizontal_edge_energy_on"] < metrics["horizontal_edge_energy_off"], "Blur did not reduce checkerboard high-frequency edges"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shell", type=Path)
    parser.add_argument("--render-node", default="/dev/dri/renderD128")
    parser.add_argument("--nested-library", type=Path,
                        help="Test-only patched Aquamarine lib directory; recorded in evidence, never installed")
    parser.add_argument("--inside", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.inside:
        exercise(args.inside)
        return
    if not args.shell or not args.shell.is_file():
        parser.error("--shell must name the built desktop-shell executable")
    directory = Path(tempfile.mkdtemp(prefix="hyprland-solid-smoke-"))
    prepare(directory, args.shell, args.nested_library)
    env = {k: v for k, v in os.environ.items() if not k.startswith("HERDR_")}
    env.update(XDG_CONFIG_HOME=str(directory / "config"), XDG_DATA_HOME=str(directory / "data"),
               XDG_CACHE_HOME=str(directory / "cache"), XDG_STATE_HOME=str(directory / "state"),
               XDG_DATA_DIRS=str(directory / "empty-apps"), XDG_CONFIG_DIRS=str(directory / "config"),
               DBUS_SYSTEM_BUS_ADDRESS="unix:path=/nonexistent-test-system-bus",
               XDG_CURRENT_DESKTOP="Hyprland", XDG_SESSION_TYPE="wayland", NO_AT_BRIDGE="1",
               TEST_RENDER_NODE=args.render_node)
    print(f"Isolated test evidence: {directory}", flush=True)
    run([ROOT / "home/dot_local/bin/runtime-test", "--render-node", args.render_node, "--",
         "bwrap", "--die-with-parent", "--unshare-net", "--bind", "/", "/", "--dev-bind", "/dev", "/dev",
         "--tmpfs", "/tmp/.X11-unix", "--chmod", "1777", "/tmp/.X11-unix", "--",
         "dbus-run-session", "--config-file", directory / "dbus.conf", "--",
         sys.executable, __file__, "--inside", directory], env=env, timeout=240)


if __name__ == "__main__":
    main()
