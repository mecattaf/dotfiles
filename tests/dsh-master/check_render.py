"""Assert the shape of the rendered Master profile folders (checks.dsh-master).

Usage: check_render.py <dsh-master package> <expectations.json>

The expectations come from the NAS configuration (tests/dsh-master/default.nix):
the pairs and their presets, the default pair, the release tag, the seat, the
state directory and the fleet policy as pkgs/dsh exports it. Each subtest
prints its name; any failure exits 1 after all of them ran.
"""

import copy
import json
import os
import re
import sys

import yaml


class Loader(yaml.SafeLoader):
    pass


Loader.add_constructor("!!js", lambda loader, node: {"__js": loader.construct_scalar(node)})
Loader.add_constructor("tag:yaml.org,2002:js", lambda loader, node: {"__js": loader.construct_scalar(node)})

WEB = "@deepseek-ai/dsh-web-app"
HEADLESS = "@deepseek-ai/dsh-headless"
PERMISSION_ROWS = {"sandbox", "sandbox-policy", "approval", "permission"}
PIN = re.compile(r"^github:mecattaf/[a-z-]+#floor-v2\.[0-9]+$")
# How a seed rule addresses its two readers, and its length bound: half of the
# fork's RuleSchema limit, since every enabled rule sits in the main Session's
# prompt and every matched one in a worker's brief.
ASSESSOR_CLAUSE = "If you are assessing it: "
WORKER_CLAUSE = "If you are the worker running this ticket, only this sentence applies to you: "
RULE_CHARS = 1000
# The fork's assessmentOutcome (src/policy.ts) turns an accept into `ignore
# directionUnsettled` unless the assessor declares implementation_requested,
# a target_basis other than undetermined and no requires_design_decision.
# Upstream's admission prompt lets a matched rule define those facts for its
# category, so each seed rule states all three before its worker clause.
DIRECTION_FACTS = {
    "implementation_requested": "an implementation request by ",
    "target_basis": "its target is ",
    "requires_design_decision": "needs no design decision",
}


def load(package):
    with open(os.path.join(package, "manifest.json"), encoding="utf-8") as stream:
        manifest = json.load(stream)
    folders = {}
    for name in manifest["profiles"]:
        folder = os.path.join(package, "profiles", name)
        with open(os.path.join(folder, "package.json"), encoding="utf-8") as stream:
            package_json = json.load(stream)
        with open(os.path.join(folder, "cordis.patch.yml"), encoding="utf-8") as stream:
            patch = yaml.load(stream, Loader=Loader)
        folders[name] = {"package": package_json, "patch": patch}
    return manifest, folders


def by_id(patch):
    rows = {}
    for row in patch:
        if "insert" in row:
            for inserted in row["insert"]:
                rows.setdefault(inserted["id"], []).append(dict(inserted, inserted=True))
        else:
            rows.setdefault(row["id"], []).append(row)
    return rows


def main(package, expect_path):
    with open(expect_path, encoding="utf-8") as stream:
        expect = json.load(stream)
    manifest, folders = load(package)
    failures = []

    def subtest(name, problems):
        print(f"{'ok' if not problems else 'FAIL'} {name}")
        failures.extend(f"{name}: {problem}" for problem in problems)

    pairs = expect["pairs"]
    workers = {f"master-{pair}": pair for pair in pairs}
    subtest(
        "one folder per pair plus master",
        [] if sorted(folders) == sorted(["master", *workers]) else [f"folders are {sorted(folders)}"],
    )

    deps = {name: folder["package"]["dependencies"] for name, folder in folders.items()}
    problems = [f"{name}: {dep}" for name, dep in deps.items() if dep != deps["master"]]
    configured = {"dsh-superagent": expect["superagent"], "@norman-else/dsh-claude": expect["claude"]}
    problems += [] if deps["master"] == configured else [f"dependencies {deps['master']}, configured {configured}"]
    # The release form only while neither pin is set by hand (docs/dsh-master.md: a fork-only re-tag sets one).
    if expect["pinsFollowTag"]:
        problems += [f"{key} pinned as {spec!r}" for key, spec in deps["master"].items() if not PIN.match(spec)]
        problems += [f"{key} names tag {spec.rpartition('#')[2]!r}, not {expect['tag']!r}" for key, spec in deps["master"].items() if spec.rpartition("#")[2] != expect["tag"]]
    subtest("identical dependencies across profiles, pinned as configured", problems)

    bundles = {name: folder["package"]["dsh"]["profile"]["bundles"] for name, folder in folders.items()}
    problems = []
    common = [b for b in bundles["master"] if b not in (WEB, HEADLESS)]
    for name, listed in bundles.items():
        app = WEB if name == "master" else HEADLESS
        if app not in listed:
            problems.append(f"{name} does not list {app}")
        if WEB in listed and HEADLESS in listed:
            problems.append(f"{name} lists both apps (the headless layer disables web authorization)")
        if [b for b in listed if b not in (WEB, HEADLESS)] != common:
            problems.append(f"{name} bundles {listed}")
    if common != ["@deepseek-ai/dsh-base", "@norman-else/dsh-claude", "dsh-superagent"]:
        problems.append(f"non-app bundles are {common}")
    subtest("bundles differ only in the app bundle", problems)

    problems = []
    rows = {name: by_id(folder["patch"]) for name, folder in folders.items()}
    superagent = {}
    for name, ids in rows.items():
        found = ids.get("dsh-superagent", [])
        if len(found) != 1:
            problems.append(f"{name}: {len(found)} dsh-superagent rows")
            continue
        row = found[0]
        if row.get("disabled"):
            problems.append(f"{name}: dsh-superagent row disabled (dormancy is the engine key)")
        engine = (row.get("config") or {}).get("engine")
        if engine is not (name == "master"):
            problems.append(f"{name}: engine is {engine!r}")
        stripped = copy.deepcopy(row)
        stripped.get("config", {}).pop("engine", None)
        superagent[name] = stripped
    problems += [f"{name}: the row differs from master's beyond engine" for name, row in superagent.items() if row != superagent.get("master")]
    extra = {name: [row for row in folder["patch"] if row.get("id", "").startswith("dsh-superagent-")] for name, folder in folders.items()}
    problems += [f"{name}: fork rows differ from master's" for name, listed in extra.items() if listed != extra["master"]]
    sources = {row["id"]: row for row in extra.get("master", [])}
    for row_id in ("dsh-superagent-scheduled", "dsh-superagent-workflow"):
        if sources.get(row_id, {}).get("disabled") is not False:
            problems.append(f"{row_id} is not rendered enabled")
    for row_id in ("dsh-superagent-github", "dsh-superagent-feishu"):
        if sources.get(row_id, {}).get("disabled") is not True:
            problems.append(f"{row_id} is not rendered disabled")
    for row in expect["superagentRows"]:
        if sources.get(row["id"]) != row:
            problems.append(f"{row['id']} is rendered as {sources.get(row['id'])}, configured {row}")
    expected = {row["id"]: row["disabled"] for profile in manifest["profiles"].values() for row in profile["expect"] if row["id"] == "dsh-superagent"}
    if expected != {"dsh-superagent": False}:
        problems.append(f"dsh-master check does not assert dsh-superagent enabled: {expected}")
    subtest("engine on only in master", problems)

    problems = [f"{name}: {row_id}" for name, ids in rows.items() for row_id in PERMISSION_ROWS & set(ids)]
    subtest("full permissions", problems)

    problems = []
    for name, ids in rows.items():
        route = pairs[expect["defaultPair"] if name == "master" else workers[name]]
        model = ids.get("agent-default-model", [])
        if len(model) != 1 or model[0].get("config") != route:
            problems.append(f"{name}: agent-default-model is {[m.get('config') for m in model]}, expected {route}")
    dshd = superagent.get("master", {}).get("config", {}).get("dshd", {})
    if dshd.get("defaultPair") != expect["defaultPair"] or dshd.get("defaultPair") not in dshd.get("pairs", {}):
        problems.append(f"dshd.defaultPair is {dshd.get('defaultPair')!r}")
    for pair, settings in expect["pairEnv"].items():
        got = dshd.get("pairs", {}).get(pair, {})
        if got.get("profile") != f"master-{pair}":
            problems.append(f"dshd.pairs.{pair}.profile is {got.get('profile')!r}")
        if got.get("env", {}) != settings["env"] or got.get("maxWorkers") != settings["maxWorkers"]:
            problems.append(f"dshd.pairs.{pair} is {got}")
    if sorted(dshd.get("pairs", {})) != sorted(pairs):
        problems.append(f"dshd.pairs are {sorted(dshd.get('pairs', {}))}")
    config = superagent.get("master", {}).get("config", {})
    if config.get("stateDir") != expect["stateDir"] or config.get("executor") != "dshd":
        problems.append(f"stateDir {config.get('stateDir')!r}, executor {config.get('executor')!r}")
    if dshd.get("env", {}).get("CLAUDE_CONFIG_DIR") != expect["claudeConfigDir"]:
        problems.append(f"dshd.env is {dshd.get('env')}")
    subtest("pair rows", problems)

    problems = []
    for name, ids in rows.items():
        claude = ids.get("llm-claude", [])
        if len(claude) != 1:
            problems.append(f"{name}: {len(claude)} llm-claude rows")
            continue
        config = claude[0]["config"]
        seat = config.get("executablePath", "")
        try:
            with open(seat, encoding="utf-8") as stream:
                text = stream.read()
        except OSError as error:
            problems.append(f"{name}: executablePath {seat!r}: {error}")
            continue
        if f"export CLAUDE_CONFIG_DIR={expect['claudeConfigDir']}\n" not in text or "exec /nix/store/" not in text:
            problems.append(f"{name}: {seat} does not pin the seat")
        want = (
            {"forwardedSources": ["user", "dsh-superagent"], "systemPromptPresets": ["dsh-superagent-router"], "presets": None}
            if name == "master"
            else {"forwardedSources": ["user"], "systemPromptPresets": [], "presets": ["claude"]}
        )
        want.update(permissionSelector="native", sources=None, presetless=None)
        problems += [f"{name}: llm-claude {key} is {config.get(key)!r}" for key, value in want.items() if config.get(key) != value]
    subtest("seat and claude rows", problems)

    problems = []
    if rows["master"].get("agent-preset-registry") or rows["master"].get("headless-preset"):
        problems.append("master inserts preset rows the web bundle does not need")
    for name, pair in workers.items():
        ids, preset = rows[name], expect["presets"][pair]
        registry = ids.get("agent-preset-registry", [])
        binder = ids.get("headless-preset", [])
        if len(registry) != 1 or not registry[0].get("inserted") or registry[0].get("config") != {"default": "claude"}:
            problems.append(f"{name}: agent-preset-registry insert is {registry}")
        if preset is None:
            if binder:
                problems.append(f"{name}: inserts headless-preset for a pair without a preset")
        elif len(binder) != 1 or binder[0].get("name") != "@norman-else/dsh-claude/headless-preset" or binder[0].get("config") != {"preset": preset}:
            problems.append(f"{name}: headless-preset insert is {binder}")
        if pairs[pair]["provider"] != "claude" and preset is not None:
            problems.append(f"{name}: binds preset {preset!r} to a {pairs[pair]['provider']} worker (the claude preset routes to Claude Code)")
        order = [row.get("insert", [{}])[0].get("id") for row in folders[name]["patch"] if "insert" in row]
        want = ["agent-preset-registry"] + ([] if preset is None else ["headless-preset"])
        if order != want:
            problems.append(f"{name}: inserts in the order {order}, expected {want}")
    subtest("headless folders insert headless-preset after agent-preset-registry", problems)

    problems = []
    try:
        with open(os.path.join(package, "share", "dsh-master", "settings.seed.json"), encoding="utf-8") as stream:
            seed = json.load(stream)
    except (OSError, ValueError) as error:
        seed = {}
        problems.append(f"settings.seed.json: {error}")
    if seed.get("eval") != {"mode": "auto", "timeoutSeconds": 600}:
        problems.append(f"eval is {seed.get('eval')}")
    rules = {rule.get("id"): rule for rule in seed.get("rules", [])}
    for rule_id, prefix in (("scheduled", "A Trigger of the scheduled Source"), ("workflow-node", "A Trigger from the workflow Source")):
        rule = rules.get(rule_id, {})
        if rule.get("enabled") is not True or not rule.get("instruction", "").startswith(prefix):
            problems.append(f"rule {rule_id} is {rule}")
    if sorted(rules) != ["scheduled", "workflow-node"]:
        problems.append(f"rules are {sorted(rules)}")
    want = {"scheduled": {"occurrence": {"unlistedUnaddressed": "inferred"}}, "workflow": {"workflow": {"unlistedUnaddressed": "inferred"}}}
    if seed.get("admission") != want:
        problems.append(f"admission is {seed.get('admission')}")
    subtest("seed file holds both rules and both admission rows", problems)

    # An item can ask the superagent itself to act, for example to start a
    # workflow, instead of handing a worker a ticket. The scheduled rule's
    # assessor clause must let it, or the assessor accepts the nudge as a
    # ticket for a worker, which has no orchestrator tools.
    problems = []
    text = rules.get("scheduled", {}).get("instruction", "")
    assess, work = text.find(ASSESSOR_CLAUSE), text.find(WORKER_CLAUSE)
    clause = text[assess:work] if 0 <= assess < work else ""
    for phrase in ("asks you, not a worker, to act", "orchestrator_workflow_start", "then do what it asks"):
        if phrase not in clause:
            problems.append(f"rule scheduled: the assessor clause does not say {phrase!r}")
    subtest("the scheduled rule lets an item ask the superagent itself to act", problems)

    # A rule has two readers: the main Session assesses Triggers by it, and
    # the fork's executor copies a matched rule verbatim into the worker's
    # brief, where it "takes precedence". So each rule describes its
    # Triggers, then has one assessor clause, and ends with one worker clause,
    # the same in every rule; the orchestrator tools appear only in the
    # assessor clause, since a dshd worker has none. The description states
    # the three direction facts, or an accept by the rule never dispatches.
    problems = []
    clauses = set()
    for rule_id, rule in rules.items():
        text = rule.get("instruction", "")
        assess, work = text.find(ASSESSOR_CLAUSE), text.find(WORKER_CLAUSE)
        if text.count(ASSESSOR_CLAUSE) != 1 or text.count(WORKER_CLAUSE) != 1 or not 0 < assess < work:
            problems.append(f"rule {rule_id}: no description, then one {ASSESSOR_CLAUSE!r}, then one {WORKER_CLAUSE!r}")
            continue
        worker = text[work:]
        clauses.add(worker)
        for fact, phrase in DIRECTION_FACTS.items():
            if phrase not in text[:work]:
                problems.append(f"rule {rule_id}: settles no {fact} (no {phrase!r} before the worker clause)")
        for phrase in ("in the current folder", "your final message is the result", "you have no orchestrator tools"):
            if phrase not in worker:
                problems.append(f"rule {rule_id}: the worker clause does not say {phrase!r}")
        for tool in re.finditer(r"orchestrator_\w+", text):
            if not assess < tool.start() < work:
                problems.append(f"rule {rule_id}: {tool.group()} outside the assessor clause")
        if len(text) > RULE_CHARS:
            problems.append(f"rule {rule_id}: {len(text)} characters, more than {RULE_CHARS}")
    if len(clauses) > 1:
        problems.append(f"the worker clauses differ: {sorted(clauses)}")
    subtest("each seed rule settles direction and tells the assessor, then the worker, what to do", problems)

    # dsh's own workspace keys plus the build policy, so pnpm 11 has no
    # undecided build script (ERR_PNPM_IGNORED_BUILDS, exit 1). render owns
    # the file like the other two, so the manifest lists it under `files`.
    problems = []
    want = {"packages": ["."], "nodeLinker": "hoisted", "autoInstallPeers": False}
    if expect["allowBuilds"]:
        want["allowBuilds"] = expect["allowBuilds"]
    if expect["allowBuilds"].get("msgpackr-extract") is None:
        problems.append("allowBuilds decides nothing for msgpackr-extract, which the fork's interpreter pulls in")
    for name, profile in manifest["profiles"].items():
        path = os.path.join(package, "profiles", name, "pnpm-workspace.yaml")
        if not os.path.isfile(path) or profile["files"].get("pnpm-workspace.yaml") is None or "once" in profile:
            problems.append(f"{name}: pnpm-workspace.yaml is not a rendered file of the folder and the manifest")
            continue
        with open(path, encoding="utf-8") as stream:
            workspace = yaml.safe_load(stream)
        if workspace != want:
            problems.append(f"{name}: pnpm-workspace.yaml is {workspace}")
    subtest("every folder carries dsh's pnpm workspace and a build policy", problems)

    problems = []
    policy = {row["id"]: row for row in expect["policyRows"]}
    wanted = sorted(set(expect["policyIds"]) - set(expect["dropped"]))
    for name, ids in rows.items():
        have = sorted(set(ids) & set(expect["policyIds"]) - {"agent-default-model"})
        if have != wanted:
            problems.append(f"{name}: policy ids {have}")
        problems += [f"{name}: {row_id} differs from the policy" for row_id in wanted if ids.get(row_id, [None])[0] != policy[row_id]]
        sessions = ids.get("session-persistence-jsonl", [])
        if len(sessions) != 1 or sessions[0].get("config", {}).get("compression") != "none" or "__js" not in sessions[0].get("config", {}).get("root", {}):
            problems.append(f"{name}: sessions row is {sessions}")
    subtest("policy parity", problems)

    problems = []
    for name, profile in manifest["profiles"].items():
        expected = {row["id"] for row in profile["expect"]}
        if not set(rows[name]) - {"session-persistence-jsonl"} <= expected:
            problems.append(f"{name}: rows not asserted by dsh-master check: {sorted(set(rows[name]) - expected)}")
    subtest("check asserts every rendered row", problems)

    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
