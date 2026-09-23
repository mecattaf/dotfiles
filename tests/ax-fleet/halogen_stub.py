#!/usr/bin/env python3
"""Halogen stand-in for the ax-fleet VM test (DESIGN.md 12.1, node `worker`).

OpenAI-compatible enough for the ax task image's two model paths:
  - `halogen-smoke`: one non-streaming POST /v1/chat/completions (curl);
  - `pi`: streaming POST /v1/chat/completions (SSE, `data: {...}` chunks, then
    `data: [DONE]`).
Also GET /v1/models and GET /health, like the real server.

Every request is appended to --log as one JSON line with the source address
and a per-request id, so the test can prove that sandbox traffic arrived
SNAT'd from the NAS (10.42.0.1) and count requests per Task.
"""

import argparse
import json
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODEL = "halogen-qwen3.8-flash-next"
REPLY = "halogen-stub-ok"
# The pi mode asks for one JSON object against a JSON Schema in its system
# prompt; the adapter's default schema wants {"answer": <integer>}.
JSON_REPLY = '{"answer": 42}'


def reply_for(req):
    """REPLY, or JSON_REPLY when any message mentions a JSON Schema."""
    for msg in req.get("messages") or []:
        content = msg.get("content") if isinstance(msg, dict) else None
        if isinstance(content, list):
            content = " ".join(str(p.get("text", "")) for p in content if isinstance(p, dict))
        if isinstance(content, str) and "JSON Schema" in content:
            return JSON_REPLY
    return REPLY
LOCK = threading.Lock()

# probe/ax-fleet-nop1: a stand-in floor. A Task's command POSTs its own
# completion to /floor/complete (the in-sandbox adapter reporting straight to
# the floor, LINK-DESIGN L7); the test driver, standing in for the link, reads
# GET /floor/results and then deletes the Task. Every POST is kept, so a
# golden-snapshot pre-run of the command would show as a second report.
FLOOR = []


def make_handler(log_path):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):  # quiet stderr; the jsonl is the log
            pass

        def _record(self, body):
            entry = {
                "id": uuid.uuid4().hex,
                "ts": time.time(),
                "src": self.client_address[0],
                "method": self.command,
                "path": self.path,
                "bytes": len(body),
            }
            with LOCK, open(log_path, "a", encoding="utf-8") as f:
                f.write(json.dumps(entry) + "\n")
            return entry["id"]

        def _json(self, code, obj):
            data = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            rid = self._record(b"")
            if self.path.rstrip("/") == "/floor/results":
                with LOCK:
                    self._json(200, {"reports": list(FLOOR)})
                return
            if self.path.rstrip("/") == "/health":
                self._json(200, {"status": "ok", "in_flight": 0, "queued": 0, "request_id": rid})
            elif self.path.rstrip("/") == "/v1/models":
                self._json(200, {"object": "list", "data": [{"id": MODEL, "object": "model", "owned_by": "halogen"}]})
            else:
                self._json(404, {"error": "not found", "request_id": rid})

        def do_POST(self):
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length) if length else b""
            rid = self._record(body)
            if self.path.rstrip("/") == "/floor/complete":
                try:
                    report = json.loads(body or b"{}")
                except json.JSONDecodeError:
                    self._json(400, {"error": "bad json", "request_id": rid})
                    return
                with LOCK:
                    FLOOR.append({"received": time.time(), "src": self.client_address[0], "request_id": rid, "report": report})
                    n = len(FLOOR)
                self._json(200, {"ok": True, "request_id": rid, "n": n})
                return
            if self.path.rstrip("/") != "/v1/chat/completions":
                self._json(404, {"error": "not found", "request_id": rid})
                return
            try:
                req = json.loads(body or b"{}")
            except json.JSONDecodeError:
                self._json(400, {"error": "bad json", "request_id": rid})
                return
            created = int(time.time())
            cid = "chatcmpl-" + rid
            if not req.get("stream"):
                self._json(
                    200,
                    {
                        "id": cid,
                        "object": "chat.completion",
                        "created": created,
                        "model": MODEL,
                        "choices": [
                            {
                                "index": 0,
                                "message": {"role": "assistant", "content": reply_for(req)},
                                "finish_reason": "stop",
                            }
                        ],
                        "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2},
                    },
                )
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()
            chunks = [
                {"role": "assistant", "content": ""},
                {"content": reply_for(req)},
            ]
            for i, delta in enumerate(chunks + [None]):
                choice = {"index": 0, "delta": delta or {}, "finish_reason": None if delta else "stop"}
                obj = {"id": cid, "object": "chat.completion.chunk", "created": created, "model": MODEL, "choices": [choice]}
                if delta is None:
                    obj["usage"] = {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}
                self.wfile.write(b"data: " + json.dumps(obj).encode() + b"\n\n")
                self.wfile.flush()
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
            self.close_connection = True

    return Handler


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8731)
    ap.add_argument("--log", default="/tmp/halogen-stub.jsonl")
    args = ap.parse_args()
    ThreadingHTTPServer(("0.0.0.0", args.port), make_handler(args.log)).serve_forever()


if __name__ == "__main__":
    main()
