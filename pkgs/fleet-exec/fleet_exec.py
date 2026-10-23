"""Execute a heavy command in an explicit compute-host checkout, without local fallback."""

import argparse
import shlex
import subprocess
import sys


def ssh_command(host, cwd, command):
    if host not in ("strix-coordinator", "strix-worker"):
        raise ValueError("choose strix-coordinator or strix-worker")
    if not cwd.startswith("/") or "\x00" in cwd:
        raise ValueError("--cwd must be an absolute path on the compute host")
    if not command:
        raise ValueError("supply a command after --")
    remote = f"cd -- {shlex.quote(cwd)} && exec {shlex.join(command)}"
    return [
        "ssh", "-T", "-oBatchMode=yes", "-oStrictHostKeyChecking=yes",
        "-oForwardAgent=no", "-oIdentitiesOnly=yes", "-oConnectTimeout=10",
        "-i", "/run/agenix/ssh-user-key", "-l", "tom", "--", host, remote,
    ]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host", choices=["strix-coordinator", "strix-worker"])
    parser.add_argument("--cwd", required=True, help="Existing absolute checkout path on the compute host")
    arguments = list(sys.argv[1:] if argv is None else argv)
    try:
        separator = arguments.index("--")
    except ValueError:
        parser.error("separate the command with --")
    args = parser.parse_args(arguments[:separator])
    try:
        command = ssh_command(args.host, args.cwd, arguments[separator + 1:])
        return subprocess.run(command, check=False).returncode
    except (OSError, ValueError) as error:
        print(f"fleet-exec: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
