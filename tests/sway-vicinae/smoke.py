#!/usr/bin/env python3
"""Exercise real desktop clients on a private, software-rendered Wayland seat."""
import argparse
import json
import os
import runpy
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def run(args, **kwargs):
    kwargs.setdefault("timeout", 30)
    try:
        return subprocess.run([str(a) for a in args], text=True, check=True, **kwargs)
    except subprocess.CalledProcessError as error:
        if error.stdout:
            print(error.stdout, file=sys.stderr)
        if error.stderr:
            print(error.stderr, file=sys.stderr)
        raise


def wait_for(predicate, description, timeout=15):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError(f"Timed out: {description}")


def prepare(directory):
    # Evaluate the actual selected client configuration, not a second hand-written theme.
    expression = f'''let f = builtins.getFlake {json.dumps(str(ROOT))};
      c = f.nixosConfigurations.client.config; h = c.home-manager.users.tom; p = f.nixosConfigurations.client.pkgs;
    in {{ sway = c.programs.sway.package.outPath; mako = h.services.mako.package.outPath;
      vicinae = f.inputs.vicinae.packages.${{p.stdenv.hostPlatform.system}}.default.outPath; notify = p.libnotify.outPath; herdr = f.inputs.herdr.packages.${{p.stdenv.hostPlatform.system}}.herdr.outPath;
      settings = h.programs.vicinae.settings; makoConfig = h.xdg.configFile."mako/config".text;
      localConfig = h.xdg.configFile."sway-local.conf".text;
      themes = builtins.mapAttrs (name: value: value.text) (p.lib.filterAttrs
        (name: value: builtins.match "themes/.*/(sway.conf|mako.conf|vicinae.toml|kitty.conf)" name != null) h.xdg.configFile);
    }}'''
    metadata = json.loads(run(["nix", "eval", "--impure", "--json", "--expr", expression], capture_output=True).stdout)
    (directory / "metadata.json").write_text(json.dumps(metadata, indent=2))
    for name in ["config", "data", "cache", "state", "logs", "empty-apps", "work"]:
        (directory / name).mkdir()
    config = directory / "config"
    shutil.copytree(ROOT / "home/dot_config/sway", config / "sway")
    # A compositor test must never import sockets or start the user's systemd targets.
    (config / "session.conf").write_text("# Session integration is inert in the isolated smoke test.\n")
    (config / "sway/startup.conf").write_text("# No wallpaper, services, applications or desktop settings are started.\n")
    (config / "sway-local.conf").write_text(metadata["localConfig"])
    main = (config / "sway/config").read_text().replace("/etc/sway/physical-session.conf", str(config / "session.conf"))
    main = main.replace("~/.config/", f"{config}/")
    (config / "sway/config").write_text(main)
    (config / "theme").mkdir()
    for name, content in metadata["themes"].items():
        target = config / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
    for name in ["sway.conf", "mako.conf", "vicinae.toml", "kitty.conf"]:
        shutil.copyfile(config / "themes/claude-dark" / name, config / "theme" / name)
    (config / "kitty").mkdir()
    kitty_config = (ROOT / "home/dot_config/kitty/kitty.conf").read_text()
    kitty_config = kitty_config.replace("${HOME}/.config/", f"{config}/")
    (config / "kitty-scrollback-nix.conf").write_text("# Scrollback editor is not invoked by the desktop smoke test.\n")
    (config / "kitty/kitty.conf").write_text(kitty_config + "\nshell_integration disabled\n")
    (config / "mako").mkdir()
    (config / "mako/config").write_text(metadata["makoConfig"].replace("/home/tom/.config/theme/", f"{config}/theme/"))
    settings = metadata["settings"]
    settings["providers"]["files"]["preferences"].update(autoIndexing=False, indexingPaths=[])
    settings["providers"]["clipboard"]["preferences"]["monitoring"] = False
    settings["favorites"] = []
    settings["fallbacks"] = []
    (config / "vicinae").mkdir()
    (config / "vicinae/vicinae.json").write_text(json.dumps(settings, indent=2))
    theme_dir = directory / "data/vicinae/themes"
    theme_dir.mkdir(parents=True)
    shutil.copyfile(config / "theme/vicinae.toml", theme_dir / "dotfiles-current.toml")
    # No service directories: D-Bus cannot activate a real user service.
    (directory / "dbus.conf").write_text('''<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>
<policy context="default"><allow send_destination="*"/><allow send_type="error" send_requested_reply="false"/><allow receive_sender="*"/><allow receive_type="error" receive_requested_reply="false"/><allow own="*"/></policy></busconfig>\n''')
    return metadata


def exercise(directory, screenshot):
    assert not (Path(os.environ["XDG_RUNTIME_DIR"]) / "bus").exists(), "Refusing a live user runtime"
    assert os.environ["XDG_CONFIG_HOME"] == str(directory / "config")
    metadata = json.loads((directory / "metadata.json").read_text())
    config = directory / "config"
    sway = Path(metadata["sway"]) / "bin/sway"
    swaymsg = Path(metadata["sway"]) / "bin/swaymsg"
    vicinae = Path(metadata["vicinae"]) / "bin/vicinae"
    children = []
    receipts = []

    def start(name, command):
        log = open(directory / "logs" / f"{name}.log", "w")
        child = subprocess.Popen([str(x) for x in command], stdout=log, stderr=subprocess.STDOUT)
        log.close()
        children.append((name, child))
        return child

    def ipc(command):
        value = json.loads(run([swaymsg, "-r", command], capture_output=True).stdout)
        assert all(v.get("success") for v in value), (command, value)

    def query(kind):
        return json.loads(run([swaymsg, "-r", "-t", kind], capture_output=True).stdout)

    def focused():
        return next(w for w in query("get_workspaces") if w["focused"])

    def key(name):
        run(["wtype", "-M", "logo", "-k", name, "-m", "logo"])

    def is_open():
        try:
            return subprocess.run([vicinae, "state", "open"], capture_output=True, timeout=2).returncode == 0
        except subprocess.TimeoutExpired:
            return False

    def terminal(name, app_id, text):
        return start(name, ["kitty", "--config", "NONE", "--class", app_id,
            "--title", name, "--directory", directory / "work", "-o", "shell_integration=disabled",
            "-o", "background=#101010", "-o", "foreground=#c2c0b6", "-o", "font_family=AnthropicMono Nerd Font",
            sys.executable, "-u", "-c", f"import time; print({text!r}, flush=True); time.sleep(120)"])

    try:
        # Parse every delivered palette with the complete raw input/layout/bindings/rules.
        for palette in ["claude-dark", "claude-light", "noir"]:
            shutil.copyfile(config / "themes" / palette / "sway.conf", config / "theme/sway.conf")
            log = directory / "logs" / f"sway-parse-{palette}.log"
            with log.open("w") as output:
                run([sway, "-C", "-c", config / "sway/config"], stdout=output, stderr=subprocess.STDOUT)
        shutil.copyfile(config / "themes/claude-dark/sway.conf", config / "theme/sway.conf")
        receipts.append("All three rendered Sway palettes passed native configuration validation.")
        # Simulate the Duo's two 2880x1800 panels at scale 2, vertically stacked.
        with (config / "sway/config").open("a") as output:
            output.write("\noutput HEADLESS-1 mode 2880x1800 scale 2 position 0 0\noutput HEADLESS-2 mode 2880x1800 scale 2 position 0 900\n")
        compositor = start("sway", [sway, "-c", config / "sway/config"])
        socket = wait_for(lambda: next(Path(os.environ["XDG_RUNTIME_DIR"]).glob("sway-ipc.*.sock"), None), "Sway IPC socket")
        os.environ["SWAYSOCK"] = str(socket)
        wayland = wait_for(lambda: next((p for p in Path(os.environ["XDG_RUNTIME_DIR"]).glob("wayland-*") if not p.name.endswith(".lock")), None), "Wayland socket")
        os.environ["WAYLAND_DISPLAY"] = wayland.name
        wait_for(lambda: len(query("get_outputs")) == 2, "two simulated panels")
        ipc("workspace number 1; move workspace to output HEADLESS-1; focus output HEADLESS-1")
        terminal("Herdr preview — simulated, no agent running", "smoke-herdr", "\n  HERDR DESKTOP PREVIEW\n\n  Synthetic display fixture. Live sessions and agents were not touched.\n\n  Mod+D   Vicinae commands\n  Mod+K   Herdr workspace search\n  Mod+1–9 Native Sway workspace slots\n  Mod+0   Chrome workspace\n")
        wait_for(lambda: "smoke-herdr" in json.dumps(query("get_tree")), "harmless terminal")
        bridge_api = runpy.run_path(str(ROOT / "home/dot_local/bin/herdr-picker"))
        quote = bridge_api["quote_sway"]
        for label in ['a"; kill; "b', '$mod', r'back\slash,semicolon;', "Ship it; tomorrow, côté"]:
            target = "1: " + label
            try:
                quoted = quote(target)
            except (ValueError, bridge_api["BridgeError"]):
                assert any(char in label for char in ['"', "\\", "$"]), "Supported workspace label was rejected"
                continue  # Production rejects names its native parser cannot round-trip.
            ipc(f'rename workspace {quote(focused()["name"])} to {quoted}')
            assert focused()["name"] == target, ("Workspace name was interpreted", target, focused())
            assert "smoke-herdr" in json.dumps(query("get_tree")), "Quoted name executed a command"
        ipc(f'rename workspace {quote(focused()["name"])} to "1: preview"')
        receipts.append("Unsupported quote/backslash/dollar workspace labels were rejected; supported punctuation and Unicode round-tripped.")
        for number in range(2, 10):
            key(str(number))
            wait_for(lambda n=number: focused()["num"] == n, f"Mod+{number} switches workspace")
        key("1")
        wait_for(lambda: focused()["name"] == "1: preview", "Mod+1 finds renamed native workspace")
        terminal("Chrome placement fixture — no browser running", "google-chrome", "\n  CHROME WORKSPACE 10\n\n  Harmless terminal carrying Chrome's Wayland app_id.\n  This verifies the production Sway assignment; Chrome is not launched.\n")
        wait_for(lambda: any(w["num"] == 10 for w in query("get_workspaces")), "Chrome rule creates slot 10")
        key("0")
        wait_for(lambda: focused()["num"] == 10, "Mod+0 switches to Chrome slot")
        ipc("move workspace to output HEADLESS-2; focus output HEADLESS-1; workspace number 1")
        receipts.append("Mod+1–9 bindings, renamed-workspace navigation, and Chrome app-id assignment / Mod+0 passed.")
        local_herdr = runpy.run_path(str(Path(__file__).with_name("herdr_local.py")))
        local_herdr["exercise"](directory, metadata, start, run, wait_for, ipc, receipts)
        ipc("workspace number 1")
        font = run(["fc-match", "-f", "%{family}", "Anthropic Sans"], capture_output=True).stdout
        assert "Anthropic Sans" in font, font
        mako = start("mako", [Path(metadata["mako"]) / "bin/mako", "--config", config / "mako/config"])
        time.sleep(0.4)
        assert mako.poll() is None, "Mako exited; inspect log"
        # Headless Sway otherwise has no persistent keyboard: each wtype
        # invocation adds/removes its only device and can reset layer focus.
        start("virtual-keyboard", ["wtype", "-s", "120000"])
        server = start("vicinae", [vicinae, "server", "--no-extension-runtime", "--config", config / "vicinae/vicinae.json"])
        wait_for(lambda: subprocess.run([vicinae, "ping"], capture_output=True).returncode == 0, "Vicinae server", timeout=30)
        key("d")
        wait_for(is_open, "Mod+D opens Vicinae")
        # Exercise the two actual dmenu paths used by the Herdr picker and rename.
        run([vicinae, "close"])
        wait_for(lambda: not is_open(), "launcher closes before dmenu")
        for case, rows, typed, expected in [
            ("selection", "Fixture alpha\nFixture beta\n", "", "Fixture alpha"),
            ("rename", "", "Native workspace name", "Native workspace name"),
        ]:
            with (directory / "logs" / f"dmenu-{case}.log").open("w") as error_log:
                menu = subprocess.Popen([sys.executable, "-c",
                    "import runpy,sys; b=runpy.run_path(sys.argv[1]); print(b['dmenu'](sys.stdin.read().splitlines(),sys.argv[2],free_text=sys.argv[3]=='rename') or '')",
                    str(ROOT / "home/dot_local/bin/herdr-picker"), f"Smoke {case}", case],
                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=error_log, text=True)
                children.append((f"dmenu-{case}", menu))
                menu.stdin.write(rows)
                menu.stdin.close()
                menu.stdin = None
                # Concurrent stock CLI requests reproduce the upstream ID
                # collision unless the production bridge uses unique IDs.
                def menu_ready():
                    assert menu.poll() is None, f"dmenu exited {menu.returncode}; inspect its log"
                    return is_open()
                wait_for(menu_ready, f"dmenu {case} opens")
                time.sleep(0.3)
                run(["grim", directory / f"dmenu-{case}-before.png"])
                if typed:
                    run(["wtype", "-d", "35", typed, "-s", "350", "-k", "Return"])
                else:
                    run(["wtype", "-k", "Return"])
                result, _ = menu.communicate(timeout=8)
                assert menu.returncode == 0 and result.strip() == expected, (case, menu.returncode, result)
            wait_for(lambda: not is_open(), f"dmenu {case} closes")
        receipts.append("Real Vicinae dmenu returns a selected fixture row and accepts typed workspace names with empty stdin.")
        key("d")
        wait_for(is_open, "root launcher reopens")
        theme = run([vicinae, "theme", "set", "dotfiles-current"], capture_output=True).stdout
        (directory / "logs/vicinae-theme.log").write_text(theme)
        run([Path(metadata["notify"]) / "bin/notify-send", "-t", "0", "Desktop smoke test", "Mako · Anthropic Sans · shared Herdr palette\nSynthetic preview: no live agents or browser."])
        notifications = run([Path(metadata["mako"]) / "bin/makoctl", "list"], capture_output=True).stdout
        assert "Desktop smoke test" in notifications, notifications
        time.sleep(1)
        run(["grim", screenshot])
        run([vicinae, "close"])
        assert subprocess.run([vicinae, "state", "open"], capture_output=True).returncode != 0
        assert compositor.poll() is None and server.poll() is None and mako.poll() is None
        receipts.append("Vicinae starts without extension runtime, loads the custom theme, opens via Mod+D, renders and closes; Mako receives a notification with Anthropic Sans available.")
        receipts.append(f"Screenshot: {screenshot}")
        (directory / "results.json").write_text(json.dumps(receipts, indent=2))
        print("\n".join(receipts), flush=True)
    finally:
        # Terminate only our Popen children, never a compositor/service by name.
        for name, child in reversed(children):
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
                    print(f"{name}: required SIGKILL after shutdown timeout", file=sys.stderr)
            elif child.returncode != 0:
                print(f"{name}: exited unexpectedly with status {child.returncode}", file=sys.stderr)
        print(f"Full logs retained in {directory / 'logs'}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--screenshot", type=Path, default=Path("/tmp/sway-vicinae-preview.png"))
    parser.add_argument("--inside", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.inside:
        exercise(args.inside, args.screenshot)
        return
    wrapper = Path.home() / ".local/bin/runtime-test"
    if not wrapper.is_file() or not shutil.which("bwrap"):
        raise SystemExit("runtime-test and bubblewrap are required; refusing an unisolated desktop test")
    directory = Path(tempfile.mkdtemp(prefix="sway-vicinae-smoke-"))
    metadata = prepare(directory)
    environment = {key: value for key, value in os.environ.items() if not key.startswith("HERDR_")}
    # Never inherit this agent's pane/session/socket selectors into the test.
    environment.update({
        "XDG_CONFIG_HOME": str(directory / "config"), "XDG_DATA_HOME": str(directory / "data"),
        "XDG_CACHE_HOME": str(directory / "cache"), "XDG_STATE_HOME": str(directory / "state"),
        "XDG_DATA_DIRS": str(directory / "empty-apps"), "XDG_CONFIG_DIRS": str(directory / "config"),
        "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=/nonexistent-smoke-system-bus",
        "WLR_BACKENDS": "headless", "WLR_HEADLESS_OUTPUTS": "2", "WLR_RENDERER": "pixman",
        "XDG_CURRENT_DESKTOP": "sway-physical", "XDG_SESSION_TYPE": "wayland",
        "VICINAE_DISABLE_AUTO_RATE_REFRESH": "1",
        "QT_QPA_PLATFORM": "wayland", "QT_QUICK_BACKEND": "software", "LIBGL_ALWAYS_SOFTWARE": "1", "NO_AT_BRIDGE": "1",
        "PATH": f"{metadata['sway']}/bin:{metadata['vicinae']}/bin:{os.environ['PATH']}",
    })
    print(f"Isolated desktop test artifacts: {directory}", flush=True)
    run([wrapper, "--", "bwrap", "--die-with-parent", "--unshare-net", "--bind", "/", "/", "--dev", "/dev", "--tmpfs", "/tmp/.X11-unix", "--chmod", "1777", "/tmp/.X11-unix", "--", "dbus-run-session", "--config-file", directory / "dbus.conf", "--", sys.executable,
         __file__, "--inside", directory, "--screenshot", args.screenshot.resolve()], env=environment, timeout=180)


if __name__ == "__main__":
    main()
