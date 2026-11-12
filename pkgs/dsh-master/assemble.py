"""Write the rendered Master profile folders and their manifest (build time).

Usage: assemble.py <spec.json> <out>

The spec comes from default.nix: per profile, the package.json content, the
store paths of its cordis.patch.yml and pnpm-workspace.yaml, and the rows a
config dump must show. This writes <out>/profiles/<p>/{package.json,
cordis.patch.yml,pnpm-workspace.yaml} and <out>/manifest.json with each file's
sha256, so `dsh-master` compares digests and never re-renders.
"""

import hashlib
import json
import os
import shutil
import sys


def package_text(package):
    # dsh's own key order (`dsh plugin` writes name, private, dependencies, dsh).
    data = {
        "name": package["name"],
        "private": True,
        "dependencies": package["dependencies"],
        "dsh": {"profile": {"bundles": package["bundles"]}},
    }
    return json.dumps(data, indent=2) + "\n"


def digest(path):
    with open(path, "rb") as stream:
        return hashlib.sha256(stream.read()).hexdigest()


def main(spec_path, out):
    with open(spec_path, encoding="utf-8") as stream:
        spec = json.load(stream)
    manifest = {"profiles": {}}
    for key in ("dsh", "url"):
        if key in spec:
            manifest[key] = spec[key]
    for name, profile in sorted(spec["profiles"].items()):
        folder = os.path.join(out, "profiles", name)
        os.makedirs(folder)
        package = os.path.join(folder, "package.json")
        with open(package, "w", encoding="utf-8") as stream:
            stream.write(package_text(profile["package"]))
        patch = os.path.join(folder, "cordis.patch.yml")
        shutil.copyfile(profile["patch"], patch)
        workspace = os.path.join(folder, "pnpm-workspace.yaml")
        shutil.copyfile(profile["workspace"], workspace)
        manifest["profiles"][name] = {
            "files": {"package.json": digest(package), "cordis.patch.yml": digest(patch), "pnpm-workspace.yaml": digest(workspace)},
            "expect": profile["expect"],
        }
    with open(os.path.join(out, "manifest.json"), "w", encoding="utf-8") as stream:
        json.dump(manifest, stream, indent=2, sort_keys=True)
        stream.write("\n")


if __name__ == "__main__":
    main(*sys.argv[1:])
