"""Assert the fleet policy in one `dsh <profile> --dump-config` tree.

Usage: check_dump.py <dump.yml> <expectations.json>

The dump is dsh's composed profile tree: a YAML list of rows, some carrying
`!!js` expressions (kept as opaque strings here; nothing is evaluated). The
expectations come from pkgs/dsh's passthru, so the check follows the policy
instead of restating it. checks.dsh-plugins adds `rows`, `present` and
`absent` for the plugin profile.
"""

import json
import sys

import yaml


class Loader(yaml.SafeLoader):
    pass


Loader.add_constructor("!!js", lambda loader, node: {"__js": loader.construct_scalar(node)})
Loader.add_constructor(
    "tag:yaml.org,2002:js", lambda loader, node: {"__js": loader.construct_scalar(node)}
)


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
            stack.extend(item)


def main(dump_path, expect_path):
    with open(dump_path, encoding="utf-8") as stream:
        tree = yaml.load(stream, Loader=Loader)
    with open(expect_path, encoding="utf-8") as stream:
        expect = json.load(stream)

    by_id = {}
    for row in rows(tree):
        by_id.setdefault(row["id"], row)
    failures = []

    def check(condition, message):
        if not condition:
            failures.append(message)

    for row_id in expect["disabled"]:
        row = by_id.get(row_id)
        check(row is not None, f"{row_id}: row missing")
        check(row is None or row.get("disabled") is True, f"{row_id}: not disabled")

    model = (by_id.get("agent-default-model") or {}).get("config") or {}
    check(model.get("provider") == "qwen-token-plan", f"agent-default-model provider is {model.get('provider')!r}")
    check(model.get("model") == "deepseek-v4.1-flash", f"agent-default-model model is {model.get('model')!r}")

    providers = ((by_id.get("llm-pi-ai") or {}).get("config") or {}).get("providers") or {}
    local = expect["localProviders"]
    check(sorted(providers) == sorted(["qwen-token-plan", *local]), f"llm-pi-ai providers are {sorted(providers)}")
    for name, config in local.items():
        check(providers.get(name) == config, f"{name}: provider config is {providers.get(name)!r}")

    sessions = (by_id.get("session-persistence-jsonl") or {}).get("config") or {}
    check(sessions.get("compression") == "none", f"session compression is {sessions.get('compression')!r}")
    check(isinstance(sessions.get("root"), dict), "session root is not the DSH_HOME-relative !!js row")

    sandbox = (by_id.get("sandbox") or {}).get("config") or {}
    check(sandbox.get("runnerCommand") == [expect["runner"]], f"sandbox runnerCommand is {sandbox.get('runnerCommand')!r}")
    policy = (by_id.get("sandbox-policy") or {}).get("config") or {}
    check(policy.get("mode") == "workspace-write", f"sandbox-policy mode is {policy.get('mode')!r}")
    presets = ((by_id.get("permission") or {}).get("config") or {}).get("presets") or {}
    check("danger-full-access" not in presets, "danger-full-access preset still offered")
    approval = (by_id.get("approval") or {}).get("config") or {}
    check(approval.get("policy") == "ask", f"approval policy is {approval.get('policy')!r}")

    workflow = (by_id.get("workflow-ptc") or {}).get("config") or {}
    check(workflow.get("maxConcurrentAgents") == 3, "workflow-ptc maxConcurrentAgents is not 3")
    web = (by_id.get("tool-web") or {}).get("config") or {}
    check(web.get("search") is False and web.get("fetch") is True, f"tool-web is {web!r}")

    if "acp" in by_id:
        acp = by_id["acp"].get("config") or {}
        check(acp.get("provider") == "qwen-token-plan", f"acp provider is {acp.get('provider')!r}")

    # Optional, for checks.dsh-plugins: rows whose whole config is pinned,
    # rows that must mount, rows that must not exist at all.
    for row_id, config in expect.get("rows", {}).items():
        got = (by_id.get(row_id) or {}).get("config")
        check(got == config, f"{row_id}: config is {got!r}, expected {config!r}")
    for row_id in expect.get("present", []):
        row = by_id.get(row_id)
        check(row is not None and row.get("disabled") is not True, f"{row_id}: row missing or disabled")
    for row_id in expect.get("absent", []):
        check(row_id not in by_id, f"{row_id}: row present")

    # No row may still name the official route or its default model.
    text = json.dumps(tree, default=str)
    for needle in ("deepseek-official", "api.deepseek.com"):
        check(needle not in text, f"{needle} still named in the tree")

    if failures:
        for failure in failures:
            print(f"FAIL {dump_path}: {failure}", file=sys.stderr)
        return 1
    print(f"ok {dump_path}: {len(by_id)} rows, policy present")
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
