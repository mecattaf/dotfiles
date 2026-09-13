#!/usr/bin/env python3
"""update-adopt — per-host immutable candidate adoption (#354).

stage     fetch + verify the NAS's signed candidate, realise it from Attic
activate  gate, switch (or boot), probe, mark known-good or roll back
adopt     stage then activate now; --force skips the downgrade guard and the
          rejected list (never the gates)
status    print the freshness facts as JSON

Exit codes are a contract with failure-surfacing: a busy host, a newer local
generation, a manual policy or an unreachable NAS exit 0 (a receipt, not a
failure); a bad signature, a failed realise, or a failed probe (after the
local rollback) exit 1, so the unit fails and a marker is written.

Test seams (all unset in the real unit; see modules/update-adopt.nix):
  UPDATE_ADOPT_CONFIG     JSON config rendered by Nix (required)
  UPDATE_ADOPT_ROOT       prefix for /run, /nix/var and /proc (default "")
  UPDATE_ADOPT_STORE_DIR  store directory candidates must live in (/nix/store)
  UPDATE_ADOPT_STATE_DIR  state + receipts (/var/lib/update-adopt)
  UPDATE_ADOPT_LOCK       activation lock (/run/update-adopt.lock)
External commands resolve through PATH, so tests put fakes first.
"""

import argparse
import datetime
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.environ.get("UPDATE_ADOPT_ROOT", "")
STORE_DIR = os.environ.get("UPDATE_ADOPT_STORE_DIR", "/nix/store")
STATE_DIR = os.environ.get("UPDATE_ADOPT_STATE_DIR", "/var/lib/update-adopt")
LOCK_PATH = os.environ.get("UPDATE_ADOPT_LOCK", "/run/update-adopt.lock")

CURRENT = ROOT + "/run/current-system"
BOOTED = ROOT + "/run/booted-system"
PROFILE = ROOT + "/nix/var/nix/profiles/system"
GCROOTS = ROOT + "/nix/var/nix/gcroots/update-adopt"
PSI_MEMORY = ROOT + "/proc/pressure/memory"

REVISION_FILE = "fleet-revision.json"
RECEIPTS_KEEP = 50
BOOT_FILES = ("kernel", "initrd", "kernel-params")


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def now_epoch():
    return int(time.time())


def load_config():
    path = os.environ.get("UPDATE_ADOPT_CONFIG")
    if not path:
        sys.exit("update-adopt: UPDATE_ADOPT_CONFIG is not set")
    with open(path) as stream:
        cfg = json.load(stream)
    cfg.setdefault("policy", "manual")
    cfg.setdefault("gates", [])
    cfg.setdefault("probes", [])
    cfg.setdefault("critical_units", [])
    cfg.setdefault("user_managers", [])
    cfg.setdefault("min_free_gib", 10)
    cfg.setdefault("psi_avg60_max", 20.0)
    cfg.setdefault("settle_sec", 60)
    cfg.setdefault("probe_window_sec", 600)
    cfg.setdefault("probe_interval_sec", 15)
    cfg.setdefault("gate_timeout_sec", 60)
    cfg.setdefault("reboot_pending_alert_hours", 72)
    cfg.setdefault("marker_dir", None)
    cfg.setdefault("signer_identity", "nas")
    return cfg


# ── journal + receipts ───────────────────────────────────────────────────────


def journal(state, reason, **fields):
    line = f"update-adopt: state={state} reason={reason}"
    extra = " ".join(f"{k}={v}" for k, v in fields.items() if v is not None)
    print(line + (" " + extra if extra else ""), flush=True)
    if shutil.which("logger") is None:
        return
    payload = [
        f"MESSAGE={line}",
        "SYSLOG_IDENTIFIER=update-adopt",
        f"UPDATE_ADOPT_STATE={state}",
        f"UPDATE_ADOPT_REASON={reason}",
    ]
    payload += [
        f"UPDATE_ADOPT_{k.upper()}={v}" for k, v in fields.items() if v is not None
    ]
    try:
        subprocess.run(
            ["logger", "--journald"],
            input="\n".join(payload) + "\n",
            text=True,
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def load_state():
    try:
        with open(os.path.join(STATE_DIR, "state.json")) as stream:
            state = json.load(stream)
    except (OSError, ValueError):
        state = {}
    state.setdefault("state", "idle")
    state.setdefault("rejected", [])
    return state


def atomic_write_json(path, value):
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".tmp-")
    with os.fdopen(fd, "w") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(tmp, path)


def save_state(state):
    state["updated_at"] = now_iso()
    atomic_write_json(os.path.join(STATE_DIR, "state.json"), state)


def receipt(kind, **data):
    directory = os.path.join(STATE_DIR, "receipts")
    os.makedirs(directory, exist_ok=True)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    body = {"kind": kind, "at": now_iso(), **data}
    atomic_write_json(os.path.join(directory, f"{stamp}-{kind}.json"), body)
    names = sorted(n for n in os.listdir(directory) if n.endswith(".json"))
    for name in names[:-RECEIPTS_KEEP]:
        try:
            os.unlink(os.path.join(directory, name))
        except OSError:
            pass
    return body


# ── facts about this host ────────────────────────────────────────────────────


def resolve(path):
    try:
        return os.path.realpath(path) if os.path.lexists(path) else None
    except OSError:
        return None


def revision_of(system_path):
    """The closure's own {rev, dirty, lastModified}; None when absent."""
    if not system_path:
        return None
    try:
        with open(os.path.join(system_path, REVISION_FILE)) as stream:
            value = json.load(stream)
    except (OSError, ValueError):
        return None
    return value if isinstance(value, dict) else None


def boot_differs(candidate, booted):
    if not booted:
        return True
    for name in BOOT_FILES:
        a, b = os.path.join(candidate, name), os.path.join(booted, name)
        if os.path.islink(a) or os.path.islink(b):
            if resolve(a) != resolve(b):
                return True
        else:
            try:
                with open(a, "rb") as sa, open(b, "rb") as sb:
                    if sa.read() != sb.read():
                        return True
            except OSError:
                if os.path.exists(a) != os.path.exists(b):
                    return True
    return False


def run(argv, timeout=None, **kwargs):
    try:
        return subprocess.run(
            argv, capture_output=True, text=True, timeout=timeout, check=False, **kwargs
        )
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(argv, 124, "", "timeout")
    except OSError as error:
        return subprocess.CompletedProcess(argv, 127, "", str(error))


def free_gib(path):
    probe = path
    while probe and not os.path.exists(probe):
        probe = os.path.dirname(probe)
    stats = os.statvfs(probe or "/")
    return stats.f_bavail * stats.f_frsize / (1024**3)


def psi_some_avg60():
    try:
        with open(PSI_MEMORY) as stream:
            for line in stream:
                if line.startswith("some "):
                    for part in line.split():
                        if part.startswith("avg60="):
                            return float(part.split("=", 1)[1])
    except (OSError, ValueError):
        return None
    return None


def failed_units(user=None):
    argv = ["systemctl"]
    if user:
        argv += ["--user", "-M", f"{user}@"]
    argv += ["list-units", "--failed", "--plain", "--no-legend", "--no-pager"]
    result = run(argv, timeout=30)
    if result.returncode != 0:
        return None
    return {line.split()[0] for line in result.stdout.splitlines() if line.strip()}


def unit_active(unit, user=None):
    argv = ["systemctl"]
    if user:
        argv += ["--user", "-M", f"{user}@"]
    argv += ["is-active", "--quiet", unit]
    return run(argv, timeout=30).returncode == 0


# ── the candidate ────────────────────────────────────────────────────────────


class Refusal(Exception):
    def __init__(self, reason, detail="", rc=0):
        super().__init__(reason)
        self.reason = reason
        self.detail = detail
        self.rc = rc


def fetch_candidate(cfg, workdir):
    base = cfg["candidate_url"].rstrip("/") + "/" + cfg["host"]
    manifest_path = os.path.join(workdir, "manifest.json")
    sig_path = manifest_path + ".sig"
    for url, dest in ((base + "/manifest.json", manifest_path), (base + "/manifest.json.sig", sig_path)):
        result = run(["curl", "-fsS", "-m", "10", "-o", dest, url], timeout=30)
        if result.returncode != 0:
            raise Refusal("fetch-failed", f"{url}: {result.stderr.strip()}"[:300], rc=0)
    with open(manifest_path, "rb") as stream:
        raw = stream.read()
    verify = run(
        [
            "ssh-keygen", "-Y", "verify",
            "-f", cfg["allowed_signers"],
            "-I", cfg["signer_identity"],
            "-n", "fleet-update",
            "-s", sig_path,
        ],
        timeout=30,
        stdin=open(manifest_path, "rb"),
    )
    if verify.returncode != 0:
        raise Refusal("bad-signature", (verify.stderr or verify.stdout).strip()[:300], rc=1)
    try:
        manifest = json.loads(raw)
    except ValueError as error:
        raise Refusal("bad-manifest", str(error), rc=1)
    if not isinstance(manifest, dict) or manifest.get("schema") != 1:
        raise Refusal("bad-manifest", "schema is not 1", rc=1)
    if manifest.get("host") != cfg["host"]:
        raise Refusal("host-mismatch", f"manifest names {manifest.get('host')!r}", rc=1)
    pattern = re.escape(STORE_DIR) + r"/[0-9a-df-np-sv-z]{32}-nixos-system-" + re.escape(cfg["host"]) + r"-[^/\s]+"
    store_path = manifest.get("store_path")
    if not isinstance(store_path, str) or not re.fullmatch(pattern, store_path):
        raise Refusal("bad-manifest", f"store_path {store_path!r} is not this host's system", rc=1)
    if not isinstance(manifest.get("last_modified"), int):
        raise Refusal("bad-manifest", "last_modified is not an integer", rc=1)
    return manifest


def downgrade_check(current_path, candidate_rev):
    """Refuse unless the running generation is clean, known, and older."""
    current = revision_of(current_path)
    if current is None or current.get("rev") in (None, "", "unknown"):
        raise Refusal("local-generation-newer", "current generation has no recorded revision")
    if current.get("dirty"):
        raise Refusal("local-generation-newer", f"current generation is a dirty tree ({current.get('rev')})")
    if not candidate_rev or not isinstance(candidate_rev.get("lastModified"), int):
        raise Refusal("local-generation-newer", "candidate has no recorded revision")
    if int(current.get("lastModified", 0)) >= candidate_rev["lastModified"]:
        raise Refusal(
            "local-generation-newer",
            f"current {current.get('rev')} ({current.get('lastModified')}) is not older than "
            f"candidate {candidate_rev.get('rev')} ({candidate_rev['lastModified']})",
        )


def add_root(name, path):
    os.makedirs(GCROOTS, exist_ok=True)
    return run(["nix-store", "--realise", path, "--add-root", os.path.join(GCROOTS, name)], timeout=6 * 3600)


def drop_root(name):
    try:
        os.unlink(os.path.join(GCROOTS, name))
    except OSError:
        pass


def clear_reboot_marker(cfg):
    if cfg.get("marker_dir"):
        try:
            os.unlink(os.path.join(cfg["marker_dir"], "update-adopt-reboot-pending"))
        except OSError:
            pass


def reconcile_reboot(cfg, state):
    """Clear a pending reboot once the booted system is the profile."""
    if not state.get("pending_reboot"):
        clear_reboot_marker(cfg)
        return
    if resolve(BOOTED) == resolve(PROFILE):
        journal("known-good", "rebooted-into-candidate", store_path=resolve(BOOTED))
        receipt("rebooted", store_path=resolve(BOOTED))
        state["pending_reboot"] = None
        state["state"] = "known-good"
        state["last_known_good"] = resolve(BOOTED)
        clear_reboot_marker(cfg)
        return
    since = state["pending_reboot"].get("since_epoch", now_epoch())
    hours = (now_epoch() - since) / 3600
    if hours >= cfg["reboot_pending_alert_hours"] and cfg.get("marker_dir"):
        os.makedirs(cfg["marker_dir"], exist_ok=True)
        with open(os.path.join(cfg["marker_dir"], "update-adopt-reboot-pending"), "w") as stream:
            stream.write(
                f"update-adopt reboot pending {int(hours)}h for {state['pending_reboot'].get('store_path')}"
                " — the new kernel is installed with `boot`; reboot when convenient\n"
            )


def refuse(cfg, state, refusal, candidate=None):
    state["last_refusal"] = {"reason": refusal.reason, "detail": refusal.detail, "at": now_iso()}
    if candidate:
        state["last_refusal"]["store_path"] = candidate
    journal("refused", refusal.reason, detail=refusal.detail, store_path=candidate)
    receipt("refused", reason=refusal.reason, detail=refusal.detail, store_path=candidate)
    save_state(state)
    return refusal.rc


# ── stage ────────────────────────────────────────────────────────────────────


def stage(cfg, force=False, trigger=True):
    lock = try_lock()
    if lock is None:
        journal("busy", "activation-running")
        return 0
    try:
        return _stage(cfg, force, trigger)
    finally:
        lock.close()


def _stage(cfg, force, trigger):
    state = load_state()
    reconcile_reboot(cfg, state)
    state["last_attempt"] = now_iso()
    current, profile = resolve(CURRENT), resolve(PROFILE)
    with tempfile.TemporaryDirectory() as workdir:
        try:
            manifest = fetch_candidate(cfg, workdir)
        except Refusal as refusal:
            return refuse(cfg, state, refusal)
    candidate = manifest["store_path"]
    state["candidate"] = {
        "store_path": candidate,
        "rev": manifest.get("rev"),
        "last_modified": manifest.get("last_modified"),
        "built_at": manifest.get("built_at"),
        "seen_at": now_iso(),
    }

    if candidate == current:
        state["state"] = "known-good"
        state["last_known_good"] = current
        drop_root("candidate")
        journal("known-good", "candidate-is-current", store_path=candidate)
        save_state(state)
        return 0
    if candidate == profile and state.get("pending_reboot"):
        state["state"] = "pending-reboot"
        journal("pending-reboot", "candidate-installed-for-boot", store_path=candidate)
        save_state(state)
        return 0
    if candidate in state["rejected"] and not force:
        state["state"] = "rejected"
        journal("rejected", "candidate-previously-failed", store_path=candidate)
        save_state(state)
        return 0
    if cfg["policy"] == "manual":
        state["state"] = "candidate-seen"
        journal("candidate-seen", "policy-manual", store_path=candidate)
        receipt("candidate-seen", store_path=candidate, rev=manifest.get("rev"))
        save_state(state)
        return 0
    if not force:
        try:
            downgrade_check(current, {"rev": manifest.get("rev"), "lastModified": manifest["last_modified"]})
        except Refusal as refusal:
            return refuse(cfg, state, refusal, candidate)

    free = free_gib(ROOT + STORE_DIR)
    if free < cfg["min_free_gib"]:
        state["state"] = "waiting-for-safe-window"
        state["last_deferral"] = {"reason": f"disk: {free:.1f} GiB free < {cfg['min_free_gib']}", "at": now_iso()}
        journal("waiting-for-safe-window", "disk", free_gib=f"{free:.1f}")
        save_state(state)
        return 0

    realised = add_root("candidate", candidate)
    if realised.returncode != 0:
        refusal = Refusal("realise-failed", realised.stderr.strip()[-300:], rc=1)
        return refuse(cfg, state, refusal, candidate)
    verified = run(["nix", "store", "verify", "--no-contents", "--recursive", candidate], timeout=3600)
    if verified.returncode != 0:
        drop_root("candidate")
        refusal = Refusal("verify-failed", verified.stderr.strip()[-300:], rc=1)
        return refuse(cfg, state, refusal, candidate)

    # The closure's own revision file is authoritative; the manifest's fields
    # only let us skip a pointless download.
    candidate_rev = revision_of(candidate)
    state["candidate"]["revision"] = candidate_rev
    if not force:
        try:
            downgrade_check(current, candidate_rev)
        except Refusal as refusal:
            drop_root("candidate")
            return refuse(cfg, state, refusal, candidate)

    state["candidate"]["reboot_required"] = boot_differs(candidate, resolve(BOOTED))
    state["state"] = "closure-ready"
    journal("closure-ready", "realised", store_path=candidate,
            reboot_required=state["candidate"]["reboot_required"])
    receipt("closure-ready", store_path=candidate, revision=candidate_rev,
            reboot_required=state["candidate"]["reboot_required"])
    save_state(state)
    if trigger and cfg["policy"] == "rolling":
        run(["systemctl", "start", "--no-block", "update-adopt-activate.service"], timeout=30)
    return 0


# ── activate ─────────────────────────────────────────────────────────────────


def try_lock():
    os.makedirs(os.path.dirname(LOCK_PATH) or "/", exist_ok=True)
    handle = open(LOCK_PATH, "a")
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        handle.close()
        return None
    return handle


def builtin_gates(cfg):
    for pattern in ("switch-to-configuration", "nixos-rebuild"):
        found = run(["pgrep", "-f", pattern], timeout=10)
        if found.returncode == 0 and found.stdout.strip():
            return f"rebuild-running: a {pattern} process is running"
    if unit_active("nixos-rebuild-switch-to-configuration.service"):
        return "rebuild-running: nixos-rebuild-switch-to-configuration.service is active"
    free = free_gib(ROOT + "/nix/var/nix/profiles")
    if free < cfg["min_free_gib"]:
        return f"disk: {free:.1f} GiB free < {cfg['min_free_gib']}"
    psi = psi_some_avg60()
    if psi is not None and psi >= cfg["psi_avg60_max"]:
        return f"memory-pressure: some avg60={psi} >= {cfg['psi_avg60_max']}"
    return None


def host_gates(cfg):
    for gate in cfg["gates"]:
        result = run(gate["argv"], timeout=cfg["gate_timeout_sec"])
        message = (result.stdout.strip() or result.stderr.strip())[:300]
        if result.returncode == 0:
            continue
        if result.returncode == 1:
            return f"{gate['name']}: {message or 'busy'}"
        return f"{gate['name']}: unknown (rc {result.returncode}) {message}".rstrip()
    return None


def snapshot(cfg):
    system_failed = failed_units() or set()
    users = {user: failed_units(user) or set() for user in cfg["user_managers"]}
    active = [
        unit for unit in cfg["critical_units"]
        if unit_active(unit["unit"], unit.get("user"))
    ]
    return {"system_failed": system_failed, "user_failed": users, "critical_active": active}


def probe_once(cfg, before):
    failures = []
    running = run(["systemctl", "is-system-running"], timeout=30).stdout.strip()
    if running not in ("running", "degraded"):
        failures.append(f"is-system-running: {running or 'no answer'}")
    now_failed = failed_units()
    if now_failed is None:
        failures.append("system manager did not answer list-units --failed")
    else:
        new = sorted(now_failed - before["system_failed"])
        if new:
            failures.append("new failed system units: " + ", ".join(new))
    for user, old in before["user_failed"].items():
        current = failed_units(user)
        if current is None:
            failures.append(f"user manager {user}@ did not answer")
            continue
        new = sorted(current - old)
        if new:
            failures.append(f"new failed {user} units: " + ", ".join(new))
    for unit in before["critical_active"]:
        if not unit_active(unit["unit"], unit.get("user")):
            owner = f"{unit['user']}@" if unit.get("user") else "system"
            failures.append(f"critical unit {unit['unit']} ({owner}) was active and is not")
    for probe in cfg["probes"]:
        result = run(probe["argv"], timeout=probe.get("timeout_sec", 30))
        if result.returncode != 0:
            message = (result.stdout.strip() or result.stderr.strip())[:200]
            failures.append(f"probe {probe['name']}: {message or 'rc ' + str(result.returncode)}")
    return failures


def probe(cfg, before):
    time.sleep(cfg["settle_sec"])
    deadline = time.monotonic() + cfg["probe_window_sec"]
    while True:
        failures = probe_once(cfg, before)
        if not failures or time.monotonic() >= deadline:
            return failures
        time.sleep(cfg["probe_interval_sec"])


def switch_to(path, action):
    return run(
        [
            "systemd-run", "--unit=update-adopt-switch", "--wait", "--collect", "--quiet",
            "--service-type=exec", "--no-ask-password",
            "--setenv=NIXOS_INSTALL_BOOTLOADER=",
            os.path.join(path, "bin", "switch-to-configuration"), action,
        ],
        timeout=3600,
    )


def set_profile(path):
    return run(["nix-env", "-p", PROFILE, "--set", path], timeout=600)


def activate(cfg, force=False):
    lock = try_lock()
    if lock is None:
        state = load_state()
        return refuse(cfg, state, Refusal("activation-running", "another activation holds the lock"))
    try:
        return _activate(cfg, force)
    finally:
        lock.close()


def _activate(cfg, force):
    state = load_state()
    reconcile_reboot(cfg, state)
    state["last_attempt"] = now_iso()
    candidate = (state.get("candidate") or {}).get("store_path")
    if state["state"] not in ("closure-ready", "waiting-for-safe-window") or not candidate:
        journal(state["state"], "nothing-to-activate")
        save_state(state)
        return 0
    if cfg["policy"] != "rolling" and not force:
        journal(state["state"], f"policy-{cfg['policy']}", store_path=candidate)
        save_state(state)
        return 0
    current = resolve(CURRENT)
    if candidate == current:
        state["state"] = "known-good"
        state["last_known_good"] = current
        journal("known-good", "candidate-is-current", store_path=candidate)
        save_state(state)
        return 0
    if run(["nix-store", "--check-validity", candidate], timeout=60).returncode != 0:
        state["state"] = "idle"
        journal("idle", "candidate-not-in-store", store_path=candidate)
        save_state(state)
        return 0
    if not force:
        if candidate in state["rejected"]:
            state["state"] = "rejected"
            journal("rejected", "candidate-previously-failed", store_path=candidate)
            save_state(state)
            return 0
        try:
            downgrade_check(current, revision_of(candidate))
        except Refusal as refusal:
            state["state"] = "refused"
            return refuse(cfg, state, refusal, candidate)

    deferral = builtin_gates(cfg) or host_gates(cfg)
    if deferral:
        state["state"] = "waiting-for-safe-window"
        state["last_deferral"] = {"reason": deferral, "at": now_iso(), "store_path": candidate}
        journal("waiting-for-safe-window", deferral.split(":", 1)[0], detail=deferral, store_path=candidate)
        receipt("deferred", reason=deferral, store_path=candidate)
        save_state(state)
        return 0

    before = snapshot(cfg)
    previous = resolve(PROFILE)
    reboot_required = bool((state.get("candidate") or {}).get("reboot_required"))
    action = "boot" if reboot_required else "switch"
    state["state"] = "activating"
    state["activation"] = {"store_path": candidate, "previous": previous, "action": action, "started_at": now_iso()}
    journal("activating", action, store_path=candidate, previous=previous)
    save_state(state)

    profiled = set_profile(candidate)
    result = switch_to(candidate, action) if profiled.returncode == 0 else profiled
    if action == "boot":
        if result.returncode == 0:
            state["state"] = "pending-reboot"
            state["pending_reboot"] = {"store_path": candidate, "since": now_iso(), "since_epoch": now_epoch()}
            drop_root("candidate")
            journal("pending-reboot", "kernel-or-initrd-changed", store_path=candidate)
            receipt("pending-reboot", store_path=candidate, previous=previous)
            save_state(state)
            return 0
        failures = [f"switch-to-configuration boot exited {result.returncode}: {result.stderr.strip()[-200:]}"]
    elif result.returncode != 0:
        failures = [f"switch-to-configuration switch exited {result.returncode}: {result.stderr.strip()[-200:]}"]
    else:
        state["state"] = "probing"
        journal("probing", "switched", store_path=candidate)
        save_state(state)
        failures = probe(cfg, before)

    if not failures:
        state["state"] = "known-good"
        state["last_known_good"] = candidate
        add_root("last-known-good", candidate)
        drop_root("candidate")
        journal("known-good", "probes-passed", store_path=candidate)
        receipt("known-good", store_path=candidate, previous=previous)
        save_state(state)
        return 0

    # ── local rollback ───────────────────────────────────────────────────────
    journal("failed", "probe-failed", detail="; ".join(failures)[:500], store_path=candidate)
    rollback = {"previous": previous}
    if previous and previous != candidate:
        back = set_profile(previous)
        rollback["profile_rc"] = back.returncode
        back_switch = switch_to(previous, action) if back.returncode == 0 else back
        rollback["switch_rc"] = back_switch.returncode
        if action == "switch" and back_switch.returncode == 0:
            reprobe = probe(cfg, before)
            rollback["reprobe_failures"] = reprobe
            rollback["result"] = "rolled-back" if not reprobe else "rolled-back-unhealthy"
        else:
            rollback["result"] = "rolled-back" if back_switch.returncode == 0 else "rollback-failed"
    else:
        rollback["result"] = "rollback-failed"
    if candidate not in state["rejected"]:
        state["rejected"].append(candidate)
    state["rejected"] = state["rejected"][-20:]
    state["state"] = rollback["result"]
    drop_root("candidate")
    journal(rollback["result"], "rollback", store_path=candidate, previous=previous)
    receipt("rolled-back", store_path=candidate, failures=failures, rollback=rollback)
    save_state(state)
    return 1


# ── status ───────────────────────────────────────────────────────────────────


def status(cfg):
    state = load_state()
    current = resolve(CURRENT)
    out = {
        "host": cfg["host"],
        "policy": cfg["policy"],
        "state": state.get("state"),
        "current": current,
        "current_revision": revision_of(current),
        "booted": resolve(BOOTED),
        "profile": resolve(PROFILE),
        "candidate": state.get("candidate"),
        "last_attempt": state.get("last_attempt"),
        "last_refusal": state.get("last_refusal"),
        "last_deferral": state.get("last_deferral"),
        "last_known_good": state.get("last_known_good"),
        "pending_reboot": state.get("pending_reboot"),
        "rejected": state.get("rejected"),
        "updated_at": state.get("updated_at"),
    }
    json.dump(out, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(prog="update-adopt")
    sub = parser.add_subparsers(dest="verb", required=True)
    sub.add_parser("stage")
    sub.add_parser("activate")
    adopt = sub.add_parser("adopt")
    adopt.add_argument("--force", action="store_true")
    stat = sub.add_parser("status")
    stat.add_argument("--json", action="store_true", help="accepted; output is always JSON")
    args = parser.parse_args(argv)
    cfg = load_config()
    if args.verb == "stage":
        return stage(cfg)
    if args.verb == "activate":
        return activate(cfg)
    if args.verb == "status":
        return status(cfg)
    rc = stage(cfg, force=args.force, trigger=False)
    if rc != 0 or load_state().get("state") != "closure-ready":
        return rc
    return activate(cfg, force=args.force)


if __name__ == "__main__":
    sys.exit(main())
