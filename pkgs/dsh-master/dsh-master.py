"""dsh-master: install, check and report the rendered Master DSH profiles.

    dsh-master render [--from DIR] [--quiet]   copy the rendered files into $DSH_HOME
    dsh-master install [PROFILE...]           install each profile's plugins
    dsh-master check [PROFILE...]             assert the rows in each config dump
    dsh-master status                         rendered, installed, current

The rendered folders come from the package (pkgs/dsh-master/default.nix) or
from --from DIR, a `nix build .#dsh-master` result. render writes only
$DSH_HOME/profiles/master*/{cordis.patch.yml,package.json,.dsh-master.json},
each by temporary file and rename, and only when the content differs. It
never runs pnpm and never touches cordis.yml, pnpm-lock.yaml or node_modules,
which belong to dsh. install and check run the dsh that dshd runs (the
manifest's `dsh`): the fleet wrapper refuses `dsh plugin`, and its policy
overlays would hide what a dshd instance really composes.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

import yaml

NAME = re.compile(r"^master(-[a-z0-9][a-z0-9-]*)?$")
FILES = (("cordis.patch.yml", 0o644), ("package.json", 0o600))
STATE = ".dsh-master.json"
INSTALL_TIMEOUT = "600"


class Failure(Exception):
    pass


class Loader(yaml.SafeLoader):
    pass


# `!!js` expressions stay opaque strings; nothing is evaluated.
Loader.add_constructor("!!js", lambda loader, node: {"__js": loader.construct_scalar(node)})
Loader.add_constructor("tag:yaml.org,2002:js", lambda loader, node: {"__js": loader.construct_scalar(node)})


def default_source():
    # <out>/share/dsh-master/dsh-master.py -> <out>
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))


def dsh_home():
    return os.environ.get("DSH_HOME") or os.path.join(os.path.expanduser("~"), ".dsh")


def sha256(path):
    try:
        with open(path, "rb") as stream:
            return hashlib.sha256(stream.read()).hexdigest()
    except FileNotFoundError:
        return None


def load_manifest(source):
    with open(os.path.join(source, "manifest.json"), encoding="utf-8") as stream:
        manifest = json.load(stream)
    for name in manifest["profiles"]:
        if not NAME.match(name):
            raise Failure(f"manifest names profile {name!r}, which is not a Master profile")
    return manifest


def read_state(folder):
    try:
        with open(os.path.join(folder, STATE), encoding="utf-8") as stream:
            state = json.load(stream)
        return state if isinstance(state, dict) else {}
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def write_atomic(folder, name, data, mode):
    fd, temp = tempfile.mkstemp(prefix=f".{name}.", suffix=".dsh-master", dir=folder)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp, mode)
        os.replace(temp, os.path.join(folder, name))
    except BaseException:
        if os.path.exists(temp):
            os.unlink(temp)
        raise


def write_state(folder, state):
    text = json.dumps(state, indent=2, sort_keys=True) + "\n"
    path = os.path.join(folder, STATE)
    try:
        with open(path, encoding="utf-8") as stream:
            if stream.read() == text:
                return
    except FileNotFoundError:
        pass
    write_atomic(folder, STATE, text.encode("utf-8"), 0o644)


def profile_folder(home, name, create):
    profiles = os.path.join(home, "profiles")
    folder = os.path.join(profiles, name)
    for path in (profiles, folder):
        if os.path.islink(path):
            raise Failure(f"{path} is a symbolic link; dsh-master writes only real folders")
    if create:
        os.makedirs(folder, mode=0o755, exist_ok=True)
    if not os.path.isdir(folder):
        raise Failure(f"{folder} does not exist; run dsh-master render first")
    return folder


def dsh_of(args, manifest):
    dsh = args.dsh or manifest.get("dsh")
    if not dsh:
        raise Failure("no dsh to run: the manifest names none; pass --dsh")
    return dsh


def selected(manifest, names):
    unknown = [name for name in names if name not in manifest["profiles"]]
    if unknown:
        raise Failure(f"not a rendered Master profile: {', '.join(unknown)}")
    return names or sorted(manifest["profiles"])


def render(args):
    source = args.source
    manifest = load_manifest(source)
    home = dsh_home()
    if not os.path.isdir(home):
        print(f"dsh-master: {home} does not exist (dsh has never run here); nothing rendered", file=sys.stderr)
        return 0
    for name, profile in sorted(manifest["profiles"].items()):
        folder = profile_folder(home, name, create=True)
        state = read_state(folder)
        rendered = state.get("rendered", {})
        package_changed = False
        for file, mode in FILES:
            want = profile["files"][file]
            live_path = os.path.join(folder, file)
            live = sha256(live_path)
            if live == want:
                continue
            if live is not None and live != rendered.get(file):
                print(f"dsh-master: {name}/{file} was changed outside dsh-master; replacing it", file=sys.stderr)
            with open(os.path.join(source, "profiles", name, file), "rb") as stream:
                data = stream.read()
            if hashlib.sha256(data).hexdigest() != want:
                raise Failure(f"{source}/profiles/{name}/{file} does not match its manifest digest")
            write_atomic(folder, file, data, mode)
            package_changed = package_changed or file == "package.json"
            if not args.quiet:
                print(f"updated {name}/{file}")
        write_state(folder, {"rendered": dict(profile["files"]), "installed": state.get("installed")})
        if package_changed and state.get("installed") != profile["files"]["package.json"]:
            print(f"install needed: {name}")
    return 0


def lib_present(folder, dependency):
    lib = os.path.join(folder, "node_modules", dependency, "lib")
    return os.path.isdir(lib) and any(entry.endswith(".js") for entry in os.listdir(lib))


def install(args):
    manifest = load_manifest(args.source)
    home = dsh_home()
    failed = False
    for name in selected(manifest, args.profiles):
        profile = manifest["profiles"][name]
        folder = profile_folder(home, name, create=False)
        package = os.path.join(folder, "package.json")
        want = profile["files"]["package.json"]
        if sha256(package) != want or sha256(os.path.join(folder, "cordis.patch.yml")) != profile["files"]["cordis.patch.yml"]:
            raise Failure(f"{name} is not the rendered version; run dsh-master render first")
        with open(package, encoding="utf-8") as stream:
            dependencies = json.load(stream)["dependencies"]
        command = ["timeout", INSTALL_TIMEOUT, dsh_of(args, manifest), "plugin", "--profile", name, "install"]
        print(f"dsh-master: {name}: {' '.join(command)}", file=sys.stderr)
        code = subprocess.run(command, cwd=home, check=False).returncode
        # pnpm has printed "Done" and then hung: judge the folder, not the exit.
        problems = []
        if sha256(package) != want:
            problems.append("the install rewrote package.json")
        if not os.path.isfile(os.path.join(folder, "pnpm-lock.yaml")):
            problems.append("no pnpm-lock.yaml")
        problems += [f"{dep} has no built lib/" for dep in sorted(dependencies) if not lib_present(folder, dep)]
        if problems:
            print(f"dsh-master: {name}: install failed (exit {code}): {'; '.join(problems)}", file=sys.stderr)
            failed = True
            continue
        if code != 0:
            print(f"dsh-master: {name}: install exited {code}, but the folder is complete", file=sys.stderr)
        state = read_state(folder)
        state["installed"] = want
        write_state(folder, state)
        print(f"installed {name}")
    return 1 if failed else 0


def rows(tree):
    """Every mapping with an `id`, at any depth (group rows nest theirs)."""
    stack = [tree]
    while stack:
        item = stack.pop()
        if isinstance(item, dict):
            if isinstance(item.get("id"), str):
                yield item
            stack.extend(item.values())
        elif isinstance(item, list):
            stack.extend(reversed(item))


def dump_failures(dump, stderr, expect):
    """Compare a composed tree with the rendered rows; one message per failure."""
    failures = [f"stderr: {line}" for line in stderr.splitlines() if line.strip()]
    by_id = {}
    for row in rows(yaml.load(dump, Loader=Loader)):
        by_id.setdefault(row["id"], row)
    for want in expect:
        got = by_id.get(want["id"])
        if got is None:
            failures.append(f"{want['id']}: row missing")
            continue
        if want["disabled"] is True and got.get("disabled") is not True:
            failures.append(f"{want['id']}: not disabled")
        elif want["disabled"] is False and got.get("disabled") is True:
            failures.append(f"{want['id']}: disabled")
        if want["config"] is not None and got.get("config") != want["config"]:
            failures.append(f"{want['id']}: config is {json.dumps(got.get('config'), default=str, sort_keys=True)}")
    sessions = (by_id.get("session-persistence-jsonl") or {}).get("config") or {}
    if sessions.get("compression") != "none":
        failures.append(f"session-persistence-jsonl: compression is {sessions.get('compression')!r}")
    return failures


def check(args):
    manifest = load_manifest(args.source)
    home = dsh_home()
    failed = False
    for name in selected(manifest, args.profiles):
        profile_folder(home, name, create=False)
        result = subprocess.run(
            [dsh_of(args, manifest), "--profile", name, "--dump-config"],
            cwd=home,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            failures = [f"--dump-config exited {result.returncode}", *result.stderr.splitlines()]
        else:
            failures = dump_failures(result.stdout, result.stderr, manifest["profiles"][name]["expect"])
        if failures:
            failed = True
            for failure in failures:
                print(f"{name}: {failure}", file=sys.stderr)
        else:
            print(f"ok {name}: {len(manifest['profiles'][name]['expect'])} rows as rendered, no patch warning")
    return 1 if failed else 0


def status(args):
    manifest = load_manifest(args.source)
    home = dsh_home()
    for name, profile in sorted(manifest["profiles"].items()):
        folder = os.path.join(home, "profiles", name)
        current = all(sha256(os.path.join(folder, file)) == profile["files"][file] for file, _ in FILES)
        installed = read_state(folder).get("installed") == profile["files"]["package.json"]
        modules = os.path.isdir(os.path.join(folder, "node_modules"))
        print(
            f"{name}: rendered {'current' if current else 'stale'}, "
            f"installed {'current' if installed else 'no'}, node_modules {'present' if modules else 'absent'}"
        )
    return 0


def main(argv):
    parser = argparse.ArgumentParser(prog="dsh-master", description=__doc__.split("\n\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)
    for name, handler in (("render", render), ("install", install), ("check", check), ("status", status)):
        command = commands.add_parser(name)
        command.add_argument("--from", dest="source", default=default_source(), help="a dsh-master build (default: this one)")
        command.set_defaults(handler=handler)
        if name == "render":
            command.add_argument("--quiet", action="store_true", help="print only warnings and needed installs")
        if name in ("install", "check"):
            command.add_argument("--dsh", help="the dsh to run (default: the manifest's, the one dshd runs)")
            command.add_argument("profiles", nargs="*", metavar="PROFILE")
    args = parser.parse_args(argv)
    try:
        return args.handler(args)
    except Failure as error:
        print(f"dsh-master: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
