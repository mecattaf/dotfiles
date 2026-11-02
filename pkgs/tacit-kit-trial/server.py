#!/usr/bin/env python3
"""Loopback controller for four fixed, native Tacit Kit examples."""
import argparse
import atexit
import hmac
import json
import os
from pathlib import Path
import secrets
import shutil
import signal
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parent
DEMOS = {
    "controls": "Controls",
    "lists": "Lists and search",
    "actions": "Actions and feedback",
    "navigation": "Tabs, menus and panels",
}


class Trial:
    def __init__(self, qs, kit):
        self.qs = qs
        self.kit = Path(kit)
        self.directory = tempfile.TemporaryDirectory(prefix="tacit-kit-trial-")
        self.state = Path(self.directory.name)
        self.children = {}
        self.lock = threading.RLock()
        self.palette = "dusk"
        self.reduced = False
        self.write_palette()

    def write_palette(self):
        target = self.state / "quickshell/user/generated/colors.json"
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_suffix(".tmp")
        shutil.copyfile(self.kit / "tools/palettes" / (self.palette + ".json"), temporary)
        temporary.replace(target)

    def ipc(self, kind, function, *args):
        result = subprocess.run(
            [self.qs, "ipc", "--pid", str(self.children[kind][0].pid),
             "call", "trial", function, *args],
            capture_output=True, text=True, timeout=2,
        )
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "Native window did not answer")
        return result.stdout.strip()

    def stop(self, kind):
        with self.lock:
            child = self.children.pop(kind, None)
            if child:
                process, stream = child
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=3)
                stream.close()

    def spawn(self, kind):
        if kind not in DEMOS:
            raise ValueError("Unknown example")
        with self.lock:
            if kind in self.children and self.children[kind][0].poll() is None:
                return
            self.stop(kind)
            env = os.environ.copy()
            env.update(QML_IMPORT_PATH=str(self.kit / "qml") + ":" + env.get("QML_IMPORT_PATH", ""),
                       XDG_STATE_HOME=str(self.state),
                       TACIT_REDUCED_MOTION="1" if self.reduced else "0")
            stream = (self.state / (kind + ".log")).open("w")
            process = subprocess.Popen([self.qs, "-p", str(ROOT / "qml" / (kind + ".qml"))],
                                       env=env, stdin=subprocess.DEVNULL, stdout=stream, stderr=subprocess.STDOUT)
            self.children[kind] = process, stream
            error = "Native window did not become ready"
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    break
                try:
                    snapshot = json.loads(self.ipc(kind, "snapshot"))
                    if snapshot.get("visible"):
                        return
                except (RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
                    error = str(exc)
                time.sleep(0.1)
            self.stop(kind)
            log = (self.state / (kind + ".log")).read_text()[-5000:]
            raise RuntimeError(error + "\n" + log)

    def status(self):
        with self.lock:
            windows = []
            for kind, title in DEMOS.items():
                row = dict(id=kind, title=title, running=False)
                child = self.children.get(kind)
                if child and child[0].poll() is None:
                    try:
                        snapshot = json.loads(self.ipc(kind, "snapshot"))
                        row.update(running=bool(snapshot.get("visible")), native=snapshot)
                        if not row["running"]:
                            self.stop(kind)
                    except (RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
                        row["error"] = str(exc)
                elif child:
                    row["exitCode"] = child[0].returncode
                    row["log"] = (self.state / (kind + ".log")).read_text()[-3000:]
                    self.stop(kind)
                windows.append(row)
            return dict(windows=windows, palette=self.palette, reducedMotion=self.reduced,
                        kitRevision="f34574dae85aec2eb9e8835cc1dfece87cdfdf2d")

    def configure(self, palette, reduced):
        if palette not in ("dusk", "moss") or not isinstance(reduced, bool):
            raise ValueError("Choose dusk or moss and a boolean motion setting")
        with self.lock:
            self.palette, self.reduced = palette, reduced
            self.write_palette()
            for kind, (process, _) in self.children.items():
                if process.poll() is None:
                    self.ipc(kind, "motion", "true" if reduced else "false")

    def close(self):
        with self.lock:
            for kind in list(self.children):
                self.stop(kind)
            self.directory.cleanup()


def handler_for(trial, port, token):
    class Handler(BaseHTTPRequestHandler):
        def reply(self, status, body, content_type="application/json"):
            data = json.dumps(body).encode() if content_type == "application/json" else body.encode()
            self.send_response(status)
            self.send_header("Content-Type", content_type + "; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'nonce-" + token + "'; style-src 'unsafe-inline'; font-src 'self'; frame-ancestors 'none'; base-uri 'none'")
            self.end_headers()
            self.wfile.write(data)

        def valid_host(self):
            return self.headers.get("Host") in (f"localhost:{port}", f"127.0.0.1:{port}")

        def do_GET(self):
            if not self.valid_host():
                return self.reply(403, {"error": "Use the localhost address"})
            if self.path == "/":
                return self.reply(200, (ROOT / "index.html").read_text().replace("__TOKEN__", token), "text/html")
            if self.path == "/api/status":
                return self.reply(200, trial.status())
            if self.path.startswith("/source/"):
                name = self.path.removeprefix("/source/")
                if name in DEMOS or name == "DemoWindow":
                    return self.reply(200, (ROOT / "qml" / (name + ".qml")).read_text(), "text/plain")
            if self.path == "/font.ttf":
                data = (trial.kit / "qml/Tacit/Kit/fonts/TacitSans.ttf").read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "font/ttf")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            self.reply(404, {"error": "Not found"})

        def do_POST(self):
            if not self.valid_host() or not hmac.compare_digest(self.headers.get("X-Trial-Token", ""), token):
                return self.reply(403, {"error": "Reload the local walkthrough page"})
            if self.headers.get("Origin") not in (None, f"http://127.0.0.1:{port}", f"http://localhost:{port}"):
                return self.reply(403, {"error": "Local requests only"})
            try:
                size = int(self.headers.get("Content-Length", "0"))
                if not 0 < size <= 2048 or self.headers.get_content_type() != "application/json":
                    return self.reply(400, {"error": "Expected a small JSON request"})
                body = json.loads(self.rfile.read(size))
                if not isinstance(body, dict):
                    raise ValueError("Expected an object")
                if self.path in ("/api/spawn", "/api/close"):
                    kind = body.get("id")
                    if kind not in DEMOS:
                        raise ValueError("Unknown example")
                    (trial.spawn if self.path == "/api/spawn" else trial.stop)(kind)
                elif self.path == "/api/close-all":
                    for kind in DEMOS:
                        trial.stop(kind)
                elif self.path == "/api/settings":
                    trial.configure(body.get("palette"), body.get("reducedMotion"))
                else:
                    return self.reply(404, {"error": "Not found"})
                self.reply(200, trial.status())
            except (ValueError, TypeError) as exc:
                self.reply(400, {"error": str(exc)})
            except (RuntimeError, subprocess.TimeoutExpired) as exc:
                self.reply(502, {"error": str(exc)})

        def log_message(self, fmt, *args):
            if not args or str(args[1]) != "200":
                super().log_message(fmt, *args)
    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error("port must be between 1024 and 65535")
    if not os.environ.get("WAYLAND_DISPLAY") and os.environ.get("QT_QPA_PLATFORM") != "offscreen":
        parser.error("Run from the Zenbook's Wayland desktop session")
    trial = Trial(os.environ.get("TACIT_QS", "qs"), os.environ["TACIT_KIT"])
    atexit.register(trial.close)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler_for(trial, args.port, secrets.token_hex(24)))
    server.daemon_threads = False
    def shutdown(*_):
        threading.Thread(target=server.shutdown, daemon=True).start()
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    print(f"Tacit Kit walkthrough: http://localhost:{args.port}", flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()
        trial.close()


if __name__ == "__main__":
    main()
