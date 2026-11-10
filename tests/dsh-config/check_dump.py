"""Assert the fleet policy in one `dsh <profile> --dump-config` tree.

Usage: check_dump.py <dump.yml> <expectations.json>

The dump is dsh's composed profile tree: a YAML list of rows, some carrying
`!!js` expressions (kept as opaque strings here; nothing is evaluated). The
expectations come from pkgs/dsh's passthru (`defaultRoute`, `cloudProviders`,
`localProviders`, ...), so the check follows the policy instead of restating
it. checks.dsh-plugins and checks.dsh-zen add `rows`, `present` and `absent`
for the plugin profiles; a `DSH_ROUTE` dump passes the route as `defaultRoute`.
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
    """The host loader's rows; detached agent presets own separate trees.

    cordis-plugin-include applies --patch only to entries and group configs.
    Preset config.plugins are declarations for future agent scopes; their
    repeated ids must not shadow the host's providers or policy rows here.
    """
    stack = [tree]
    while stack:
        item = stack.pop()
        if isinstance(item, dict):
            if isinstance(item.get("id"), str):
                yield item
            if item.get("group") is True and isinstance(item.get("config"), list):
                stack.append(item["config"])
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

    # Native web presets inherit the host services. If an upstream bump puts
    # a provider or exporter inside a preset, root-only patches no longer
    # protect it. Refuse that change instead of mistaking a duplicate id for
    # the host row. Scoped tools may still depend on disabled host services.
    protected = (set(expect["disabled"]) - {"tool-plugin-manager"}) | {"llm-pi-ai", "web"}
    pending = list(by_id.values())
    while pending:
        parent = pending.pop()
        config = parent.get("config")
        if not isinstance(config, dict) or not isinstance(config.get("plugins"), list):
            continue
        scoped = list(rows(config["plugins"]))
        pending.extend(scoped)
        for row in scoped:
            check(row["id"] not in protected or row.get("disabled") is True,
                  f"{parent['id']}: scoped {row['id']} bypasses the host policy")

    route = expect["defaultRoute"]
    model = (by_id.get("agent-default-model") or {}).get("config") or {}
    check(model.get("provider") == route["provider"], f"agent-default-model provider is {model.get('provider')!r}")
    check(model.get("model") == route["model"], f"agent-default-model model is {model.get('model')!r}")

    providers = ((by_id.get("llm-pi-ai") or {}).get("config") or {}).get("providers") or {}
    local = expect["localProviders"]
    cloud = expect["cloudProviders"]
    check(sorted(providers) == sorted([*cloud, *local]), f"llm-pi-ai providers are {sorted(providers)}")
    for name, config in local.items():
        check(providers.get(name) == config, f"{name}: provider config is {providers.get(name)!r}")
    # A keyed cloud route: its key named so nothing ambient is read, exactly
    # the policy's model list, and its api/baseURL exactly as the policy
    # states them: absent for a native catalog route (pi-ai's own endpoint
    # and protocol under the catalog name), both present for a hand-declared
    # one (cohere). retryPolicy differs per overlay.
    for name, config in cloud.items():
        got = providers.get(name) or {}
        check(got.get("apiKeyEnv") == config["apiKeyEnv"], f"{name}: apiKeyEnv is {got.get('apiKeyEnv')!r}")
        for field in ("api", "baseURL"):
            check(
                got.get(field) == config.get(field),
                f"{name}: {field} is {got.get(field)!r}, expected {config.get(field)!r}",
            )
        want = [m["id"] for m in config["models"]]
        have = [m.get("id") for m in got.get("models") or []]
        check(have == want, f"{name}: models are {have!r}, expected {want!r}")
    # No provider row may carry a credential-shaped value or a resolved
    # Cloudflare account id: keys reach dsh through the environment only.
    for name, got in providers.items():
        text = json.dumps(got, default=str)
        check("{CLOUDFLARE_ACCOUNT_ID}" not in text, f"{name}: names the Cloudflare placeholder in the policy")
        check("/run/agenix" not in text, f"{name}: names an agenix path")
    # Retired providers must not survive in a composed profile.
    check("ds4" not in providers, "local ds4 provider still selectable")
    check("qwen-token-plan" not in providers, "qwen-token-plan provider still declared")

    sessions = (by_id.get("session-persistence-jsonl") or {}).get("config") or {}
    check(sessions.get("compression") == "none", f"session compression is {sessions.get('compression')!r}")
    check(isinstance(sessions.get("root"), dict), "session root is not the DSH_HOME-relative !!js row")

    sandbox = (by_id.get("sandbox") or {}).get("config") or {}
    policy = (by_id.get("sandbox-policy") or {}).get("config") or {}
    presets = ((by_id.get("permission") or {}).get("config") or {}).get("presets") or {}
    approval = (by_id.get("approval") or {}).get("config") or {}
    if expect.get("permissive"):
        # Native DSH owns these rows. The fleet must leave its environment
        # expressions and full-access preset intact, and supply no runner.
        check("runnerCommand" not in sandbox, "fleet sandbox runner still pinned")
        check("DSH_PERMISSION_MODE" in str(policy.get("mode", {}).get("__js", ""))
              if isinstance(policy.get("mode"), dict) else False, "native permission mode overridden")
        check("DSH_PERMISSION_MODE" in str(approval.get("policy", {}).get("__js", ""))
              if isinstance(approval.get("policy"), dict) else False, "native approval policy overridden")
        check(presets.get("danger-full-access") == {"sandbox": "danger-full-access", "approval": "never"},
              "native full-access preset missing")
        with open(expect["policy"], encoding="utf-8") as stream:
            fleet = yaml.safe_load(stream)
        with open(expect["restrictivePolicy"], encoding="utf-8") as stream:
            restrictive = yaml.safe_load(stream)
        section7 = {"sandbox", "sandbox-policy", "approval", "permission"}
        check(all(row["id"] not in section7 for row in fleet), "section 7 remains in fleet overlay")
        check(fleet == [row for row in restrictive if row["id"] not in section7],
              "permissive policy changed rows outside section 7 or their order")
    else:
        check(sandbox.get("runnerCommand") == [expect["runner"]], f"sandbox runnerCommand is {sandbox.get('runnerCommand')!r}")
        check(policy.get("mode") == "workspace-write", f"sandbox-policy mode is {policy.get('mode')!r}")
        check("danger-full-access" not in presets, "danger-full-access preset still offered")
        check(approval.get("policy") == "ask", f"approval policy is {approval.get('policy')!r}")

    workflow = (by_id.get("workflow-ptc") or {}).get("config") or {}
    check(workflow.get("maxConcurrentAgents") == 3, "workflow-ptc maxConcurrentAgents is not 3")
    web = (by_id.get("tool-web") or {}).get("config") or {}
    check(web.get("search") is False and web.get("fetch") is True, f"tool-web is {web!r}")

    if "acp" in by_id:
        acp = by_id["acp"].get("config") or {}
        check(acp.get("provider") == expect.get("acpRoute", route)["provider"], f"acp provider is {acp.get('provider')!r}")

    # Optional, for checks.dsh-plugins: rows whose whole config is pinned,
    # rows that must mount, rows that must not exist at all.
    for row_id, config in expect.get("rows", {}).items():
        got = (by_id.get(row_id) or {}).get("config")
        check(got == config, f"{row_id}: config is {got!r}, expected {config!r}")
    for row_id in expect.get("present", []):
        row = by_id.get(row_id)
        check(row is not None and row.get("disabled") is not True, f"{row_id}: row missing or disabled")
    for row_id in expect.get("disabledRows", []):
        row = by_id.get(row_id)
        check(row is not None and row.get("disabled") is True, f"{row_id}: row missing or enabled")
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
