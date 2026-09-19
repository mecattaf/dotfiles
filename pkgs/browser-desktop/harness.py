"""Microsoft FARA's model loop, using a noVNC canvas as its environment.

No remote-Chrome CDP, custom RFB implementation, or replacement model prompt.
The pinned upstream Fara15Agent owns image scaling, prompting, parsing and action
dispatch. This adapter owns session lifecycle, human takeover and evidence.
"""
import argparse
import asyncio
import base64
import contextlib
import copy
from datetime import datetime
import fcntl
import html
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import urllib.request
import urllib.error
from urllib.parse import urlparse
from session import MANUAL, TASK_LEASE, TASK_MODEL, start_desktop, stop_desktop, launch_chrome, desktop_status

RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "browser-desktop"
RUNS = Path.home() / ".local/state/fara-browser/runs"
ASSETS = Path(__file__).parent
CONTROL = "http://127.0.0.1:4782"


def chrome_profiles(data_dir):
    """Chrome's recorded profile identities; never infer website logins."""
    state = json.loads((data_dir / "Local State").read_text()).get("profile", {})
    return [{"directory": directory, "name": item.get("name", directory),
             "google_account": item.get("user_name") or None,
             "google_account_name": item.get("gaia_name") or None,
             "exists": (data_dir / directory).is_dir(),
             "last_used_by_chrome": directory == state.get("last_used")}
            for directory, item in state.get("info_cache", {}).items()]


def selected_profile(data_dir, directory):
    try:
        return next(p for p in chrome_profiles(data_dir) if p["directory"] == directory)
    except (OSError, ValueError, StopIteration):
        return {"directory": directory, "name": directory, "google_account": None,
                "google_account_name": None, "metadata_available": False}


def command(*args, check=True):
    return subprocess.run(args, text=True, capture_output=True, check=check).stdout.strip()


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


def keyring_state():
    try:
        value = command("busctl", "--user", "get-property", "org.freedesktop.secrets",
                        "/org/freedesktop/secrets/aliases/default",
                        "org.freedesktop.Secret.Collection", "Locked")
        return {"b false": "unlocked", "b true": "locked"}.get(value, "unknown")
    except subprocess.CalledProcessError:
        return "unavailable"


def request_unlock():
    import secretstorage
    # gcr-prompter exits after inactivity. Start it on the right display only
    # when actually needed, rather than changing global D-Bus activation state.
    subprocess.Popen([os.environ["FARA_BROWSER_PROMPTER"]], env=session_environment(),
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(.2)
    print(json.dumps({"status": "awaiting_keyring_unlock", "viewer": "https://browser.internal",
                      "message": "Enter the keyring password in the shared desktop."}), flush=True)
    # Prompt objects belong to one D-Bus connection. The established library
    # keeps it alive until the human completes or dismisses the native dialog.
    with contextlib.closing(secretstorage.dbus_init()) as connection:
        secretstorage.Collection(connection).unlock(timeout=600)


def session_environment():
    path = RUNTIME / "environment"
    if not path.exists():
        raise RuntimeError("Start browser-desktop.service before using the browser.")
    # Read our own Bash-generated environment, without importing any credentials.
    data = command("bash", "-c", 'source "$1"; printf "%s\\n%s\\n" "$WAYLAND_DISPLAY" "$SWAYSOCK"',
                   "bash", str(path)).splitlines()
    env = dict(os.environ)
    env.pop("DISPLAY", None)
    env.update(WAYLAND_DISPLAY=data[0], SWAYSOCK=data[1], XDG_CURRENT_DESKTOP="sway")
    return env


def windows(env):
    tree = json.loads(subprocess.check_output(["swaymsg", "-t", "get_tree", "-r"], env=env))
    found = {}
    def visit(node):
        chrome_process = False
        if node.get("pid"):
            with contextlib.suppress(OSError):
                chrome_process = Path(os.readlink(f"/proc/{node['pid']}/exe")).name == "chrome"
        if chrome_process or node.get("app_id") == "google-chrome" or node.get("window_properties", {}).get("class") == "Google-chrome":
            found[node["id"]] = node
        for child in node.get("nodes", []) + node.get("floating_nodes", []):
            visit(child)
    visit(tree)
    return found


def ensure_chrome_on_display(data_dir, env):
    lock = data_dir / "SingletonLock"
    if not lock.is_symlink():
        return
    try:
        pid = int(os.readlink(lock).rsplit("-", 1)[1])
        # Chrome can sanitize its environment after starting. Sway's reported
        # client PID is authoritative for an existing window on this seat.
        if any(node.get("pid") == pid for node in windows(env).values()):
            return
        raw = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
        process_env = dict(item.split(b"=", 1) for item in raw if b"=" in item)
    except (ValueError, FileNotFoundError, ProcessLookupError):
        return  # Chrome itself decides whether a stale singleton lock is usable.
    if process_env.get(b"WAYLAND_DISPLAY", b"").decode() != env["WAYLAND_DISPLAY"]:
        raise RuntimeError("This Chrome installation is already running on another display. "
                           "Close its existing windows normally before opening its profiles in Sway; "
                           "the tool will not terminate that browser.")


KEYS = {"ctrl": "Control", "control": "Control", "alt": "Alt", "shift": "Shift",
        "super": "Meta", "win": "Meta", "cmd": "Meta", "esc": "Escape",
        "enter": "Enter", "tab": "Tab", "backspace": "Backspace", "delete": "Delete",
        "space": "Space", "arrowleft": "ArrowLeft", "arrowright": "ArrowRight",
        "arrowup": "ArrowUp", "arrowdown": "ArrowDown", "home": "Home", "end": "End",
        "pageup": "PageUp", "pagedown": "PageDown"}


class NoVNCEnvironment:
    """Duck-types upstream ComputerEnvironment, preserving its action semantics."""
    def __init__(self, runner):
        self.runner = runner
        self.page = None
        self.frame = None

    async def open(self):
        self.page = await self.runner.browser.new_page(viewport={"width": 1440, "height": 900}, device_scale_factor=1)
        await self.page.goto(self.runner.args.viewer_url.rstrip("/") + "/novnc/vnc.html?autoconnect=1&path=/vnc&resize=off&agent=1&view_only=0")
        await self.page.add_style_tag(content="#noVNC_control_bar_anchor {display:none!important}")
        await self.page.wait_for_function("document.documentElement.classList.contains('noVNC_connected')", timeout=15000)
        await asyncio.sleep(.25)

    async def close(self):
        if self.page:
            # The library releases held keys when disconnecting; then close the
            # transport so a cancelled inference cannot send another event.
            with contextlib.suppress(Exception):
                await self.page.evaluate("window.faraRfb()?.disconnect()")
            await self.page.close()
            self.page = None

    def check(self):
        if self.runner.owner != "agent":
            raise asyncio.CancelledError

    async def capture(self):
        self.check()
        encoded = await self.page.evaluate("window.faraRfb().toDataURL()")
        self.frame = base64.b64decode(encoded.split(",", 1)[1])
        return self.frame

    async def get_observation(self):
        return await self.capture()

    async def get_page_context(self):
        from fara.environments.computer import PageContext
        return PageContext("", "Full remote desktop through noVNC")

    async def get_page_markdown(self):
        return "DOM extraction is unavailable for this remote desktop. Read the screenshot and scroll as needed."

    async def mouse_move(self, x, y):
        self.check()
        await self.page.mouse.move(*self.point(x, y))

    @staticmethod
    def point(x, y):
        if not (0 <= x < 1440 and 0 <= y < 900):
            raise ValueError("Action coordinate is outside the captured desktop")
        return x, y

    async def click(self, x, y, button="left", count=1):
        self.check()
        await self.page.mouse.click(*self.point(x, y), button=button, click_count=count)

    async def left_click(self, x, y): await self.click(x, y)
    async def right_click(self, x, y): await self.click(x, y, "right")
    async def double_click(self, x, y): await self.click(x, y, count=2)
    async def triple_click(self, x, y): await self.click(x, y, count=3)

    async def left_click_drag(self, x, y):
        self.check()
        await self.page.mouse.down()
        try:
            await self.page.mouse.move(*self.point(x, y), steps=10)
        finally:
            await self.page.mouse.up()

    async def key(self, keys):
        self.check()
        mapped = [KEYS.get(k.lower(), k) for k in keys]
        try:
            for key in mapped:
                self.check()
                await self.page.keyboard.down(key)
        finally:
            for key in reversed(mapped):
                await self.page.keyboard.up(key)

    async def type(self, text):
        self.check()
        if len(text) > 16000:
            raise ValueError("Type action exceeds 16000 characters")
        # Use the upstream VNC clipboard, then a native paste. An arbitrary
        # Unicode keysym need not exist in the seat's keyboard layout; emitting
        # Enter per newline can also submit a form instead of entering text.
        if text:
            await self.page.evaluate("text => window.faraRfb().clipboardPasteFrom(text)", text)
            await asyncio.sleep(.15)
            await self.key(["ctrl", "v"])

    async def scroll(self, pixels):
        self.check()
        await self.page.mouse.wheel(0, -max(-9000, min(9000, pixels)))

    async def hscroll(self, pixels):
        self.check()
        await self.page.mouse.wheel(max(-9000, min(9000, pixels)), 0)

    async def wait(self, duration=1):
        self.check()
        await asyncio.sleep(max(0, min(float(duration), 30)))

    async def goto_url(self, url):
        if not url.startswith(("http://", "https://", "about:")):
            raise ValueError("Only browser URLs are supported")
        await self.key(["ctrl", "l"])
        await self.type(url)
        await self.key(["enter"])
        await asyncio.sleep(1)

    async def go_back(self): await self.key(["alt", "arrowleft"])
    async def wait_for_load(self): await self.wait(.4)


class Runner:
    def __init__(self, args):
        self.args = args
        self.profile = selected_profile(args.chrome_data_dir, args.profile)
        self.task_id = args.id or time.strftime("%Y%m%d-%H%M%S") + f"-{os.getpid()}"
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", self.task_id):
            raise ValueError("Task ID must use letters, numbers, underscores or hyphens")
        self.directory = RUNS / self.task_id
        self.owner = "human"
        self.phase = "starting"
        self.step = 0
        self.pending = ""
        self.model_action = None
        self.ready = asyncio.Event()
        self.env = NoVNCEnvironment(self)
        self.browser = None
        self.baseline = set()
        self.owned = set()
        self.desktop_env = session_environment()
        self.outcome = "interrupted"
        self.chrome_unit = None
        self.model_started = False
        self.lock = asyncio.Lock()

    def state(self):
        return {"task_id": self.task_id, "owner": self.owner, "phase": self.phase,
                "step": self.step, "run_dir": str(self.directory),
                "model": self.args.model, "endpoint": self.args.endpoint,
                "chrome_data_dir": str(self.args.chrome_data_dir.resolve()),
                "profile_at_start": self.profile,
                "profile_now": selected_profile(self.args.chrome_data_dir, self.args.profile)}

    def record(self, event, **data):
        with (self.directory / "lifecycle.jsonl").open("a") as stream:
            stream.write(json.dumps({"time": time.time(), "event": event, "step": self.step, **data}, ensure_ascii=False) + "\n")
        write_json(self.directory / "state.json", self.state())

    async def pause(self):
        async with self.lock:
            self.owner = "human"
            self.phase = "pausing"
            self.ready.clear()
            if self.model_action:
                self.model_action.cancel()
            await self.env.close()
            if self.model_action:
                with contextlib.suppress(asyncio.CancelledError):
                    await self.model_action
            self.phase = "paused"
            self.record("paused")

    async def resume(self, message):
        async with self.lock:
            if self.owner == "agent":
                raise ValueError("Task is already running")
            if self.browser is None:
                raise ValueError("The browser is still starting; resume when it is ready")
            if keyring_state() != "unlocked":
                raise ValueError("Unlock the keyring in the desktop before resuming")
            await self.env.open()
            self.pending = message or "The user finished taking control. Observe the current desktop before continuing."
            self.owner = "agent"
            self.phase = "running"
            self.record("resumed", message=self.pending)
            self.ready.set()

    async def controls(self):
        from aiohttp import web
        app = web.Application(client_max_size=65536)
        async def state(_request): return web.json_response(self.state())
        async def change(request):
            if request.headers.get("X-Fara-Control") != "1":
                raise web.HTTPForbidden()
            origin = request.headers.get("Origin")
            if origin and origin != self.args.viewer_url.rstrip("/"):
                raise web.HTTPForbidden()
            action = request.match_info["action"]
            try:
                if action == "pause": await self.pause()
                elif action == "resume": await self.resume((await request.json()).get("message", ""))
                elif action == "cancel":
                    await self.pause()
                    self.outcome = "cancelled"
                    self.main_task.cancel()
                else: raise web.HTTPNotFound()
            except ValueError as exc:
                return web.json_response({"error": str(exc)}, status=409)
            return web.json_response(self.state())
        app.router.add_get("/state", state)
        app.router.add_post("/{action}", change)
        runner = web.AppRunner(app, access_log=None)
        await runner.setup()
        await web.TCPSite(runner, "127.0.0.1", 4782).start()
        return runner

    async def run(self):
        from playwright.async_api import async_playwright
        from fara.agents.fara.fara15_agent import Fara15Agent, Fara15AgentConfig
        from fara.core.run_context import RunContext
        from fara.core.data_point import Task, SolverStatus, UserMessage, UserMessageType
        from tenacity import retry_if_exception_type
        self.directory.mkdir(parents=True, exist_ok=False)
        task = self.args.task_file.read_text()
        (self.directory / "task.txt").write_text(task)
        task = ("Selected Chrome profile (recorded browser metadata, not proof of the website login): "
                + json.dumps(self.profile, ensure_ascii=False)
                + "\nVerify the requested website identity before acting.\n\n" + task)
        self.main_task = asyncio.current_task()
        server = await self.controls()
        self.record("started", profile=self.profile, model=self.args.model, endpoint=self.args.endpoint,
                    upstream="microsoft/fara@a675d6d61c41c47ae87bacefeab22caad18e3e84")
        print(json.dumps(self.state()), flush=True)
        runner = self
        class DesktopFara(Fara15Agent):
            # Upstream retries CancelledError, delaying takeover and starting
            # another inference. Keep its retry policy for ordinary errors only.
            _make_model_call = Fara15Agent._make_model_call.retry_with(
                retry=Fara15Agent._make_model_call.retry.retry & retry_if_exception_type(Exception))

            # Keep upstream run(), prompting, parsing, dispatch and recording.
            # Snapshot only at an inference boundary so interrupted work can be
            # resumed with a new screenshot and explicit user feedback.
            async def _generate_model_call(self, *args, **kwargs):
                runner.saved_state = copy.deepcopy(self._state)
                runner.step = self._state.current_step + 1
                runner.phase = "thinking"
                runner.record("inference")
                return await super()._generate_model_call(*args, **kwargs)

            async def _execute_action(self, env, calls):
                env.check()
                runner.phase = "acting"
                runner.record("executing")
                if calls[0].arguments.get("action") == "read_page_answer_question":
                    self._pending_observation = "DOM extraction is unavailable through noVNC. Read the screenshot and scroll as needed."
                    return False, self._pending_observation
                try:
                    return await super()._execute_action(env, calls)
                finally:
                    runner.owned.update(set(windows(runner.desktop_env)) - runner.baseline)

        context = RunContext.create(self.env, Task(task_id=self.task_id, instruction=task),
                                    self.directory, run_id=self.task_id)
        agent = DesktopFara(Fara15AgentConfig(
            client_config={"base_url": self.args.endpoint, "model": self.args.model, "api_key": "not-needed"},
            max_rounds=self.args.max_steps, captcha_timeout_limit=0,
            max_n_images=3, extra_create_args={"max_tokens": 4096,
                "extra_body": {"chat_template_kwargs": {"enable_thinking": False}}},
        ))
        try:
            await agent.initialize(context)
            ensure_chrome_on_display(self.args.chrome_data_dir, self.desktop_env)
            from aiohttp import ClientSession
            async with ClientSession() as client:
                health = self.args.endpoint.removesuffix("/v1") + "/health"
                try:
                    async with client.get(health) as response:
                        available = response.status == 200
                except Exception:
                    available = False
                if not available:
                    if self.args.endpoint != "http://127.0.0.1:8732/v1" or self.args.model != "Fara1.5-9B":
                        raise RuntimeError("The selected local FARA endpoint is unavailable. Automatic startup is configured only for Fara1.5-9B at port 8732.")
                    self.model_started = command("systemctl", "--user", "is-active", "fara-browser-model", check=False) != "active"
                    if self.model_started:
                        TASK_MODEL.touch(mode=0o600)
                    command("systemctl", "--user", "start", "fara-browser-model")
                    self.phase = "loading_model"
                    self.record("loading_model")
                    for _ in range(180):
                        try:
                            async with client.get(health) as response:
                                if response.status == 200: break
                        except Exception:
                            pass
                        await asyncio.sleep(1)
                    else:
                        raise RuntimeError("FARA model did not become ready within three minutes")
                async with client.get(self.args.endpoint.rstrip("/") + "/models") as response:
                    response.raise_for_status()
                    available_models = [item["id"] for item in (await response.json())["data"]]
                if self.args.model not in available_models:
                    raise RuntimeError(f"Requested model {self.args.model!r} is not advertised by this endpoint: {available_models}")
            self.baseline = set(windows(self.desktop_env))
            self.chrome_unit = f"browser-chrome-task-{os.getpid()}.service"
            write_json(TASK_LEASE, {"baseline": sorted(self.baseline), "unit": self.chrome_unit})
            launch_chrome(self.args.chrome_data_dir, self.args.profile, self.desktop_env, unit=self.chrome_unit)
            for _ in range(100):
                self.owned = set(windows(self.desktop_env)) - self.baseline
                if self.owned: break
                await asyncio.sleep(.1)
            if len(self.owned) != 1:
                raise RuntimeError("Could not identify exactly one new task window")
            window_id = next(iter(self.owned))
            command("swaymsg", "-s", self.desktop_env["SWAYSOCK"], f"[con_id={window_id}] focus")
            # Sway-forced fullscreen hides Chrome's address bar and suppresses
            # its navigation shortcuts. Cover the output with a normal window.
            command("swaymsg", "-s", self.desktop_env["SWAYSOCK"], f"[con_id={window_id}] floating enable")
            command("swaymsg", "-s", self.desktop_env["SWAYSOCK"], f"[con_id={window_id}] resize set width 1440 px height 900 px")
            command("swaymsg", "-s", self.desktop_env["SWAYSOCK"], f"[con_id={window_id}] move position 0 0")
            async with async_playwright() as playwright:
                self.browser = await playwright.chromium.launch(
                    executable_path=os.environ["FARA_BROWSER_CHROME"], headless=True,
                    chromium_sandbox=True, args=["--disable-gpu"])
                if self.phase != "paused":
                    await self.resume(task)
                else:
                    self.record("ready_for_resume")
                while agent._state.current_step < self.args.max_steps:
                    await self.ready.wait()
                    if self.pending:
                        context.add_observation(UserMessage(content=self.pending,
                            message_type=UserMessageType.CRITICAL_POINT_RESPONSE))
                        self.pending = ""
                    self.model_action = asyncio.create_task(agent.run(context))
                    try:
                        answer, _, _ = await self.model_action
                    except asyncio.CancelledError:
                        if self.main_task.cancelling(): raise
                        if hasattr(self, "saved_state"):
                            agent._state = self.saved_state
                            # Preserve interrupted evidence filenames. The resumed
                            # inference uses a new step and a fresh observation.
                            agent._state.current_step = self.step
                        self.record("action_interrupted")
                        context.checkpoint()
                        continue
                    finally:
                        self.model_action = None
                    if context.solver_log.status == SolverStatus.WAITING_FOR_USER:
                        await self.pause()
                        self.record("needs_user", question=answer)
                        print(json.dumps({"task_id": self.task_id, "needs_user": answer}), flush=True)
                        continue
                    actions = [e for e in context.solver_log.events if getattr(e, "type", "") == "action"]
                    self.outcome = "completed" if actions and actions[-1].action_name == "terminate" else "step_limit"
                    self.record(self.outcome, answer=answer)
                    break
                else:
                    self.outcome = "step_limit"
                await self.env.close()
                await self.browser.close()
        except asyncio.CancelledError:
            self.outcome = "cancelled"
            self.record("cancelled")
        except Exception as exc:
            self.outcome = "error"
            self.record("error", error=str(exc))
            raise
        finally:
            self.owner = "human"
            self.ready.clear()
            with contextlib.suppress(Exception): await self.env.close()
            # Task windows are tracked independently of Chrome's shared process.
            # Never kill the entire browser or touch windows predating this run.
            if self.chrome_unit:
                self.owned.update(set(windows(self.desktop_env)) - self.baseline)
            for window_id in self.owned:
                command("swaymsg", "-s", self.desktop_env["SWAYSOCK"], f"[con_id={window_id}] kill", check=False)
            remaining = set()
            for _ in range(30):
                remaining = self.owned & set(windows(self.desktop_env))
                if not remaining: break
                await asyncio.sleep(.1)
            if remaining:
                self.outcome = "cleanup_failed"
                self.record("cleanup_failed", window_ids=sorted(remaining))
            elif self.chrome_unit:
                command("systemctl", "--user", "stop", self.chrome_unit, check=False)
            if not remaining:
                TASK_LEASE.unlink(missing_ok=True)
            context.checkpoint()
            await agent.close(context)
            self.phase = self.outcome
            self.record("finished", outcome=self.outcome)
            make_replay(self.directory)
            await server.cleanup()
            if self.model_started:
                command("systemctl", "--user", "stop", "fara-browser-model", check=False)
            print(json.dumps(self.state()), flush=True)


def make_replay(directory):
    events = []
    native = directory / "solver_log/events.jsonl"
    if native.exists():
        events = [json.loads(line) for line in native.read_text().splitlines()]
    lifecycle = directory / "lifecycle.jsonl"
    if lifecycle.exists():
        events.extend(json.loads(line) for line in lifecycle.read_text().splitlines())
    def event_time(event):
        if "time" in event:
            return event["time"]
        return datetime.fromisoformat(event["timestamp"]).timestamp()
    events.sort(key=event_time)
    for event in events:
        if event.get("screenshot_path"):
            event["image"] = event["screenshot_path"]
    payload = json.dumps(events, ensure_ascii=False).replace("<", "\\u003c")
    template = (ASSETS / "replay.html").read_text()
    (directory / "replay.html").write_text(template.replace("__EVENTS__", payload).replace("__TASK__", html.escape(directory.name)))


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    sub.add_parser("keyring")
    sub.add_parser("unlock")
    profiles = sub.add_parser("profiles")
    profiles.add_argument("--chrome-data-dir", type=Path, default=Path.home()/".config/google-chrome")
    run = sub.add_parser("run")
    run.add_argument("--profile", required=True, help="Existing Chrome directory name, e.g. Default or Profile 2")
    run.add_argument("--task-file", type=Path, required=True)
    run.add_argument("--id")
    run.add_argument("--max-steps", type=int, default=30)
    run.add_argument("--viewer-url", default="https://browser.internal")
    run.add_argument("--endpoint", default="http://127.0.0.1:8732/v1")
    run.add_argument("--model", default="Fara1.5-9B", help="Served model ID for Fara 1.5 4B, 9B or 27B; must match /v1/models")
    run.add_argument("--chrome-data-dir", type=Path, default=Path.home()/".config/google-chrome")
    sub.add_parser("pause")
    sub.add_parser("cancel")
    resume = sub.add_parser("resume")
    resume.add_argument("--message-file", type=Path, required=True)
    args = parser.parse_args()
    if args.command in ("keyring", "unlock"):
        if args.command == "unlock" and keyring_state() == "locked":
            start_desktop(manual=True)
            request_unlock()
        print(json.dumps({"keyring": keyring_state(), "viewer": "https://browser.internal"}))
        return
    if args.command == "profiles":
        active = None
        try:
            with urllib.request.urlopen(CONTROL + "/state", timeout=2) as response:
                active = json.load(response)
        except OSError:
            pass
        profiles = chrome_profiles(args.chrome_data_dir)
        for profile in profiles:
            profile["fara_task_id"] = (active["task_id"] if active
                and active.get("chrome_data_dir") == str(args.chrome_data_dir.resolve())
                and active.get("profile_at_start", {}).get("directory") == profile["directory"] else None)
        print(json.dumps(profiles, ensure_ascii=False))
        return
    if args.command in ("status", "pause", "resume", "cancel"):
        url = CONTROL + ("/state" if args.command == "status" else "/" + args.command)
        data = None if args.command == "status" else json.dumps({
            "message": args.message_file.read_text() if args.command == "resume" else ""
        }).encode()
        req = urllib.request.Request(url, data=data, headers={"X-Fara-Control": "1", "Content-Type": "application/json"})
        try:
            print(urllib.request.urlopen(req, timeout=20).read().decode())
        except urllib.error.HTTPError as exc:
            print(exc.read().decode(), file=sys.stderr)
            return 1
        except OSError:
            print(json.dumps({"status": "idle", **desktop_status(), "keyring": keyring_state(), "viewer": "https://browser.internal"}))
            if args.command != "status": raise
        return
    if not (1 <= args.max_steps <= 200): parser.error("--max-steps must be between 1 and 200")
    if Path(args.profile).name != args.profile or args.profile in (".", ".."):
        parser.error("--profile must be an existing Chrome profile directory")
    if not (args.chrome_data_dir / args.profile).is_dir():
        parser.error("Profile does not exist; use fara-browser profiles")
    if urlparse(args.endpoint).hostname not in ("localhost", "127.0.0.1", "::1"):
        parser.error("FARA inference must stay local")
    if keyring_state() != "unlocked":
        if keyring_state() == "locked":
            start_desktop(manual=True)
            request_unlock()
        print(json.dumps({"status": "needs_keyring_unlock", "viewer": "https://browser.internal",
                          "message": "Unlock the desktop keyring in the browser window, then rerun this command."}))
        return 3
    RUNTIME.mkdir(parents=True, exist_ok=True)
    with (RUNTIME / "task.lock").open("w") as lock:
        try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError: parser.error("Another FARA task is running")
        start_desktop()
        runner = None
        async def execute():
            task = asyncio.current_task()
            loop = asyncio.get_running_loop()
            for sig in (signal.SIGTERM, signal.SIGINT): loop.add_signal_handler(sig, task.cancel)
            await runner.run()
        try:
            runner = Runner(args)
            asyncio.run(execute())
        finally:
            if runner and runner.model_started:
                command("systemctl", "--user", "stop", "fara-browser-model", check=False)
            TASK_MODEL.unlink(missing_ok=True)
            if not MANUAL.exists():
                stop_desktop()
                TASK_LEASE.unlink(missing_ok=True)
        return 0 if runner.outcome == "completed" else 1


if __name__ == "__main__":
    try: sys.exit(main())
    except Exception as exc:
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        sys.exit(1)
