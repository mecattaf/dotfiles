"""Write a pnpm v9 lockfile stub into a profile folder: lockfile.py FOLDER [TAG].

Each package.json dependency is locked at its own specifier, or at TAG in
its place (an earlier install's lockfile)."""

import json
import os
import sys

folder = sys.argv[1]
with open(os.path.join(folder, "package.json"), encoding="utf-8") as stream:
    dependencies = json.load(stream)["dependencies"]
lines = ["lockfileVersion: '9.0'", "", "importers:", "", "  .:", "    dependencies:"]
for dependency, spec in sorted(dependencies.items()):
    if len(sys.argv) > 2:
        spec = spec.split("#")[0] + "#" + sys.argv[2]
    lines += [f"      {json.dumps(dependency)}:", f"        specifier: {json.dumps(spec)}", f"        version: {json.dumps(spec)}"]
with open(os.path.join(folder, "pnpm-lock.yaml"), "w", encoding="utf-8") as stream:
    stream.write("\n".join(lines) + "\n")
