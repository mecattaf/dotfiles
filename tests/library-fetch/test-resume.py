"""Exercise the real fetcher against interrupted and corrupt local HTTP responses."""

import hashlib
import http.server
import json
import os
import subprocess
import sys
import tempfile
import threading
from pathlib import Path


payload = bytes(range(256)) * 4096
oid = hashlib.sha256(payload).hexdigest()
requests = []
mode = {"fail": False, "cut": True}


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        offset = int(self.headers.get("Range", "bytes=0-").split("=")[1].split("-")[0])
        requests.append(offset)
        if mode["fail"]:
            self.send_error(404)
            return
        self.send_response(206 if offset else 200)
        if offset:
            self.send_header("Content-Range", f"bytes {offset}-{len(payload)-1}/{len(payload)}")
        self.send_header("Content-Length", str(len(payload) - offset))
        self.send_header("Connection", "close")
        self.end_headers()
        if mode["cut"]:
            mode["cut"] = False
            self.wfile.write(payload[offset : offset + 65536])
            self.wfile.flush()
            self.close_connection = True
            return
        self.wfile.write(payload[offset:])


with tempfile.TemporaryDirectory(prefix="library-fetch-resume-") as temporary:
    root = Path(temporary)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    weights = root / "weights"
    artifact = weights / "fixture"
    artifact.mkdir(parents=True)
    partial = artifact / "fixture.gguf.part"
    final = artifact / "fixture.gguf"
    partial.write_bytes(payload[:262144])
    manifest = root / "manifest.json"
    row = [{"id": "fixture", "files": [{"name": "fixture.gguf", "bytes": len(payload), "oid": oid, "url": f"http://127.0.0.1:{server.server_port}/fixture"}]}]
    manifest.write_text(json.dumps(row))
    environment = dict(os.environ, LIBRARY_FETCH_MANIFEST=str(manifest), LIBRARY_FETCH_WEIGHTS=str(weights))

    def run():
        return subprocess.run([sys.argv[1]], env=environment, capture_output=True, text=True, timeout=90)

    success = run()
    assert success.returncode == 0, success.stderr
    assert requests[:2] == [262144, 327680], requests
    assert final.read_bytes() == payload
    assert not partial.exists()

    final.unlink()
    partial.write_bytes(payload[:262144])
    mode["fail"] = True
    failed = run()
    assert failed.returncode != 0
    assert partial.read_bytes() == payload[:262144], "failed fetch discarded resumable bytes"
    assert not final.exists(), "failed transfer landed as a complete model"

    mode["fail"] = False
    row[0]["files"][0]["oid"] = "0" * 64
    manifest.write_text(json.dumps(row))
    corrupt = run()
    assert corrupt.returncode != 0
    assert "HASH MISMATCH" in corrupt.stderr
    assert not final.exists(), "corrupt transfer landed as a complete model"
    assert not partial.exists(), "known-bad bytes were retained for resume"
    server.shutdown()

print("PASS: interrupted resume, retained failed partial, rejected corrupt payload")
