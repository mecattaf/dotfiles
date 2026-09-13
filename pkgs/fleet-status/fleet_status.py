#!/usr/bin/env python3
"""fleet-status — one bounded, truthful snapshot of the house computer (#356).

Two entry points share this file and its schema (SCHEMA.md):

  fleet-status-collect --json   on EVERY host: local facts only, each one
                                {value, source, observed_at, grade[, reason]}.
  fleet-status [--json]         on the coordinator: fans the collector out over
                                the root SSH mesh in parallel, one hard deadline
                                per node, and renders a compact terminal view.

The rules that make the output honest rather than pretty:

* A fact is `measured`, `unknown` (we tried and could not tell — a timeout, a
  missing tool, a refused socket) or `missing-by-design` (this host's profile
  says the thing does not exist here, e.g. the NAS has no user manager). An
  unknown is never rendered as a zero, and absence is never rendered as health.
* A node that does not answer inside its deadline is `timeout`; one whose ssh
  exits 255 is `unreachable`; one that answers garbage is `error`. All three
  carry no facts, and the renderer prints them LOUDLY.
* The planes stay separate. Tally and Herdr contribute IDs, states and counts,
  never copies of their lakes or transcripts; Halogen contributes its own
  /health; journald and /var/lib/failure-markers stay the source of failures.
* The Herdr server's RSS is reported apart from herdr.service's cgroup, because
  the cgroup is dominated by pane descendants (the 2026-09-08 incident, #357):
  descendants are per-pane footprints, never "Herdr memory".

Stdlib only; every subprocess has a timeout; no daemon, no database.
"""

from __future__ import annotations

import concurrent.futures as cf
import datetime as dt
import json
import os
import pwd
import re
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

SCHEMA = 1
GRADES = ("measured", "unknown", "missing-by-design")
REACHABILITY = ("reachable", "timeout", "unreachable", "error")
SECTIONS = (
    "identity",
    "nix",
    "updates",
    "systemd",
    "user_manager",
    "failure_markers",
    "pressure",
    "storage",
    "timers",
    "events",
    "inference",
    "runs",
    "attention",
)

CMD_TIMEOUT = float(os.environ.get("FLEET_STATUS_CMD_TIMEOUT", "3"))
COLLECT_BUDGET = float(os.environ.get("FLEET_STATUS_COLLECT_BUDGET", "6"))
NODE_DEADLINE = float(os.environ.get("FLEET_STATUS_NODE_DEADLINE", "8"))

PROFILE_FILE = os.environ.get("FLEET_STATUS_PROFILE", "/etc/fleet-status/profile.json")
HOSTS_FILE = os.environ.get("FLEET_STATUS_HOSTS_FILE", "/etc/fleet-status/hosts.json")

TOM = "tom"
MARKER_DIR = Path(os.environ.get("FLEET_STATUS_MARKER_DIR", "/var/lib/failure-markers"))

# journald's own catalog ids (systemd/catalog/systemd.catalog.in).
MSG_COREDUMP = "fc2e22bc6ee647b6b90729ab34a250b1"
MSG_UNIT_FAILED = "d9b373ed55a64feb8242e02dbe79a49c"
EVENTS_SINCE = "-6h"
EVENTS_CAP = 50


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def fact(value, source: str, grade: str = "measured", reason: str | None = None) -> dict:
    out = {"value": value, "source": source, "observed_at": now_iso(), "grade": grade}
    if reason:
        out["reason"] = reason
    return out


def unknown(source: str, reason: str) -> dict:
    return fact(None, source, "unknown", reason)


def by_design(source: str, reason: str) -> dict:
    return fact(None, source, "missing-by-design", reason)


class CmdError(Exception):
    pass


def run(argv: list[str], timeout: float = CMD_TIMEOUT, ok_codes=(0,), env=None) -> str:
    """Run argv with a hard timeout; raise CmdError with a short reason."""
    if shutil.which(argv[0]) is None and not os.path.isabs(argv[0]):
        raise CmdError(f"{argv[0]} not found")
    try:
        proc = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
            stdin=subprocess.DEVNULL,
        )
    except subprocess.TimeoutExpired:
        raise CmdError(f"{argv[0]} timed out after {timeout:g}s")
    except OSError as exc:
        raise CmdError(f"{argv[0]}: {exc.strerror}")
    if proc.returncode not in ok_codes:
        err = (proc.stderr or proc.stdout).strip().splitlines()
        raise CmdError(f"{argv[0]} exit {proc.returncode}: {err[0][:160] if err else ''}")
    return proc.stdout


def as_tom(argv: list[str]) -> tuple[list[str], dict | None]:
    """Commands that live on tom's user bus/sockets. The ssh collector runs as
    root, so it drops to tom with his runtime dir; locally it already is tom."""
    try:
        uid = pwd.getpwnam(TOM).pw_uid
    except KeyError:
        raise CmdError("no user tom")
    env = dict(os.environ, XDG_RUNTIME_DIR=f"/run/user/{uid}")
    if os.geteuid() == 0:
        return ["runuser", "-u", TOM, "--", "env", f"XDG_RUNTIME_DIR=/run/user/{uid}", *argv], env
    return argv, env


def user_systemctl(args: list[str]) -> list[str]:
    if os.geteuid() == 0:
        return ["systemctl", "--user", "-M", f"{TOM}@", *args]
    return ["systemctl", "--user", *args]


TOM_BIN_DIR = os.environ.get("FLEET_STATUS_TOM_BIN_DIR", f"/etc/profiles/per-user/{TOM}/bin")


def tom_bin(name: str) -> str:
    # tom's Home Manager profile holds herdr and tally; root's PATH over ssh
    # does not, so resolve them there first.
    p = f"{TOM_BIN_DIR}/{name}"
    return p if os.path.exists(p) else name


def read_text(path: str | Path) -> str:
    return Path(path).read_text()


def load_profile() -> dict:
    try:
        return json.loads(read_text(PROFILE_FILE))
    except (OSError, ValueError):
        return {"name": "unprofiled", "user_manager": False, "roles": [], "mounts": []}


def systemctl_show(units: list[str], props: list[str], user: bool = False) -> dict[str, dict]:
    if not units:
        return {}
    base = user_systemctl(["show"]) if user else ["systemctl", "show"]
    argv = [*base, *units, "-p", ",".join(["Id", *props])]
    env = None
    if user:
        argv, env = as_tom(argv) if os.geteuid() != 0 else (argv, None)
    out = run(argv, env=env)
    result: dict[str, dict] = {}
    for block in out.strip().split("\n\n"):
        kv = dict(line.split("=", 1) for line in block.splitlines() if "=" in line)
        if "Id" in kv:
            result[kv["Id"]] = kv
    return result


# ─── collector sections ────────────────────────────────────────────────────


def c_identity(profile: dict) -> dict:
    out = {"hostname": fact(socket.gethostname(), "gethostname()"), "profile": fact(profile.get("name"), PROFILE_FILE)}
    try:
        out["boot_id"] = fact(read_text("/proc/sys/kernel/random/boot_id").strip(), "/proc/sys/kernel/random/boot_id")
    except OSError as exc:
        out["boot_id"] = unknown("/proc/sys/kernel/random/boot_id", str(exc))
    try:
        out["uptime_s"] = fact(int(float(read_text("/proc/uptime").split()[0])), "/proc/uptime")
    except (OSError, ValueError, IndexError) as exc:
        out["uptime_s"] = unknown("/proc/uptime", str(exc))
    return out


def c_nix(profile: dict) -> dict:
    out: dict = {}
    links = {}
    for key, path in (("current", "/run/current-system"), ("booted", "/run/booted-system")):
        try:
            links[key] = os.readlink(path)
            out[key] = fact(links[key], f"readlink {path}")
        except OSError as exc:
            out[key] = unknown(f"readlink {path}", exc.strerror or str(exc))
    try:
        gen_link = os.readlink("/nix/var/nix/profiles/system")
        m = re.match(r"system-(\d+)-link", gen_link)
        target = os.path.realpath("/nix/var/nix/profiles/system")
        out["generation"] = fact(
            {"number": int(m.group(1)) if m else None, "link": gen_link, "is_current": target == links.get("current")},
            "readlink /nix/var/nix/profiles/system",
        )
    except OSError as exc:
        out["generation"] = unknown("/nix/var/nix/profiles/system", exc.strerror or str(exc))
    try:
        v = json.loads(run(["nixos-version", "--json"]))
        out["version"] = fact(v.get("nixosVersion"), "nixos-version --json")
        rev = v.get("configurationRevision")
        out["revision"] = (
            fact(rev, "nixos-version --json")
            if rev
            else unknown("nixos-version --json", "system.configurationRevision not set in this closure")
        )
    except (CmdError, ValueError) as exc:
        out["version"] = unknown("nixos-version --json", str(exc))
        out["revision"] = unknown("nixos-version --json", str(exc))
    if "current" in links and "booted" in links:
        differs = []
        for part in ("kernel", "initrd", "kernel-modules"):
            try:
                a = os.path.realpath(f"/run/booted-system/{part}")
                b = os.path.realpath(f"/run/current-system/{part}")
                if a != b:
                    differs.append(part)
            except OSError:
                pass
        out["pending_reboot"] = fact({"pending": bool(differs), "differs": differs}, "/run/{booted,current}-system/{kernel,initrd,kernel-modules}")
    else:
        out["pending_reboot"] = unknown("/run/{booted,current}-system", "a system link is unreadable")
    return out


def c_updates(profile: dict) -> dict:
    # #354's `update-adopt status --json` is the authority. Until it is
    # enrolled on a host, the honest answer is unknown, not "up to date".
    exe = shutil.which("update-adopt")
    if exe is None:
        return {"status": unknown("update-adopt status --json", "update-adopt not enrolled on this host (#354)")}
    try:
        data = json.loads(run([exe, "status", "--json"]))
    except (CmdError, ValueError) as exc:
        return {"status": unknown("update-adopt status --json", str(exc))}
    return {"status": fact(data, "update-adopt status --json")}


def c_systemd(profile: dict) -> dict:
    out: dict = {}
    try:
        state = run(["systemctl", "is-system-running"], ok_codes=range(0, 256)).strip()
        out["system_state"] = fact(state or None, "systemctl is-system-running", "measured" if state else "unknown")
    except CmdError as exc:
        out["system_state"] = unknown("systemctl is-system-running", str(exc))
    try:
        failed = json.loads(run(["systemctl", "list-units", "--failed", "--output=json", "--no-pager"]) or "[]")
        out["failed_units"] = fact([u.get("unit") for u in failed], "systemctl list-units --failed --output=json")
    except (CmdError, ValueError) as exc:
        out["failed_units"] = unknown("systemctl list-units --failed", str(exc))
    return out


def c_user_manager(profile: dict) -> dict:
    src = f"systemctl --user (as {TOM})"
    if not profile.get("user_manager"):
        why = f"profile {profile.get('name')} has no Home Manager user session"
        return {"state": by_design(src, why), "failed_units": by_design(src, why)}
    out: dict = {}
    try:
        argv, env = as_tom(user_systemctl(["is-system-running"])) if os.geteuid() != 0 else (user_systemctl(["is-system-running"]), None)
        state = run(argv, env=env, ok_codes=range(0, 256)).strip()
        out["state"] = fact(state or None, src, "measured" if state else "unknown")
    except CmdError as exc:
        out["state"] = unknown(src, str(exc))
    try:
        argv = user_systemctl(["list-units", "--failed", "--output=json", "--no-pager"])
        env = None
        if os.geteuid() != 0:
            argv, env = as_tom(argv)
        failed = json.loads(run(argv, env=env) or "[]")
        out["failed_units"] = fact([u.get("unit") for u in failed], src + " list-units --failed")
    except (CmdError, ValueError) as exc:
        out["failed_units"] = unknown(src, str(exc))
    return out


def c_failure_markers(profile: dict) -> dict:
    src = str(MARKER_DIR)
    if not MARKER_DIR.is_dir():
        return {"markers": unknown(src, "marker directory absent")}
    markers = []
    try:
        for p in sorted(MARKER_DIR.iterdir()):
            if p.name.startswith(".") or not p.is_file():
                continue
            try:
                first = p.read_text(errors="replace").splitlines()[:1]
            except OSError:
                first = []
            markers.append({"name": p.name, "summary": first[0][:200] if first else "", "mtime": int(p.stat().st_mtime)})
    except OSError as exc:
        return {"markers": unknown(src, str(exc))}
    return {"markers": fact(markers, src)}


def cgroup_mem(path: Path) -> int | None:
    try:
        return int((path / "memory.current").read_text())
    except (OSError, ValueError):
        return None


def c_pressure(profile: dict) -> dict:
    out: dict = {}
    try:
        mi = {}
        for line in read_text("/proc/meminfo").splitlines():
            k, v = line.split(":", 1)
            mi[k] = int(v.split()[0]) * 1024
        out["memory"] = fact(
            {
                "total": mi.get("MemTotal"),
                "available": mi.get("MemAvailable"),
                "swap_total": mi.get("SwapTotal"),
                "swap_used": (mi.get("SwapTotal", 0) - mi.get("SwapFree", 0)) if "SwapTotal" in mi else None,
            },
            "/proc/meminfo",
        )
    except (OSError, ValueError) as exc:
        out["memory"] = unknown("/proc/meminfo", str(exc))
    psi = {}
    for res in ("memory", "cpu", "io"):
        try:
            for line in read_text(f"/proc/pressure/{res}").splitlines():
                kind, *fields = line.split()
                psi[f"{res}_{kind}"] = {k: float(v) for k, v in (f.split("=") for f in fields) if k.startswith("avg")}
        except (OSError, ValueError):
            pass
    out["psi"] = fact(psi, "/proc/pressure/{memory,cpu,io}") if psi else unknown("/proc/pressure", "PSI unreadable")
    try:
        la = read_text("/proc/loadavg").split()
        out["load"] = fact([float(x) for x in la[:3]], "/proc/loadavg")
    except (OSError, ValueError) as exc:
        out["load"] = unknown("/proc/loadavg", str(exc))
    root = Path(os.environ.get("FLEET_STATUS_CGROUP_ROOT", "/sys/fs/cgroup"))
    groups: list[tuple[int, str]] = []
    candidates = list((root / "system.slice").glob("*")) + list((root / "user.slice").glob("user-*.slice/session-*.scope"))
    for mgr in (root / "user.slice").glob("user-*.slice/user@*.service"):
        candidates += list(mgr.glob("*.slice/*"))
    for cg in candidates:
        if not cg.is_dir():
            continue
        mem = cgroup_mem(cg)
        if mem:
            groups.append((mem, str(cg.relative_to(root))))
    if groups:
        groups.sort(reverse=True)
        out["top_cgroups"] = fact(
            [{"cgroup": name, "memory_current": mem} for mem, name in groups[:5]],
            f"{root}/**/memory.current (cgroup totals include every descendant)",
        )
    else:
        out["top_cgroups"] = unknown(str(root), "no readable memory.current")
    return out


def c_storage(profile: dict) -> dict:
    src = "findmnt --json --real -b"
    try:
        data = json.loads(run(["findmnt", "--json", "--real", "-b", "-o", "TARGET,SOURCE,FSTYPE,SIZE,USED,AVAIL"]))
    except (CmdError, ValueError) as exc:
        return {"mounts": unknown(src, str(exc))}
    flat: dict[str, dict] = {}

    def walk(nodes):
        for n in nodes:
            flat[n["target"]] = n
            walk(n.get("children", []))

    walk(data.get("filesystems", []))
    rows = []
    for m in profile.get("mounts", []):
        point = m["mountpoint"]
        n = flat.get(point)
        row = {"mountpoint": point, "mounted": n is not None, "on_demand": m.get("on_demand", False)}
        if n:
            size, used = n.get("size") or 0, n.get("used") or 0
            row.update({"fstype": n.get("fstype"), "size": size, "avail": n.get("avail"), "use_pct": round(100 * used / size, 1) if size else None})
        rows.append(row)
    return {"mounts": fact(rows, src + " against the declared fileSystems")}


def c_timers(profile: dict) -> dict:
    def scan(user: bool) -> dict:
        src = ("systemctl --user" if user else "systemctl") + " list-timers --all --output=json + show Result"
        argv = (user_systemctl(["list-timers", "--all", "--output=json", "--no-pager"]) if user else ["systemctl", "list-timers", "--all", "--output=json", "--no-pager"])
        env = None
        try:
            if user and os.geteuid() != 0:
                argv, env = as_tom(argv)
            timers = json.loads(run(argv, env=env) or "[]")
            units = sorted({t.get("activates") for t in timers if t.get("activates")})
            shown = systemctl_show(units, ["Result", "ActiveState"], user=user)
        except (CmdError, ValueError) as exc:
            return unknown(src, str(exc))
        bad = [
            {"unit": u, "result": s.get("Result"), "active": s.get("ActiveState")}
            for u, s in shown.items()
            if s.get("Result") not in (None, "", "success")
        ]
        return fact({"timers": len(timers), "non_success": bad}, src)

    out = {"system": scan(False)}
    out["user"] = scan(True) if profile.get("user_manager") else by_design("systemctl --user list-timers", "no user manager on this profile")
    return out


def journal(args: list[str]) -> list[dict]:
    argv = ["journalctl", "-o", "json", "--no-pager", "--since", EVENTS_SINCE, "-n", str(EVENTS_CAP), *args]
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=CMD_TIMEOUT, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        raise CmdError(f"journalctl timed out after {CMD_TIMEOUT:g}s")
    except OSError as exc:
        raise CmdError(f"journalctl: {exc.strerror}")
    out = proc.stdout
    if proc.returncode != 0:
        # journalctl exits 1 for "matched nothing": a -g grep with no hit
        # prints nothing at all, and a -u glob naming a unit that never
        # logged says "No data available". Both are a measured empty list.
        # Anything else is a real failure and stays unknown.
        err = proc.stderr.strip()
        if not (proc.returncode == 1 and not out.strip() and (not err or "No data available" in err)):
            raise CmdError(f"journalctl exit {proc.returncode}: {err.splitlines()[0][:160] if err else ''}")
    rows = []
    for line in out.splitlines():
        try:
            rows.append(json.loads(line))
        except ValueError:
            continue
    return rows


def first_line(msg) -> str:
    if isinstance(msg, list):  # journald hands binary-ish MESSAGE as a byte list
        try:
            msg = bytes(msg).decode("utf-8", "replace")
        except (TypeError, ValueError):
            msg = ""
    return str(msg or "").splitlines()[0][:200] if msg else ""


def c_events(profile: dict) -> dict:
    # Bounded field matches only — never an unfiltered six-hour dump over ssh.
    queries = {
        "coredumps": (["MESSAGE_ID=" + MSG_COREDUMP], lambda r: {"exe": r.get("COREDUMP_EXE"), "unit": r.get("COREDUMP_UNIT")}),
        "unit_failures": (["MESSAGE_ID=" + MSG_UNIT_FAILED], lambda r: {"unit": r.get("UNIT") or r.get("USER_UNIT")}),
        "oom_kills": (["-k", "-g", "Out of memory|oom-kill|oom_reaper"], lambda r: {}),
        # An identifier match, not `-u update-adopt*`: a unit glob makes
        # journalctl enumerate every unit name in the journal, which took more
        # than 3 s on the NAS (measured 2026-09-13).
        "update_adopt": (["SYSLOG_IDENTIFIER=update-adopt"], lambda r: {"unit": r.get("_SYSTEMD_UNIT")}),
    }
    out = {}
    for name, (args, extra) in queries.items():
        src = "journalctl -o json --since -6h " + " ".join(args)
        try:
            rows = journal(args)
        except CmdError as exc:
            out[name] = unknown(src, str(exc))
            continue
        items = []
        for r in rows[-EVENTS_CAP:]:
            ts = r.get("__REALTIME_TIMESTAMP")
            when = dt.datetime.fromtimestamp(int(ts) / 1e6, dt.timezone.utc).isoformat(timespec="seconds") if ts else None
            items.append({"at": when, "message": first_line(r.get("MESSAGE")), **extra(r)})
        out[name] = fact(items, src)
    return out


def http_json(url: str, timeout: float = 2.5):
    with urllib.request.urlopen(url, timeout=timeout) as resp:  # noqa: S310 (loopback, fixed URL)
        return json.loads(resp.read(1 << 20))


def c_inference(profile: dict) -> dict:
    roles = profile.get("roles", [])
    out: dict = {}
    if "halogen" in roles:
        src = "systemctl list-units --all podman-halogen*"
        try:
            units = json.loads(run(["systemctl", "list-units", "--all", "--output=json", "--no-pager", "podman-halogen*"]) or "[]")
            out["halogen_units"] = fact({u["unit"]: u.get("active") for u in units}, src)
        except (CmdError, ValueError) as exc:
            out["halogen_units"] = unknown(src, str(exc))
        port = profile.get("halogen_port", 8731)
        try:
            h = http_json(f"http://127.0.0.1:{port}/health")
            keep = ("status", "model", "context", "busy", "in_flight", "queued", "slots")
            out["health"] = fact({k: h.get(k) for k in keep}, f"GET 127.0.0.1:{port}/health")
        except Exception as exc:  # noqa: BLE001 — any failure is simply "unknown"
            out["health"] = unknown(f"GET 127.0.0.1:{port}/health", str(exc)[:160])
        try:
            c = http_json(f"http://127.0.0.1:{port}/cache")
            out["cache"] = fact({k: c.get(k) for k in ("entries", "bytes", "hits", "misses", "hit_rate")}, f"GET 127.0.0.1:{port}/cache")
        except Exception as exc:  # noqa: BLE001
            out["cache"] = unknown(f"GET 127.0.0.1:{port}/cache", str(exc)[:160])
    if "fara" in roles:
        src = "systemctl --user show fara-browser-model"
        try:
            s = systemctl_show(["fara-browser-model.service"], ["ActiveState"], user=True)
            out["fara_browser_model"] = fact((s.get("fara-browser-model.service") or {}).get("ActiveState"), src)
        except CmdError as exc:
            out["fara_browser_model"] = unknown(src, str(exc))
    if not out:
        out["server"] = by_design("profile roles", f"profile {profile.get('name')} serves no model")
    return out


def tail_lines(path: Path, max_bytes: int = 4 << 20) -> list[str]:
    with path.open("rb") as fh:
        fh.seek(0, os.SEEK_END)
        size = fh.tell()
        fh.seek(max(0, size - max_bytes))
        data = fh.read().decode("utf-8", "replace")
    lines = data.splitlines()
    return lines[1:] if size > max_bytes else lines


def c_runs(profile: dict) -> dict:
    if "runs" not in profile.get("roles", []):
        return {"tally": by_design("profile roles", f"no Tally plane on profile {profile.get('name')}")}
    out: dict = {}
    try:
        home = Path(pwd.getpwnam(TOM).pw_dir)
    except KeyError:
        home = None
    # Plane B: the rewrite kernel, a SYSTEM unit (modules/tally-b.nix).
    try:
        s = systemctl_show(["tally-kernel.service"], ["ActiveState"])
        out["kernel_unit"] = fact((s.get("tally-kernel.service") or {}).get("ActiveState"), "systemctl show tally-kernel")
    except CmdError as exc:
        out["kernel_unit"] = unknown("systemctl show tally-kernel", str(exc))
    ledger = (home or Path("/nonexistent")) / ".local/state/tally-rewrite/ledger.jsonl"
    try:
        if home is None:
            raise OSError(f"no user {TOM}")
        granted: dict[str, str] = {}
        last_seq = None
        for line in tail_lines(ledger):
            try:
                row = json.loads(line)
            except ValueError:
                continue
            last_seq = row.get("seq", last_seq)
            p = row.get("payload") or {}
            kind, lease = p.get("kind"), p.get("lease")
            if kind == "lease_grant" and lease:
                granted[str(lease)] = p.get("row") or p.get("seat") or ""
            elif kind == "lease_released" and lease:
                granted.pop(str(lease), None)
        out["kernel_leases"] = fact(
            {"open_lease_ids": sorted(granted), "ledger": str(ledger), "last_seq": last_seq},
            f"{ledger} (lease_grant minus lease_released, last 4 MiB)",
        )
    except OSError as exc:
        out["kernel_leases"] = unknown(str(ledger), exc.strerror or str(exc))
    # Plane A: the live tally daemon on tom's user bus.
    try:
        s = systemctl_show(["tally-daemon.service"], ["ActiveState"], user=True)
        out["daemon_unit"] = fact((s.get("tally-daemon.service") or {}).get("ActiveState"), "systemctl --user show tally-daemon")
    except CmdError as exc:
        out["daemon_unit"] = unknown("systemctl --user show tally-daemon", str(exc))
    src = "tally query jobs --state running --json --limit 20"
    try:
        argv, env = as_tom([tom_bin("tally"), "query", "jobs", "--state", "running", "--json", "--limit", "20"])
        data = json.loads(run(argv, env=env))
        ids = [i.get("jobId") or i.get("id") or i.get("job") for i in data.get("items", [])]
        out["daemon_running_jobs"] = fact({"job_ids": [i for i in ids if i], "truncated": bool(data.get("nextCursor"))}, src)
    except (CmdError, ValueError, AttributeError) as exc:
        out["daemon_running_jobs"] = unknown(src, str(exc))
    src = "tally query pools"
    try:
        argv, env = as_tom([tom_bin("tally"), "query", "pools"])
        data = json.loads(run(argv, env=env))
        busy = [
            {"pool": p.get("pool"), "held": p.get("held"), "queued": p.get("queued"), "signal": p.get("signal")}
            for p in data.get("pools", [])
            if p.get("held") or p.get("queued") or p.get("signal") not in (None, "GO")
        ]
        out["daemon_pools"] = fact({"pools": len(data.get("pools", [])), "not_idle": busy}, src)
    except (CmdError, ValueError, AttributeError) as exc:
        out["daemon_pools"] = unknown(src, str(exc))
    return out


def proc_table() -> dict[int, tuple[int, int, int]]:
    """pid -> (ppid, rss_bytes, starttime_ticks) from one /proc pass."""
    page = os.sysconf("SC_PAGE_SIZE")
    table = {}
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            stat = read_text(f"/proc/{d}/stat")
            rest = stat[stat.rindex(")") + 2 :].split()
            ppid, start = int(rest[1]), int(rest[19])
            rss = int(read_text(f"/proc/{d}/statm").split()[1]) * page
        except (OSError, ValueError, IndexError):
            continue
        table[int(d)] = (ppid, rss, start)
    return table


def tree_rss(root: int, table: dict) -> tuple[int, int]:
    children: dict[int, list[int]] = {}
    for pid, (ppid, _, _) in table.items():
        children.setdefault(ppid, []).append(pid)
    total, count, stack = 0, 0, [root]
    while stack:
        pid = stack.pop()
        if pid not in table:
            continue
        total += table[pid][1]
        count += 1
        stack.extend(children.get(pid, []))
    return total, count


def c_attention(profile: dict) -> dict:
    if "attention" not in profile.get("roles", []):
        return {"herdr": by_design("profile roles", f"no Herdr server on profile {profile.get('name')}")}
    out: dict = {}
    herdr = tom_bin("herdr")

    def herdr_json(args):
        argv, env = as_tom([herdr, *args])
        return json.loads(run(argv, env=env)).get("result", {})

    try:
        agents = herdr_json(["agent", "list"]).get("agents", [])
        counts: dict[str, int] = {}
        for a in agents:
            counts[a.get("agent_status", "unknown")] = counts.get(a.get("agent_status", "unknown"), 0) + 1
        out["agents"] = fact(
            {
                "by_status": counts,
                "agents": [{"pane_id": a.get("pane_id"), "agent": a.get("agent"), "status": a.get("agent_status")} for a in agents],
            },
            "herdr agent list",
        )
    except (CmdError, ValueError, AttributeError) as exc:
        agents = []
        out["agents"] = unknown("herdr agent list", str(exc))

    # Server RSS apart from the cgroup: the cgroup total is every pane's
    # descendants too, and must never be read as the server's own footprint.
    src = "systemctl --user show herdr -p MainPID,ControlGroup"
    table = proc_table()
    try:
        s = systemctl_show(["herdr.service"], ["MainPID", "ControlGroup"], user=True).get("herdr.service", {})
        pid = int(s.get("MainPID") or 0)
        cg = s.get("ControlGroup") or ""
        server_rss = table[pid][1] if pid in table else None
        cg_path = Path("/sys/fs/cgroup") / cg.lstrip("/")
        cg_mem = cgroup_mem(cg_path) if cg else None
        cg_anon = None
        try:
            stat = dict(l.split() for l in (cg_path / "memory.stat").read_text().splitlines())
            cg_anon = int(stat["anon"])
        except (OSError, ValueError, KeyError):
            pass
        out["server"] = fact(
            # memory.current counts page cache the panes' builds touched as
            # well; anon is the part that is actually process memory.
            {"main_pid": pid or None, "server_rss": server_rss, "cgroup": cg or None, "cgroup_memory_current": cg_mem, "cgroup_anon": cg_anon},
            src + " + /proc/<MainPID>/statm + <cgroup>/memory.current",
            "measured" if server_rss is not None else "unknown",
            None if server_rss is not None else "herdr MainPID not running",
        )
    except CmdError as exc:
        out["server"] = unknown(src, str(exc))

    try:
        panes = herdr_json(["pane", "list"]).get("panes", [])
    except (CmdError, ValueError, AttributeError) as exc:
        out["panes"] = unknown("herdr pane list", str(exc))
        return out
    agent_by_pane = {a.get("pane_id"): a for a in agents}
    hz = os.sysconf("SC_CLK_TCK")
    try:
        btime = next(int(l.split()[1]) for l in read_text("/proc/stat").splitlines() if l.startswith("btime"))
    except (OSError, StopIteration, ValueError):
        btime = None
    budget = time.monotonic() + 3.0
    rows = []
    for p in panes:
        pid_ = p.get("pane_id")
        agent = agent_by_pane.get(pid_) or {}
        row = {"pane_id": pid_, "workspace_id": p.get("workspace_id"), "agent": agent.get("agent"), "status": agent.get("agent_status") or p.get("agent_status"), "title": (p.get("terminal_title_stripped") or "")[:60]}
        if time.monotonic() > budget:
            row.update({"grade": "unknown", "reason": "pane budget exhausted"})
            rows.append(row)
            continue
        try:
            info = herdr_json(["pane", "process-info", "--pane", pid_]).get("process_info", {})
            shell = int(info.get("shell_pid") or 0)
            if shell in table:
                rss, nproc = tree_rss(shell, table)
                age = int(time.time() - (btime + table[shell][2] / hz)) if btime else None
                row.update({"shell_pid": shell, "age_s": age, "tree_rss": rss, "tree_procs": nproc, "grade": "measured"})
            else:
                row.update({"shell_pid": shell or None, "grade": "unknown", "reason": "shell pid not in /proc"})
        except (CmdError, ValueError, AttributeError) as exc:
            row.update({"grade": "unknown", "reason": str(exc)[:120]})
        rows.append(row)
    rows.sort(key=lambda r: r.get("tree_rss") or 0, reverse=True)
    out["panes"] = fact(
        {"count": len(rows), "panes": rows},
        "herdr pane list + herdr pane process-info + /proc (age = shell start; footprint = shell process tree RSS)",
    )
    return out


COLLECTORS = {
    "identity": c_identity,
    "nix": c_nix,
    "updates": c_updates,
    "systemd": c_systemd,
    "user_manager": c_user_manager,
    "failure_markers": c_failure_markers,
    "pressure": c_pressure,
    "storage": c_storage,
    "timers": c_timers,
    "events": c_events,
    "inference": c_inference,
    "runs": c_runs,
    "attention": c_attention,
}


def collect() -> dict:
    profile = load_profile()
    started = time.monotonic()
    sections: dict = {}
    pool = cf.ThreadPoolExecutor(max_workers=len(COLLECTORS))
    futures = {pool.submit(fn, profile): name for name, fn in COLLECTORS.items()}
    deadline = started + COLLECT_BUDGET
    for fut, name in futures.items():
        remaining = max(0.0, deadline - time.monotonic())
        try:
            sections[name] = fut.result(timeout=remaining)
        except cf.TimeoutError:
            sections[name] = {"section": unknown(name, f"collector budget {COLLECT_BUDGET:g}s exhausted")}
        except Exception as exc:  # noqa: BLE001 — a crashed section is unknown, never absent
            sections[name] = {"section": unknown(name, f"{type(exc).__name__}: {exc}"[:200])}
    pool.shutdown(wait=False, cancel_futures=True)
    return {
        "schema": SCHEMA,
        "kind": "node",
        "observed_at": now_iso(),
        "hostname": socket.gethostname(),
        "profile": profile.get("name"),
        "collect_ms": int((time.monotonic() - started) * 1000),
        "sections": sections,
    }


# ─── schema validation (used by the tests and by the fan-out) ──────────────


def validate_fact(f, where: str) -> list[str]:
    errs = []
    if not isinstance(f, dict):
        return [f"{where}: fact is not an object"]
    for key in ("value", "source", "observed_at", "grade"):
        if key not in f:
            errs.append(f"{where}: missing {key}")
    if f.get("grade") not in GRADES:
        errs.append(f"{where}: bad grade {f.get('grade')!r}")
    if f.get("grade") != "measured" and f.get("value") is not None:
        errs.append(f"{where}: non-measured fact carries a value")
    if f.get("grade") != "measured" and not f.get("reason"):
        errs.append(f"{where}: non-measured fact without reason")
    return errs


def validate_node_report(rep) -> list[str]:
    if not isinstance(rep, dict) or rep.get("schema") != SCHEMA or not isinstance(rep.get("sections"), dict):
        return ["node report: not a schema-1 object with sections"]
    errs = []
    for name in SECTIONS:
        sec = rep["sections"].get(name)
        if not isinstance(sec, dict) or not sec:
            errs.append(f"section {name} missing or empty")
            continue
        for fname, f in sec.items():
            errs += validate_fact(f, f"{name}.{fname}")
    return errs


def validate_snapshot(snap) -> list[str]:
    errs = []
    if not isinstance(snap, dict) or snap.get("schema") != SCHEMA:
        return ["snapshot: schema != 1"]
    for key in ("observed_at", "nodes", "updates", "failures", "inference", "runs", "attention"):
        if key not in snap:
            errs.append(f"snapshot: missing {key}")
    for node in snap.get("nodes", []):
        where = f"node {node.get('name')}"
        if node.get("reachability") not in REACHABILITY:
            errs.append(f"{where}: bad reachability")
        if node.get("reachability") == "reachable":
            errs += [f"{where}: {e}" for e in validate_node_report(node.get("report"))]
        elif node.get("report") is not None:
            errs.append(f"{where}: unreachable node carries a report")
    return errs


# ─── fan-out ───────────────────────────────────────────────────────────────


def load_hosts() -> list[dict]:
    try:
        declared = json.loads(read_text(HOSTS_FILE))
    except (OSError, ValueError):
        declared = []
    names = os.environ.get("FLEET_STATUS_HOSTS")
    if not names:
        return declared
    by_name = {h["name"]: h for h in declared}
    return [by_name.get(n, {"name": n, "target": f"root@{n}", "profile": "unprofiled", "transport": "ssh"}) for n in names.split(",") if n]


def fetch_node(host: dict) -> dict:
    name = host["name"]
    base = {"name": name, "profile": host.get("profile"), "target": host.get("target"), "report": None}
    if host.get("transport") == "local":
        argv = [os.environ.get("FLEET_STATUS_COLLECT", "fleet-status-collect"), "--json"]
    else:
        ssh = os.environ.get("FLEET_STATUS_SSH", "ssh")
        argv = [ssh, "-o", "BatchMode=yes", "-o", "ConnectTimeout=3", host["target"], "fleet-status-collect", "--json"]
    started = time.monotonic()
    try:
        proc = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.DEVNULL, text=True, start_new_session=True)
    except OSError as exc:
        return {**base, "reachability": "unreachable", "error": str(exc), "latency_ms": None}
    try:
        stdout, stderr = proc.communicate(timeout=NODE_DEADLINE)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass
        proc.communicate()
        return {**base, "reachability": "timeout", "error": f"no answer within {NODE_DEADLINE:g}s", "latency_ms": None}
    latency = int((time.monotonic() - started) * 1000)
    err = (stderr or "").strip().splitlines()
    if proc.returncode == 255:
        return {**base, "reachability": "unreachable", "error": f"ssh exit 255: {err[-1][:160] if err else ''}", "latency_ms": latency}
    if proc.returncode != 0:
        return {**base, "reachability": "error", "error": f"collector exit {proc.returncode}: {err[-1][:160] if err else ''}", "latency_ms": latency}
    try:
        report = json.loads(stdout)
    except ValueError:
        return {**base, "reachability": "error", "error": "collector output is not JSON", "latency_ms": latency}
    problems = validate_node_report(report)
    if problems:
        return {**base, "reachability": "error", "error": "schema: " + "; ".join(problems[:3]), "latency_ms": latency}
    return {**base, "reachability": "reachable", "latency_ms": latency, "report": report}


def g(node: dict, section: str, name: str) -> dict:
    """A fact from a node, or an unknown standing in for an unreachable one."""
    rep = node.get("report")
    if rep is None:
        return unknown(f"node {node['name']}", f"node {node['reachability']}")
    return rep["sections"].get(section, {}).get(name) or unknown(section, "fact not reported")


def snapshot() -> dict:
    hosts = load_hosts()
    with cf.ThreadPoolExecutor(max_workers=max(1, len(hosts))) as pool:
        nodes = list(pool.map(fetch_node, hosts))
    updates, failures, inference, runs, attention = [], [], [], [], []
    for n in nodes:
        nm = n["name"]
        updates.append({"node": nm, "status": g(n, "updates", "status"), "current": g(n, "nix", "current"), "booted": g(n, "nix", "booted"), "revision": g(n, "nix", "revision"), "pending_reboot": g(n, "nix", "pending_reboot")})
        if n.get("report") is None:
            failures.append({"node": nm, "kind": "node", "id": nm, "grade": "unknown", "reason": f"node {n['reachability']}: failures cannot be ruled out"})
        else:
            for kind, sec, fname in (("unit", "systemd", "failed_units"), ("user-unit", "user_manager", "failed_units")):
                f = g(n, sec, fname)
                if f["grade"] == "measured":
                    failures += [{"node": nm, "kind": kind, "id": u, "grade": "measured", "source": f["source"]} for u in f["value"]]
                elif f["grade"] == "unknown":
                    failures.append({"node": nm, "kind": kind, "id": None, "grade": "unknown", "reason": f.get("reason")})
            m = g(n, "failure_markers", "markers")
            if m["grade"] == "measured":
                failures += [{"node": nm, "kind": "marker", "id": x["name"], "grade": "measured", "source": m["source"], "summary": x["summary"]} for x in m["value"]]
        if n.get("report") is None:
            inference.append({"node": nm, "grade": "unknown", "reason": f"node {n['reachability']}"})
            continue
        secs = n["report"]["sections"]
        if not all(f["grade"] == "missing-by-design" for f in secs["inference"].values()):
            inference.append({"node": nm, **secs["inference"]})
        if not all(f["grade"] == "missing-by-design" for f in secs["runs"].values()):
            runs.append({"node": nm, **secs["runs"]})
        if not all(f["grade"] == "missing-by-design" for f in secs["attention"].values()):
            attention.append({"node": nm, **secs["attention"]})
    return {"schema": SCHEMA, "kind": "fleet", "observed_at": now_iso(), "nodes": nodes, "updates": updates, "failures": failures, "inference": inference, "runs": runs, "attention": attention}


# ─── rendering ─────────────────────────────────────────────────────────────

BOLD, RED, YEL, DIM, RST = "\033[1m", "\033[31m", "\033[33m", "\033[2m", "\033[0m"


def paint(s: str, code: str, color: bool) -> str:
    return f"{code}{s}{RST}" if color else s


def gib(b) -> str:
    return "?" if b is None else f"{b / (1 << 30):.1f}G"


def mib(b) -> str:
    return "?" if b is None else (f"{b / (1 << 30):.1f}G" if b >= 1 << 30 else f"{b / (1 << 20):.0f}M")


def dur(s) -> str:
    if s is None:
        return "?"
    d, s = divmod(int(s), 86400)
    h, s = divmod(s, 3600)
    m = s // 60
    return f"{d}d{h}h" if d else (f"{h}h{m}m" if h else f"{m}m")


def val(f: dict, fmt=lambda v: v, unknown_text="unknown"):
    if f["grade"] == "measured":
        return fmt(f["value"])
    if f["grade"] == "missing-by-design":
        return "n/a"
    return unknown_text


def render_node(n: dict, color: bool) -> list[str]:
    head = f"{n['name']:<12} {n.get('profile') or '?':<16}"
    if n["reachability"] != "reachable":
        word = "UNREACHABLE" if n["reachability"] == "unreachable" else n["reachability"].upper()
        return [paint(f"{head} {word}", BOLD + RED, color) + f"  {n.get('error', '')}", paint("             no facts: every section is unknown, not zero", DIM, color)]
    s = n["report"]["sections"]
    ident = s["identity"]
    lines = [paint(head, BOLD, color) + f" reachable {n['latency_ms']}ms  up {val(ident['uptime_s'], dur)}  boot {val(ident['boot_id'], lambda v: v[:8])}"]

    gen = s["nix"]["generation"]
    pr = s["nix"]["pending_reboot"]
    nix = f"gen {val(gen, lambda v: v['number'])}  {val(s['nix']['version'])}  rev {val(s['nix']['revision'], lambda v: v[:12])}"
    if pr["grade"] == "measured" and pr["value"]["pending"]:
        nix += "  " + paint("PENDING REBOOT (" + ",".join(pr["value"]["differs"]) + ")", BOLD + YEL, color)
    elif pr["grade"] != "measured":
        nix += "  reboot state unknown"
    lines.append(f"  nix       {nix}")

    up = s["updates"]["status"]
    if up["grade"] == "measured":
        v = up["value"] if isinstance(up["value"], dict) else {}
        parts = [f"{k} {str(v[k])[:24]}" for k in ("candidate", "last_known_good", "last_result", "state") if k in v]
        lines.append("  updates   " + ("  ".join(parts) or json.dumps(v)[:100]))
    else:
        lines.append(f"  updates   unknown ({up.get('reason')})")

    fu, um, mk = s["systemd"]["failed_units"], s["user_manager"]["failed_units"], s["failure_markers"]["markers"]
    sysline = f"{val(s['systemd']['system_state'])}  failed {val(fu, lambda v: len(v))}"
    if fu["grade"] == "measured" and fu["value"]:
        sysline = paint(sysline, RED, color) + " " + ",".join(fu["value"][:4])
    sysline += f"  user {val(s['user_manager']['state'])} failed {val(um, lambda v: len(v))}"
    if um["grade"] == "measured" and um["value"]:
        sysline += " " + ",".join(um["value"][:4])
    if mk["grade"] == "measured" and mk["value"]:
        sysline += "  " + paint("markers " + ",".join(x["name"] for x in mk["value"]), YEL, color)
    elif mk["grade"] != "measured":
        sysline += "  markers unknown"
    lines.append(f"  systemd   {sysline}")

    p = s["pressure"]
    mem = val(p["memory"], lambda v: f"avail {gib(v['available'])}/{gib(v['total'])} swap {gib(v['swap_used'])}/{gib(v['swap_total'])}")
    psi = val(p["psi"], lambda v: "psi10 mem {:.2f} cpu {:.2f} io {:.2f}".format(*(v.get(f"{r}_some", {}).get("avg10", 0.0) for r in ("memory", "cpu", "io"))))
    load = val(p["load"], lambda v: "load " + " ".join(f"{x:.2f}" for x in v))
    lines.append(f"  pressure  {mem}  {psi}  {load}")
    tc = p["top_cgroups"]
    if tc["grade"] == "measured":
        lines.append("  cgroups   " + "  ".join(f"{c['cgroup'].rsplit('/', 1)[-1]} {mib(c['memory_current'])}" for c in tc["value"][:4]))

    mounts = s["storage"]["mounts"]
    if mounts["grade"] == "measured":
        parts = []
        for m in mounts["value"]:
            if not m["mounted"]:
                parts.append(m["mountpoint"] + (" (on demand)" if m["on_demand"] else paint(" NOT MOUNTED", RED, color)))
            elif m.get("use_pct") is not None:
                txt = f"{m['mountpoint']} {m['use_pct']:.0f}%"
                parts.append(paint(txt, YEL, color) if m["use_pct"] >= 90 else txt)
        lines.append("  storage   " + "  ".join(parts[:8]))
    else:
        lines.append(f"  storage   unknown ({mounts.get('reason')})")

    bad = []
    for scope in ("system", "user"):
        t = s["timers"][scope]
        if t["grade"] == "measured":
            bad += [f"{b['unit']}={b['result']}" for b in t["value"]["non_success"]]
        elif t["grade"] == "unknown":
            bad.append(f"{scope} timers unknown")
    lines.append("  timers    " + (", ".join(bad[:5]) if bad else "all last runs succeeded"))

    ev = s["events"]
    lines.append("  events6h  " + "  ".join(f"{k.replace('_', ' ')} {val(ev[k], lambda v: len(v))}" for k in ("coredumps", "unit_failures", "oom_kills", "update_adopt")))

    inf = s["inference"]
    if "health" in inf:
        h = inf["health"]
        lines.append("  inference " + val(h, lambda v: f"halogen {v.get('status')} {v.get('model')} busy={v.get('busy')} in_flight={v.get('in_flight')} queued={v.get('queued')}", f"halogen UNKNOWN ({h.get('reason')})"))
        units = inf.get("halogen_units")
        if units and units["grade"] == "measured":
            lines[-1] += "  " + " ".join(f"{k.replace('.service', '')}={v}" for k, v in units["value"].items())
    if "fara_browser_model" in inf:
        lines.append(f"  inference fara-browser-model {val(inf['fara_browser_model'])}")

    r = s["runs"]
    if "kernel_unit" in r:
        kl = r["kernel_leases"]
        jobs = r["daemon_running_jobs"]
        lines.append(
            f"  runs      tally-kernel {val(r['kernel_unit'])} open leases {val(kl, lambda v: len(v['open_lease_ids']) and ','.join(v['open_lease_ids'][:3]) or 0)}"
            f"  tally-daemon {val(r['daemon_unit'])} running jobs {val(jobs, lambda v: len(v['job_ids']))}"
        )

    a = s["attention"]
    if "server" in a:
        srv = a["server"]
        ag = a["agents"]
        lines.append(
            "  herdr     "
            + val(srv, lambda v: f"server rss {mib(v['server_rss'])} (cgroup incl. panes {mib(v['cgroup_memory_current'])}, anon {mib(v.get('cgroup_anon'))})")
            + "  agents "
            + val(ag, lambda v: " ".join(f"{k}={c}" for k, c in sorted(v["by_status"].items())) or "none")
        )
        panes = a["panes"]
        if panes["grade"] == "measured":
            lines.append(f"  panes     {panes['value']['count']} panes; largest process trees:")
            for row in panes["value"]["panes"][:6]:
                if row.get("grade") == "measured":
                    lines.append(f"            {row['pane_id']:<8} {str(row.get('agent') or '-'):<7} {str(row.get('status') or '-'):<8} age {dur(row['age_s']):>6}  {mib(row['tree_rss']):>6} in {row['tree_procs']} procs  {row['title'][:30]}")
                else:
                    lines.append(f"            {row['pane_id']:<8} footprint unknown ({row.get('reason')})")
        else:
            lines.append(f"  panes     unknown ({panes.get('reason')})")
    return lines


def render(snap: dict, color: bool) -> str:
    out = [paint(f"fleet-status  {snap['observed_at']}", BOLD, color)]
    down = [n["name"] for n in snap["nodes"] if n["reachability"] != "reachable"]
    if down:
        out.append(paint(f"NOT ANSWERING: {', '.join(down)} — their state is unknown", BOLD + RED, color))
    for n in snap["nodes"]:
        out.append("")
        out += render_node(n, color)
    return "\n".join(out) + "\n"


def main_collect(argv: list[str]) -> int:
    report = collect()
    sys.stdout.write(json.dumps(report, indent=None if "--json" in argv else 2) + "\n")
    sys.stdout.flush()
    os._exit(0)  # do not wait on a section thread stuck past the budget


def main_status(argv: list[str]) -> int:
    if "-h" in argv or "--help" in argv:
        print("usage: fleet-status [--json]\n  FLEET_STATUS_HOSTS=a,b,c limits/extends the node list (names not declared ssh to root@<name>).")
        return 0
    snap = snapshot()
    if "--json" in argv:
        print(json.dumps(snap))
    else:
        sys.stdout.write(render(snap, color=sys.stdout.isatty() and not os.environ.get("NO_COLOR")))
    return 0


if __name__ == "__main__":
    prog = os.path.basename(sys.argv[0])
    args = sys.argv[1:]
    if prog.endswith("collect") or (args[:1] == ["collect"]):
        sys.exit(main_collect([a for a in args if a != "collect"]))
    sys.exit(main_status(args))
