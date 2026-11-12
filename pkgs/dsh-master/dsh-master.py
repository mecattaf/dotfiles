"""dsh-master: install, check and report the rendered Master DSH profiles.

    dsh-master render [--from DIR] [--quiet]   copy the rendered files into $DSH_HOME
    dsh-master install [--force] [PROFILE...] install each profile's plugins
    dsh-master check [PROFILE...]             assert the rows in each config dump
    dsh-master status                         rendered, installed, current
    dsh-master settings seed [FILE] [--url U] seed the floor's Store settings

The rendered folders come from the package (pkgs/dsh-master/default.nix) or
from --from DIR, a `nix build .#dsh-master` result. render writes only
$DSH_HOME/profiles/master*/{cordis.patch.yml,package.json,.dsh-master.json},
each by temporary file and rename, and only when the content differs, plus
dsh's own pnpm-workspace.yaml when a folder has none (dsh writes it when it
creates a profile and owns it after), and in that file only the configured
allowBuilds keys that are absent or that dsh left undecided. It never runs
pnpm and never touches cordis.yml, pnpm-lock.yaml or node_modules, which
belong to dsh. install and check run the dsh that dshd runs (the
manifest's `dsh`): the fleet wrapper refuses `dsh plugin`, and its policy
overlays would hide what a dshd instance really composes. settings seed is
a client of the floor's management API: it upserts rules and admission cells
and raises the accept mode, and never touches anything else.
"""

import argparse
import copy
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

import yaml

NAME = re.compile(r"master(-[a-z0-9][a-z0-9-]*)?")
FILES = (("cordis.patch.yml", 0o644), ("package.json", 0o600))
# Written only when missing: dsh owns them once they exist.
ONCE = (("pnpm-workspace.yaml", 0o644),)
WORKSPACE = "pnpm-workspace.yaml"
# What dsh's plugin manager writes for a build script awaiting a decision
# (dsh-plugin-manager build-approval UNDECIDED_BUILD).
UNDECIDED = "set this to true or false"
STATE = ".dsh-master.json"
INSTALL_TIMEOUT = "600"
# timeout(1) itself failed, or could not run or find the command: dsh never ran.
NOT_RUN = (125, 126, 127)
# dshd unit states in which an instance may be running its profile's code.
ACTIVE = ("active", "activating", "deactivating", "reloading", "refreshing")


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
        if not NAME.fullmatch(name):
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


def mapping(value):
    return value if isinstance(value, dict) else {}


def yaml_key(name):
    return name if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", name) else json.dumps(name)


def decided(text, builds):
    """The workspace text with each configured build decided, or None when it already is.

    A key is set only when it is absent or dsh left it undecided: a person's own
    true or false and every other key stay. The text is edited in place, and
    rewritten whole only when the edit would not parse to the wanted mapping."""
    data = yaml.safe_load(text) if text.strip() else {}
    if not isinstance(data, dict):
        raise Failure("is not a YAML mapping")
    have = data.get("allowBuilds")
    if have is not None and not isinstance(have, dict):
        raise Failure("allowBuilds is not a mapping")
    have = have or {}
    todo = {name: value for name, value in sorted(builds.items()) if have.get(name, UNDECIDED) == UNDECIDED}
    if not todo:
        return None
    want = dict(data, allowBuilds={**have, **todo})
    new = text if not text or text.endswith("\n") else text + "\n"
    lines = {name: f"{yaml_key(name)}: {'true' if value else 'false'}" for name, value in todo.items()}
    if "allowBuilds" not in data:
        new += "allowBuilds:\n" + "".join(f"  {line}\n" for line in lines.values())
    for name, line in lines.items() if "allowBuilds" in data else ():
        if name in have:
            pattern = rf"(?m)^([ \t]+)(['\"]?){re.escape(name)}\2:[ \t]*{re.escape(UNDECIDED)}[ \t]*$"
            new = re.sub(pattern, lambda m: m[1] + line, new, count=1)
        else:
            new = re.sub(r"(?m)^allowBuilds:[ \t]*\n", lambda m: m[0] + "  " + line + "\n", new, count=1)
    if yaml.safe_load(new) != want:
        new = yaml.safe_dump(want, sort_keys=False, default_flow_style=False)
    return new


def workspace(folder):
    """The folder's workspace text, or None when there is none."""
    path = os.path.join(folder, WORKSPACE)
    if os.path.islink(path):
        raise Failure(f"{path} is a symbolic link; dsh-master writes only real files")
    try:
        with open(path, encoding="utf-8") as stream:
            return stream.read()
    except FileNotFoundError:
        return None


def pending_builds(text):
    try:
        builds = mapping(mapping(yaml.safe_load(text or "")).get("allowBuilds"))
    except yaml.YAMLError:
        return []
    return sorted(name for name, value in builds.items() if value == UNDECIDED)


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
        for file, mode in ONCE:
            if os.path.lexists(os.path.join(folder, file)):
                continue
            with open(os.path.join(source, "profiles", name, file), "rb") as stream:
                data = stream.read()
            if hashlib.sha256(data).hexdigest() != profile["once"][file]:
                raise Failure(f"{source}/profiles/{name}/{file} does not match its manifest digest")
            write_atomic(folder, file, data, mode)
            if not args.quiet:
                print(f"created {name}/{file}")
        builds = manifest.get("allowBuilds") or {}
        if builds:
            text = workspace(folder)
            try:
                new = decided(text, builds)
            except (Failure, yaml.YAMLError) as error:
                raise Failure(f"{name}/{WORKSPACE}: {error}") from error
            if new is not None:
                mode = stat.S_IMODE(os.stat(os.path.join(folder, WORKSPACE)).st_mode)
                write_atomic(folder, WORKSPACE, new.encode("utf-8"), mode)
                if not args.quiet:
                    print(f"updated {name}/{WORKSPACE} (allowBuilds)")
        write_state(folder, {"rendered": dict(profile["files"]), "installed": state.get("installed")})
        # Every render until an install records this package.json, not only the one that changed it.
        if state.get("installed") != profile["files"]["package.json"]:
            print(f"install needed: {name}")
    return 0


def lib_present(folder, dependency):
    # The fork builds lib/*.js; dsh-claude's tsdown entries are lib/*.mjs.
    lib = os.path.join(folder, "node_modules", dependency, "lib")
    return os.path.isdir(lib) and any(entry.endswith((".js", ".mjs")) for entry in os.listdir(lib))


def lock_problems(folder, dependencies):
    """Where pnpm's lockfile (and node_modules' copy of it) does not lock package.json."""
    problems = []
    for lock in ("pnpm-lock.yaml", os.path.join("node_modules", ".pnpm", "lock.yaml")):
        path = os.path.join(folder, lock)
        if not os.path.isfile(path):
            if lock == "pnpm-lock.yaml":
                problems.append("no pnpm-lock.yaml")
            continue
        try:
            with open(path, encoding="utf-8") as stream:
                locked = mapping(mapping(mapping(mapping(yaml.safe_load(stream)).get("importers")).get(".")).get("dependencies"))
        except yaml.YAMLError:
            problems.append(f"{lock} does not parse")
            continue
        for dependency, spec in sorted(dependencies.items()):
            have = mapping(locked.get(dependency)).get("specifier")
            if have != spec:
                problems.append(f"{lock} locks {dependency} at {have or 'nothing'}, not {spec}")
    return problems


def instances_using(args, manifest, home):
    """{profile: [instance]} for the dshd instances of this DSH_HOME that may be running."""
    dshd = args.dshd or manifest.get("dshd") or "dshd"

    def query(*verb):
        result = subprocess.run([dshd, *verb], capture_output=True, text=True, check=False, timeout=30)
        if result.returncode != 0:
            raise Failure(f"{dshd} {' '.join(verb)} exited {result.returncode}: {result.stderr.strip()}")
        return json.loads(result.stdout)

    using = {}
    try:
        for entry in query("ls", "--json").get("instances", []):
            if entry.get("state") in ("stopped", "failed"):
                continue
            got = query("get", "--json", entry["name"])
            profile = mapping(got.get("profile"))
            if got.get("activeState") not in ACTIVE or not profile.get("dshHome"):
                continue
            if os.path.realpath(profile["dshHome"]) == os.path.realpath(home):
                using.setdefault(profile.get("name"), []).append(entry["name"])
    except (OSError, ValueError, KeyError, AttributeError, subprocess.TimeoutExpired, Failure) as error:
        raise Failure(f"cannot tell which dshd instances run a Master profile ({error}); stop them and pass --force") from error
    return using


def install(args):
    manifest = load_manifest(args.source)
    home = dsh_home()
    failed = False
    using = None
    for name in selected(manifest, args.profiles):
        profile = manifest["profiles"][name]
        folder = profile_folder(home, name, create=False)
        package = os.path.join(folder, "package.json")
        want = profile["files"]["package.json"]
        if sha256(package) != want or sha256(os.path.join(folder, "cordis.patch.yml")) != profile["files"]["cordis.patch.yml"]:
            raise Failure(f"{name} is not the rendered version; run dsh-master render first")
        # Without it pnpm treats the folder as no workspace and pulls the DSH peers from the registry.
        if not all(os.path.isfile(os.path.join(folder, file)) for file, _ in ONCE):
            raise Failure(f"{name} has no pnpm-workspace.yaml; run dsh-master render first")
        with open(package, encoding="utf-8") as stream:
            dependencies = json.load(stream)["dependencies"]
        # pnpm replaces lib/ and the served client.js under a live process.
        if not args.force:
            if using is None:
                using = instances_using(args, manifest, home)
            if using.get(name):
                raise Failure(f"dshd instance {', '.join(using[name])} is running {name}; stop it first, or pass --force")
        command = ["timeout", INSTALL_TIMEOUT, dsh_of(args, manifest), "plugin", "--profile", name, "install"]
        print(f"dsh-master: {name}: {' '.join(command)}", file=sys.stderr)
        code = subprocess.run(command, cwd=home, check=False).returncode
        if code in NOT_RUN:
            print(f"dsh-master: {name}: install failed: {command[2]} did not run (exit {code})", file=sys.stderr)
            failed = True
            continue
        # pnpm has printed "Done" and then hung: judge the folder, not the exit.
        # The lockfile must lock this package.json: an old install's lockfile and lib/ do not count.
        problems = []
        if sha256(package) != want:
            problems.append("the install rewrote package.json")
        problems += lock_problems(folder, dependencies)
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
        pending = pending_builds(workspace(folder))
        if pending:
            print(f"dsh-master: {name}: builds pending: {', '.join(pending)} (programs.dsh.master.allowBuilds)", file=sys.stderr)
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
    builds = manifest.get("allowBuilds") or {}
    for name, profile in sorted(manifest["profiles"].items()):
        folder = os.path.join(home, "profiles", name)
        current = all(sha256(os.path.join(folder, file)) == profile["files"][file] for file, _ in FILES) and all(
            os.path.isfile(os.path.join(folder, file)) for file, _ in ONCE
        )
        text = workspace(folder) if os.path.isdir(folder) else None
        if current and builds:
            try:
                current = decided(text or "", builds) is None
            except (Failure, yaml.YAMLError):
                current = False
        installed = read_state(folder).get("installed") == profile["files"]["package.json"]
        modules = os.path.isdir(os.path.join(folder, "node_modules"))
        pending = pending_builds(text)
        print(
            f"{name}: rendered {'current' if current else 'stale'}, "
            f"installed {'current' if installed else 'no'}, node_modules {'present' if modules else 'absent'}"
            + (f", builds pending: {', '.join(pending)}" if pending else "")
        )
    return 0


MODES = ("off", "observe", "auto")


class Conflict(Exception):
    pass


def api(url, method="GET", body=None):
    # The floor answers only same-origin management requests (fork src/app/http.ts sameOrigin).
    request = urllib.request.Request(
        url,
        method=method,
        data=None if body is None else json.dumps(body).encode("utf-8"),
        headers={"x-orchestrator-request": "1", "content-type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace").strip()
        if error.code == 409:
            raise Conflict(detail) from error
        raise Failure(f"{method} {url}: HTTP {error.code}: {detail}") from error
    except urllib.error.URLError as error:
        raise Failure(f"{method} {url}: {error.reason}") from error


def seeded(blocks, seed):
    """The blocks the seed changes, as {block: (value, revision)}; warnings go to stderr."""
    changes = {}
    if "rules" in seed or "admission" in seed:
        current = blocks["policy"]["value"]
        policy = copy.deepcopy(current)
        rules = policy.setdefault("rules", [])
        for rule in seed.get("rules", []):
            index = next((i for i, have in enumerate(rules) if have.get("id") == rule["id"]), None)
            if index is None:
                rules.append(rule)
            else:
                rules[index] = rule
        for source, table in seed.get("admission", {}).items():
            entry = policy.setdefault("sources", {}).setdefault(source, {"allowed": [], "admission": {}})
            for row, cells in table.items():
                entry.setdefault("admission", {}).setdefault(row, {}).update(cells)
        if policy != current:
            changes["policy"] = (policy, blocks["policy"]["revision"])
    if "eval" in seed:
        current = blocks["eval"]["value"]
        have, want = current.get("mode"), seed["eval"]["mode"]
        if have == "off" and want != "off":
            print("dsh-master: eval.mode is off in the Store (a person switched it off); left alone", file=sys.stderr)
        elif have not in MODES:
            print(f"dsh-master: eval.mode is {have!r} in the Store, not one of {', '.join(MODES)}; left alone", file=sys.stderr)
        elif MODES.index(want) > MODES.index(have):
            changes["eval"] = (dict(current, mode=want), blocks["eval"]["revision"])
    return changes


def settings_seed(args):
    with open(args.file or os.path.join(args.source, "share", "dsh-master", "settings.seed.json"), encoding="utf-8") as stream:
        seed = json.load(stream)
    if "eval" in seed and mapping(seed["eval"]).get("mode") not in MODES:
        raise Failure(f"the seed's eval.mode is {mapping(seed['eval']).get('mode')!r}, not one of {', '.join(MODES)}")
    base = args.url.rstrip("/") + "/orchestrator/api/settings"
    for attempt in (1, 2):
        changes = seeded(api(base)["blocks"], seed)
        if not changes:
            print("unchanged")
            return 0
        try:
            # Rules and admission before the mode, so `auto` never runs on the old rules.
            for block in ("policy", "eval"):
                if block in changes:
                    value, revision = changes[block]
                    api(f"{base}/{block}", "PUT", {"value": value, "revision": revision})
        except Conflict as error:
            if attempt == 2:
                print(f"dsh-master: settings changed twice while seeding: {error}", file=sys.stderr)
                return 1
            continue
        print(f"changed {' '.join(block for block in ('policy', 'eval') if block in changes)}")
        return 0
    return 1


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
        if name == "install":
            command.add_argument("--dshd", help="the dshd to ask which instances run (default: the manifest's)")
            command.add_argument("--force", action="store_true", help="install even while a dshd instance runs the profile")
    settings = commands.add_parser("settings").add_subparsers(dest="settings", required=True)
    seed = settings.add_parser("seed", help="upsert the seed's rules and admission cells, raise eval.mode")
    seed.add_argument("file", nargs="?", help="seed file (default: this build's settings.seed.json)")
    seed.add_argument("--url", default="http://127.0.0.1:3082", help="the floor's web server")
    seed.add_argument("--from", dest="source", default=default_source(), help="a dsh-master build (default: this one)")
    seed.set_defaults(handler=settings_seed)
    args = parser.parse_args(argv)
    try:
        return args.handler(args)
    except Failure as error:
        print(f"dsh-master: {error}", file=sys.stderr)
        return 2
    except (OSError, KeyError, ValueError, yaml.YAMLError) as error:
        verb = args.command if args.command != "settings" else "settings seed"
        print(f"dsh-master: {verb}: {type(error).__name__}: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    # Piped (activation, tee), stdout would otherwise come after later folders' errors.
    sys.stdout.reconfigure(line_buffering=True)
    sys.exit(main(sys.argv[1:]))
