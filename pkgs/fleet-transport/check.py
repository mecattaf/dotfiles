"""Read-only Tailscale observations; console expiry receipts remain authoritative."""

import argparse
import json
import subprocess
import sys


def check(status, policy, host):
    errors = []
    if status.get("BackendState") != "Running":
        errors.append("Tailscale is not Running")
    if (status.get("CurrentTailnet") or {}).get("MagicDNSSuffix") != policy["tailnetSuffix"]:
        errors.append("wrong tailnet")
    suffix = "." + policy["tailnetSuffix"] + "."
    nodes = {}
    for node in [status.get("Self") or {}, *(status.get("Peer") or {}).values()]:
        dns = node.get("DNSName", "")
        if dns.endswith(suffix):
            name = dns[:-len(suffix)]
            if name in nodes:
                errors.append(f"duplicate identity: {name}")
            nodes[name] = node
    for name in policy["hosts"]:
        node = nodes.get(name)
        if not node:
            errors.append(f"missing identity: {name}")
            continue
        if not node.get("Online"):
            errors.append(f"offline: {name}")
        if node.get("Expired") or node.get("KeyExpiry") not in (None, "0001-01-01T00:00:00Z"):
            errors.append(f"node key expires: {name}")
    self_node = status.get("Self") or {}
    if self_node.get("DNSName") != host + suffix:
        errors.append("local identity does not match the declared host")
    nas = nodes.get(policy["exitNode"], {})
    if not nas.get("ExitNodeOption"):
        errors.append("NAS exit-node approval is not visible")
    if policy["subnet"] not in (nas.get("PrimaryRoutes") or []):
        errors.append("NAS subnet approval is not visible")
    exit_status = status.get("ExitNodeStatus")
    if host == policy["exitNode"]:
        if exit_status:
            errors.append("NAS must not select an exit node")
    elif not (exit_status and nas.get("ID") and exit_status.get("ID") == nas["ID"] and exit_status.get("Online")):
        errors.append("NAS is not the active online exit node")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--policy", required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--status", help="Read a saved status JSON instead of querying the local daemon")
    args = parser.parse_args()
    try:
        with open(args.policy) as file:
            policy = json.load(file)
        if args.status:
            with open(args.status) as file:
                status = json.load(file)
        else:
            status = json.loads(subprocess.check_output(["tailscale", "status", "--json"], timeout=20))
        errors = check(status, policy, args.host)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"fleet-transport-check: {error}", file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print("PASS: four online identities, no reported key expiry, NAS exit/subnet approval and selection visible.")
    print("Also verify all four 'Key expiry disabled' entries in the admin console; this is not a traffic or hardware test.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
