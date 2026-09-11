"""Three routing tiers on one radio; only controlled windows leave Freebox.

Run as root from the NixOS timers. Probe marks select private routing tables,
so a healthy BE550 bypass cannot conceal a broken NAS forwarding path. Tables
42001/42003 and rule priorities 101/103 are reserved exclusively for this unit.

Modes: `tick` is the failover watchdog, `return` the 04:00 controlled return,
`boot` the same return polled every 20 s during the first five minutes after
boot. NetworkManager picks Freebox at boot whenever the BE550 6 GHz SSID is
missing from the first scan (2026-09-11 21:00:27: "auto-activating connection
'Freebox-AB3ACE'" 3 s after wlp192s0 came up; thomas-6ghz only returned with
the old 2-minute one-shot at 21:02:24), so `boot` retries until the primary is
associated, is a no-op once it is, and once the window has closed stops its
own timer (timers.target restarts it at the next boot).
"""
import contextlib
import fcntl
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import time

DEVICE = "wlp192s0"
PRIMARY = "thomas-6ghz"
FREEBOX = "Freebox-AB3ACE"
SOURCE = "10.42.0.2"
STATE = Path("/run/coordinator-uplink")
PATHS = {"nas": ("10.42.0.1", 42001, 101), "be550": ("10.42.0.3", 42003, 103)}
PUBLIC_DNS = ("1.1.1.1", "9.9.9.9")
FAILURES = 3


def command(*args, check=True):
    return subprocess.run(args, check=check, text=True, capture_output=True, timeout=35)


def active():
    return command("nmcli", "-g", "GENERAL.CONNECTION", "device", "show", DEVICE).stdout.strip()


def current_tier():
    gateway = command("nmcli", "-g", "IP4.GATEWAY", "device", "show", DEVICE).stdout.strip()
    return "be550" if gateway == PATHS["be550"][0] else "nas"


def cleanup_routes():
    for _, table, priority in PATHS.values():
        # Fully qualified deletion affects only this service's own marked rules.
        command("ip", "-4", "rule", "del", "priority", str(priority), "fwmark", str(table),
                "lookup", str(table), check=False)
        command("ip", "-4", "route", "flush", "table", str(table), check=False)


@contextlib.contextmanager
def probe_routes():
    cleanup_routes()  # Also recover leftovers after an interrupted prior check.
    try:
        for gateway, table, priority in PATHS.values():
            command("ip", "-4", "route", "add", "table", str(table), "10.42.0.0/24",
                    "dev", DEVICE, "src", SOURCE)
            command("ip", "-4", "route", "add", "table", str(table), "default",
                    "via", gateway, "dev", DEVICE)
            # If the link route disappears, terminate lookup rather than falling
            # through to another table and falsely validating a different path.
            command("ip", "-4", "route", "add", "table", str(table), "unreachable",
                    "default", "metric", "32767")
            command("ip", "-4", "rule", "add", "priority", str(priority), "fwmark",
                    str(table), "lookup", str(table))
        yield
    finally:
        cleanup_routes()


def dns_alive(server, mark, name="example.com"):
    # An explicit UDP A query avoids libc/resolved caches and DNS from another
    # interface. Check transaction, response status, and a nonempty answer.
    ident = os.urandom(2)
    packet = ident + struct.pack("!HHHHH", 0x0100, 1, 0, 0, 0)
    packet += b"".join(bytes([len(label)]) + label.encode("ascii") for label in name.split("."))
    packet += b"\x00" + struct.pack("!HH", 1, 1)
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_MARK, mark)
            sock.bind((SOURCE, 0))
            sock.settimeout(2)
            sock.connect((server, 53))
            sock.send(packet)
            reply = sock.recv(4096)
            if len(reply) < 12 or reply[:2] != ident:
                return False
            flags, _, answers, _, _ = struct.unpack("!HHHHH", reply[2:12])
            return bool(flags & 0x8000) and not flags & 0x020F and answers > 0
    except OSError:
        return False


def probe(tier):
    gateway, mark, _ = PATHS[tier]
    reachable = any(command("ping", "-4", "-n", "-c1", "-W2", "-m", str(mark),
                            "-I", SOURCE, target, check=False).returncode == 0
                    for target in PUBLIC_DNS)
    resolvers = (gateway,) if tier == "nas" else PUBLIC_DNS
    return (reachable and any(dns_alive(server, mark) for server in resolvers)
            and (tier != "nas" or dns_alive(gateway, mark, "photos.internal")))


def apply_tier(tier):
    if active() != PRIMARY:  # A manual radio change during probing wins.
        return False
    gateway = PATHS[tier][0]
    dns = gateway if tier == "nas" else ",".join(PUBLIC_DNS)
    command("nmcli", "device", "modify", DEVICE, "ipv4.gateway", gateway,
            "ipv4.dns", dns, "ipv4.ignore-auto-dns", "yes")
    print(f"coordinator uplink: {tier}, gateway {gateway}, DNS {dns}", flush=True)
    return True


def switch_freebox():
    if active() == PRIMARY:
        command("nmcli", "connection", "up", FREEBOX)
        print("coordinator uplink: Freebox fallback", flush=True)


def load_state():
    try:
        return json.loads((STATE / "failures.json").read_text())
    except (OSError, ValueError):
        return {}


def save_state(state):
    temporary = STATE / "failures.tmp"
    temporary.write_text(json.dumps(state))
    temporary.replace(STATE / "failures.json")


def tick(state):
    if active() != PRIMARY:
        return {}  # Includes deliberate manual Freebox use; never preempt it.
    tier = current_tier()
    if probe(tier):
        return {}
    failures = state.get("failures", 0) + 1 if state.get("tier") == tier else 1
    if failures < FAILURES:
        return {"tier": tier, "failures": failures}
    if tier == "nas" and probe("be550"):
        apply_tier("be550")
    else:
        switch_freebox()
    return {}


def controlled_return():
    was_freebox = active() == FREEBOX
    if was_freebox:
        visible = command("nmcli", "-t", "-f", "SSID", "device", "wifi", "list",
                          "ifname", DEVICE, "--rescan", "yes").stdout.splitlines()
        if PRIMARY not in visible:
            return
        try:
            command("nmcli", "connection", "up", PRIMARY)
        except subprocess.SubprocessError:
            command("nmcli", "connection", "up", FREEBOX)
            return
        time.sleep(10)
    if active() != PRIMARY:
        return
    # Route tables must be installed after associating: the Freebox rail does
    # not own SOURCE. Never trust current default-route reachability here.
    try:
        with probe_routes():
            if probe("nas"):
                apply_tier("nas")
            elif probe("be550"):
                apply_tier("be550")
            else:
                switch_freebox()
    except (OSError, subprocess.SubprocessError):
        if was_freebox:
            switch_freebox()
        raise


BOOT_TIMER = "uplink-rail-reconcile.timer"


def stop_boot_timer():
    # Polled every 20 s; nothing is left to do until the next boot restarts it.
    command("systemctl", "stop", BOOT_TIMER, check=False)


def boot_window():
    # OnBootSec timers started by a midday rebuild may fire immediately. They
    # must not treat that activation as permission to leave a manual Freebox
    # session; real boot reconciliation is bounded to the first five minutes.
    return float(Path("/proc/uptime").read_text().split()[0]) <= 300


def main():
    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (STATE / "lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        if sys.argv[1:] in (["return"], ["boot"]):
            # Boot runs repeat every 20 s: once the primary is up they must
            # neither re-probe nor reset the watchdog's failure counter.
            if sys.argv[1] == "boot":
                if not boot_window():
                    stop_boot_timer()
                    return
                if active() == PRIMARY:
                    return
            controlled_return()
            save_state({})
        elif sys.argv[1:] == ["tick"]:
            if active() != PRIMARY:
                save_state({})
                return
            with probe_routes():
                save_state(tick(load_state()))
        else:
            raise SystemExit("usage: uplink.py {tick|return|boot}")


if __name__ == "__main__":
    main()
