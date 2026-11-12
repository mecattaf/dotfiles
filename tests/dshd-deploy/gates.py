#!/usr/bin/env python3
"""Read-only NAS gates for D16. No deploy, signal, reload, or credential reads."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def command(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=30).stdout


def unit_identity(name, user=False):
    args = ["systemctl", *(["--user"] if user else []), "show", name]
    for field in ("Id", "LoadState", "ActiveState", "SubState", "InvocationID", "MainPID", "ControlGroup"):
        args.extend(["-p", field])
    result = dict(line.split("=", 1) for line in command(*args).splitlines() if "=" in line)
    if result.get("LoadState") != "loaded" or not result.get("InvocationID"):
        raise ValueError(f"cannot establish a live identity for {name}: {result}")
    return result


def process_identity(proc):
    # The comm field can contain spaces and parentheses; split after its last ')'.
    stat = (proc / "stat").read_text().rsplit(")", 1)[1].split()
    return {
        "pid": int(proc.name),
        "startTicks": int(stat[19]),  # field 22, measured since boot
        "cgroup": (proc / "cgroup").read_text().splitlines(),
    }


def snapshot(agency_units):
    processes = []
    for proc in Path("/proc").glob("[0-9]*"):
        try:
            args = (proc / "cmdline").read_bytes().split(b"\0")
            comm = (proc / "comm").read_text().strip()
            # Native dsh is commonly a node process. Match its executable or
            # package entrypoint, never a later prompt argument. Do not store argv.
            entrypoints = [arg.decode(errors="replace") for arg in args[:3]]
            if comm == "dsh" or any(
                Path(arg).name == "dsh" or "/@deepseek-ai/dsh/" in arg
                for arg in entrypoints
            ):
                processes.append(process_identity(proc))
        except (FileNotFoundError, ProcessLookupError):
            # A disappearing process makes a snapshot uncertain. Retry the whole
            # command rather than declaring an incomplete process inventory valid.
            raise ValueError(f"process {proc.name} changed during snapshot; retry") from None
    units = {
        f"system:user@{os.getuid()}.service": unit_identity(f"user@{os.getuid()}.service"),
        **{f"user:{name}": unit_identity(name, user=True)
           for name in ["herdr.service", "herdr-web-ui.service", *agency_units]},
    }
    dshd = command("systemctl", "--user", "list-units", "--all", "--plain", "--no-legend",
                   "--no-pager", "dshd@*.service").strip()
    return {
        "bootId": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
        "units": units,
        "dsh": sorted(processes, key=lambda item: item["pid"]),
        "dshdUnits": dshd,
    }


def busy_reasons():
    """Read-only, conservative admission check. Never stop an existing job.

    Formerly update-check's busy_reasons(), inlined unchanged in policy when
    that program left the repository: the five-minute load against half the
    CPUs, any Nix builder, build or activation command, and every Herdr pane
    whose agent is neither idle, done nor blocked.
    """
    reasons = []
    load = os.getloadavg()[1]
    limit = max(1.0, (os.cpu_count() or 1) * 0.5)
    if load >= limit:
        reasons.append(f"five-minute load {load:.1f} >= {limit:.1f}")
    for proc in Path("/proc").glob("[0-9]*/cmdline"):
        try:
            args = proc.read_bytes().decode(errors="replace").strip("\0").split("\0")
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        try:
            uid_line = next(line for line in (proc.parent / "status").read_text().splitlines() if line.startswith("Uid:"))
            if 30000 <= int(uid_line.split()[1]) < 31000:
                reasons.append(f"Nix builder running (pid {proc.parent.name})")
        except (FileNotFoundError, ProcessLookupError, PermissionError, StopIteration):
            pass
        words = [Path(arg).name for arg in args[:3]]
        if any(word in {"nixos-rebuild", "nixos-rebuild-ng", "home-manager", "deploy-rs", "nh"} for word in words):
            reasons.append(f"build or activation command running (pid {proc.parent.name})")
        name = Path(args[0]).name if args else ""
        if (name in {"nix", "nix-build", "nix-store", "nixos-rebuild", "nixos-rebuild-ng"}
                and (name.startswith("nixos-rebuild") or name == "nix-build"
                     or args[1:3] == ["flake", "check"]
                     or any(a in {"build", "develop", "shell", "-r", "--realise"} for a in args[1:]))):
            reasons.append(f"Nix work running (pid {proc.parent.name})")
    # Calling pane list is read-only and cannot start or attach a session.
    try:
        listing = subprocess.run(["herdr", "pane", "list"], capture_output=True, text=True, timeout=15)
        if listing.returncode != 0:
            raise ValueError(f"herdr pane list exited {listing.returncode}: {(listing.stderr or listing.stdout).strip()[-800:]}")
        panes = json.loads(listing.stdout)["result"]["panes"]
        if not isinstance(panes, list):
            raise ValueError("panes is not a list")
        for pane in panes:
            if pane.get("agent") and pane.get("agent_status") not in {"idle", "done", "blocked"}:
                reasons.append(f"Herdr pane {pane.get('pane_id', '?')} is {pane.get('agent_status', 'unknown')}")
    except (OSError, subprocess.TimeoutExpired, ValueError, KeyError, TypeError) as e:
        raise ValueError(f"cannot establish Herdr idleness: {e}") from e
    return reasons


def idle(deploying_pane):
    reasons = busy_reasons()
    pattern = re.compile(r"Herdr pane " + re.escape(deploying_pane) + r" is .+")
    ignored = [reason for reason in reasons if pattern.fullmatch(reason)]
    remaining = [reason for reason in reasons if not pattern.fullmatch(reason)]
    print(json.dumps({"idle": not remaining, "reasons": remaining,
                      "excludedDeployingPane": deploying_pane, "excludedReasons": ignored}, indent=2))
    return int(bool(remaining))


def identities(candidate):
    live_dsh = Path("/etc/profiles/per-user/tom/bin/dsh").resolve(strict=True).parent.parent
    live_drv = command("nix-store", "--query", "--deriver", str(live_dsh)).strip()
    unit = Path("/run/current-system/etc/systemd/system/home-manager-tom.service").read_text()
    generations = re.findall(r"/nix/store/[^\s;]+-home-manager-generation", unit)
    if len(set(generations)) != 1 or live_drv == "unknown-deriver":
        raise ValueError("live dsh deriver or Home Manager generation could not be identified")
    expected = {"dshDrv": live_drv, "homeManager": generations[0]}
    print(json.dumps({"live": expected, "candidate": candidate}, indent=2))
    return int(expected != candidate)


def tree_manifest(root):
    root = root.resolve(strict=True)
    result = {}
    # Resolve top-level directory links, while keeping aliases and wants links
    # visible. Unit-file symlinks are compared by bytes rather than store hash.
    for directory, directories, files in os.walk(root, followlinks=True):
        for name in files:
            path = Path(directory) / name
            relative = str(path.relative_to(root))
            if path.is_symlink() and "/" in relative:
                result[relative] = {"link": os.readlink(path),
                                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
            else:
                result[relative] = {"sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        for name in directories:
            path = Path(directory) / name
            result[str(path.relative_to(root)) + "/"] = {"directory": True}
    return result


def user_tree(candidate, live):
    before, after = tree_manifest(live), tree_manifest(candidate)
    additions = sorted(set(after) - set(before))
    removed = sorted(set(before) - set(after))
    changed = sorted(key for key in set(before) & set(after) if before[key] != after[key])
    expected = {"dshd@.service", "dshd.target", "default.target.wants/dshd.target"}
    allowed = expected | {"default.target.wants/"}
    print(json.dumps({"added": additions, "removed": removed, "changed": changed}, indent=2))
    return int(bool(removed or changed) or not expected.issubset(additions)
               or not set(additions).issubset(allowed))


def eval_user_tree(baseline, candidate):
    live = str(Path("/run/current-system/etc/systemd/user").resolve(strict=True))
    problems = []
    if baseline["userTree"] != live:
        problems.append(f"evaluated baseline user tree {baseline['userTree']} is not live {live}")
    for key in ("systemd", "packages", "additionalUpstreamUserUnits"):
        if baseline[key] != candidate[key]:
            problems.append(f"user-tree input changed: {key}")
    old, new = baseline["units"], candidate["units"]
    if set(new) - set(old) != {"dshd@.service", "dshd.target"}:
        problems.append("unit additions must be exactly dshd@.service and dshd.target")
    for key in old:
        if old[key] != new.get(key):
            problems.append(f"existing unit changed or removed: {key}")
    if new.get("dshd.target", {}).get("wantedBy") != ["default.target"]:
        problems.append("dshd.target must have only its default.target wants link")
    for name in ("dshd.target", "dshd@.service"):
        unit = new.get(name, {})
        if (unit.get("requiredBy") or unit.get("upheldBy") or unit.get("aliases")
                or (name == "dshd@.service" and unit.get("wantedBy"))):
            problems.append(f"unexpected instance or autostart link for {name}")
    print(json.dumps({"ok": not problems, "problems": problems}, indent=2))
    return int(bool(problems))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="verb", required=True)
    admission = sub.add_parser("idle", help="load, Nix and Herdr busy reasons, except one deploying pane")
    admission.add_argument("--deploying-pane", required=True)
    snap = sub.add_parser("snapshot", help="emit protected unit and every native dsh process identity")
    snap.add_argument("--agency-unit", action="append", default=None,
                      help="user unit or scope; repeat for every Agency Web owner (default agency-web.service)")
    compare = sub.add_parser("compare", help="require identical snapshots and no dshd instances")
    compare.add_argument("before", type=Path)
    compare.add_argument("after", type=Path)
    identity = sub.add_parser("identity", help="compare candidate eval JSON with the actual live dsh/HM")
    identity.add_argument("candidate", type=Path)
    units = sub.add_parser("user-tree", help="compare realized candidate etc/systemd/user with live bytes/links")
    units.add_argument("candidate", type=Path)
    units.add_argument("--live", type=Path, default=Path("/run/current-system/etc/systemd/user"))
    evaluated = sub.add_parser("eval-user-tree", help="prove evaluated unit inputs against an exactly live baseline")
    evaluated.add_argument("baseline", type=Path)
    evaluated.add_argument("candidate", type=Path)
    args = parser.parse_args()
    if args.verb == "idle":
        return idle(args.deploying_pane)
    if args.verb == "snapshot":
        print(json.dumps(snapshot(args.agency_unit or ["agency-web.service"]), indent=2, sort_keys=True))
        return 0
    if args.verb == "identity":
        return identities(json.loads(args.candidate.read_text()))
    if args.verb == "user-tree":
        return user_tree(args.candidate, args.live)
    if args.verb == "eval-user-tree":
        return eval_user_tree(json.loads(args.baseline.read_text()), json.loads(args.candidate.read_text()))
    before = json.loads(args.before.read_text())
    after = json.loads(args.after.read_text())
    if before != after or before["dshdUnits"] or after["dshdUnits"]:
        print(json.dumps({"before": before, "after": after}, indent=2, sort_keys=True))
        return 1
    print("identical protected units and dsh processes; no dshd instances")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"dshd deploy gate: {error}", file=sys.stderr)
        sys.exit(2)
