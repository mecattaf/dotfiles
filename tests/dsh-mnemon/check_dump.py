import json
import sys

import yaml


class Loader(yaml.SafeLoader):
    pass


Loader.add_constructor("tag:yaml.org,2002:js", lambda loader, node: loader.construct_scalar(node))


def rows(tree):
    if isinstance(tree, dict):
        if isinstance(tree.get("id"), str):
            yield tree
        for item in tree.values():
            yield from rows(item)
    elif isinstance(tree, list):
        for item in tree:
            yield from rows(item)


with open(sys.argv[1], encoding="utf-8") as stream:
    by_id = {row["id"]: row for row in rows(yaml.load(stream, Loader=Loader))}
if len(sys.argv) == 2:
    assert "mnemon" not in by_id, "Mnemon leaked into an existing profile"
else:
    with open(sys.argv[2], encoding="utf-8") as stream:
        expected = json.load(stream)
    for name, config in expected.items():
        assert by_id[name].get("config") == config, (name, by_id[name])
    for name in ("mnemon", "mnemon-source-runtime", "mnemon-source-documents", "mnemon-source-memory-spaces", "mnemon-strategy-default-three-tier"):
        assert by_id[name].get("disabled") is not True, name
    for name in ("mnemon-source-skills", "mnemon-strategy-auto-capture", "mnemon-strategy-light-context", "mnemon-strategy-scoped"):
        assert by_id[name].get("disabled") is True, name
print("Mnemon profile composition: ok")
