"""Apply fleet policy to the pinned upstream Web agent presets.

Cordis patches descend into groups, but a preset's config.plugins is data
until a Session mounts it. Generate those complete rows from the installed
bundle so upstream tools and persona changes still follow its version pin.
"""

import pathlib
import sys

import yaml


class JsExpression(str):
    pass


class Loader(yaml.SafeLoader):
    pass


class Dumper(yaml.SafeDumper):
    pass


Loader.add_constructor(
    "tag:yaml.org,2002:js", lambda loader, node: JsExpression(loader.construct_scalar(node))
)
Dumper.add_representer(
    JsExpression,
    lambda dumper, value: dumper.represent_scalar("tag:yaml.org,2002:js", str(value)),
)


def apply_policy(plugins):
    for plugin in plugins:
        row_id = plugin["id"]
        if row_id in {"tool-plugin-manager", "tool-plugin-market", "tool-schedule"}:
            plugin["disabled"] = True
        if row_id == "tool-web":
            plugin.setdefault("config", {}).update(search=False, fetch=True)
        if row_id == "workflow-ptc":
            plugin.setdefault("config", {})["maxConcurrentAgents"] = 3
        if plugin.get("group") and isinstance(plugin.get("config"), list):
            apply_policy(plugin["config"])


def main(bundle):
    patches = [
        {"id": row_id, "disabled": True}
        # The official account is disabled by the fleet policy too. Leaving
        # its controller mounted would wait forever for deepseekAccount.
        for row_id in ("schedule", "ui-schedule", "account-controller", "ui-settings-account")
    ]
    for name in ("standard", "ptc", "minimal", "cordis"):
        source = pathlib.Path(bundle) / "presets" / f"{name}.patch.yml"
        declaration = yaml.load(source.read_text(), Loader=Loader)[0]["insert"][0]
        config = declaration["config"]
        apply_policy(config["plugins"])
        patches.append({"id": declaration["id"], "config": config})
    yaml.dump(patches, sys.stdout, Dumper=Dumper, sort_keys=False)


if __name__ == "__main__":
    main(*sys.argv[1:])
