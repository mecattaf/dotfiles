"""Fixed NAS-to-Zenbook operations. No commands, URLs or focus arguments."""
import ipaddress
import json
import os
from pathlib import Path
import re
import shlex
import signal
import stat
import subprocess
import time
import uuid

NAMES = {"domicile_open_terminal": "terminal", "domicile_open_chat": "chat"}
CODES = {"ok", "invalid-arguments", "unavailable", "not-ready", "busy", "locked-or-modal",
         "no-workspace", "request-conflict", "outcome-unknown", "cancelled"}

def failure(request, code):
    return dict(ok=False, code=code, desktop=request.get("desktop", ""),
                requestId=request.get("requestId", ""), kind=request.get("kind", ""),
                windowId=None, workspace=None, focusChanged=False,
                workspaceChanged=False, retryAutomatically=False)

def validate(request, desktops):
    if not isinstance(request, dict) or request.get("kind") not in ("terminal", "chat"):
        raise ValueError("invalid-arguments")
    field = "cwd" if request["kind"] == "terminal" else "sessionId"
    if set(request) != {"desktop", "requestId", "kind", field} or request["desktop"] not in desktops:
        raise ValueError("invalid-arguments")
    if not isinstance(request["requestId"], str) or str(uuid.UUID(request["requestId"])) != request["requestId"]:
        raise ValueError("invalid-arguments")
    value = request[field]
    if not isinstance(value, str) or not value or len(value.encode()) > 4096 or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ValueError("invalid-arguments")
    if field == "cwd" and not Path(value).is_absolute():
        raise ValueError("invalid-arguments")
    if field == "sessionId" and not re.fullmatch(r"session-[A-Za-z0-9-]{1,100}", value):
        raise ValueError("invalid-arguments")
    return request

def tools(desktops):
    return [dict(name=name, description=(
        "Open one fresh NAS project terminal" if kind == "terminal" else "Open a Chrome viewer of an existing DSH chat; do not send a prompt") +
        " on an allowed desktop without taking focus or switching its workspace. Requires the prepared Imagine agent-window handler; unavailable has no launch fallback. Use a stable UUID requestId for retries; never automatically retry an unknown outcome.",
        inputSchema=dict(type="object", additionalProperties=False,
            required=["desktop", "requestId", "cwd" if kind == "terminal" else "sessionId"],
            properties={"desktop": dict(type="string", enum=desktops), "requestId": dict(type="string", format="uuid"),
                        "cwd" if kind == "terminal" else "sessionId": dict(type="string")}),
        annotations=dict(readOnlyHint=False, destructiveHint=False, idempotentHint=True, openWorldHint=False))
        for name, kind in NAMES.items()]

def ssh_command(record):
    peer = ipaddress.ip_address(record["tailnetIp"])
    if peer not in ipaddress.ip_network("100.64.0.0/10"):
        raise ValueError("unavailable")
    for key in ("sshAlias", "hostKeyAlias"):
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", record[key]):
            raise ValueError("unavailable")
    helper = record["agentWindowLauncher"]
    if not Path(helper).is_absolute() or any(ord(c) < 32 for c in helper):
        raise ValueError("unavailable")
    args = ["/run/current-system/sw/bin/ssh"]
    if "sshConfig" in record:
        p = Path(record["sshConfig"]); s = p.lstat()
        if not p.is_absolute() or not stat.S_ISREG(s.st_mode) or s.st_uid != os.getuid() or stat.S_IMODE(s.st_mode) != 0o600:
            raise ValueError("unavailable")
        args += ["-F", str(p)]
    return args + ["-T", "-S", "none", "-oControlMaster=no", "-oBatchMode=yes",
        "-oStrictHostKeyChecking=yes", "-oForwardAgent=no", "-oClearAllForwardings=yes",
        "-oConnectTimeout=5", "-oServerAliveInterval=10", "-oServerAliveCountMax=2",
        f"-oHostName={peer}", f"-oHostKeyAlias={record['hostKeyAlias']}", record["sshAlias"], shlex.join([helper])]

def run(registry, request, cancel=None):
    try:
        validate(request, registry["desktops"])
        if request["kind"] == "terminal" and not Path(request["cwd"]).is_dir():
            return failure(request, "invalid-arguments")
        child = subprocess.Popen(ssh_command(registry["desktops"][request["desktop"]]),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        payload = json.dumps(request).encode()
        deadline = time.monotonic() + 115
        while True:
            try:
                out, _ = child.communicate(payload, timeout=.2)
                break
            except subprocess.TimeoutExpired:
                payload = None
                if (cancel and cancel.is_set()) or time.monotonic() >= deadline:
                    os.killpg(child.pid, signal.SIGTERM)
                    try: child.communicate(timeout=.5)
                    except subprocess.TimeoutExpired:
                        os.killpg(child.pid, signal.SIGKILL); child.communicate()
                    return failure(request, "cancelled" if cancel and cancel.is_set() else "outcome-unknown")
        if child.returncode or len(out) > 16384:
            return failure(request, "unavailable")
        value = json.loads(out)
        if set(value) != set(failure(request, "unavailable")) or value["code"] not in CODES:
            return failure(request, "unavailable")
        if any(value[k] != request[k] for k in ("desktop", "requestId", "kind")):
            return failure(request, "unavailable")
        if value["focusChanged"] is not False or value["workspaceChanged"] is not False or value["retryAutomatically"] is not False:
            return failure(request, "unavailable")
        if value["ok"] is not (value["code"] == "ok"):
            return failure(request, "unavailable")
        if value["ok"] and (not isinstance(value["windowId"], str) or not isinstance(value["workspace"], str)):
            return failure(request, "unavailable")
        return value
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        return failure(request if isinstance(request, dict) else {}, "unavailable")
