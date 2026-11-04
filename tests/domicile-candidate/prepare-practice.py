#!/usr/bin/env python3
"""Prepare a persisted-state probe and actual helper plan for isolated practice."""
import argparse
import hashlib
import json
from pathlib import Path
import shlex

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--metadata", type=Path, required=True)
p.add_argument("--out", type=Path, required=True)
a = p.parse_args()
m = json.loads(a.metadata.read_text())
a.out.mkdir(parents=True, exist_ok=False)
config = Path(m["keyTable"])
helpers = Path(m["helperDirectory"])
for name in ("domicile-apps", "domicile-terminal", "herdr-domicile-client", "herdr-projector"):
    if not (helpers / name).is_file():
        raise SystemExit("missing bundled sibling helper: " + name)
probe = """import * as starter from %s;
export const output = starter.output;
export const shell_options = starter.shell_options;
export const startup = starter.startup;
export const Shell: typeof starter.Shell = (root, domicile) => {
  globalThis.localStorage.setItem("night-light:v1", JSON.stringify({on: true}));
  starter.Shell(root, domicile);
  const after = JSON.parse(globalThis.localStorage.getItem("night-light:v1") ?? "null");
  if (after?.on !== false) throw new Error("Starter did not clear persisted global tint");
  console.log("DOMICILE_STARTER_PROBE: persisted-on -> off");
};
""" % json.dumps(str(config))
(a.out / "persisted-state.tsx").write_text(probe)
(a.out / "domicile-apps").write_text("#!/bin/sh\nexec " + shlex.quote(str(helpers / "domicile-apps")) + ' "$@"\n')
(a.out / "domicile-apps").chmod(0o755)
(a.out / "chords.json").write_text(json.dumps({"terminal": [125, 28], "rescue": [125, 42, 28],
                                               "browser": [125, 29, 48], "files": [125, 29, 18]}, indent=2) + "\n")
(a.out / "expectations.json").write_text(json.dumps({"terminal": ["kitty", "--class", "domicile-terminal"],
                                                     "rescue": ["kitty", "--class", "domicile-rescue"],
                                                     "browser": ["chrome", "--ozone-platform=wayland"],
                                                     "files": ["nautilus"]}, indent=2) + "\n")
receipt = {"candidateMetadata": str(a.metadata.resolve()), "config": str(config),
           "configSha256": hashlib.sha256(config.read_bytes()).hexdigest(),
           "source": "The exact production Shell/config, with a persisted-on precondition and read-back assertion.",
           "helperDirectory": str(helpers), "compositor": m["compositor"],
           "nativeEngine": m["nativeEngine"],
           "note": "Private runtime/HOME and no NAS transport; headless does not qualify panel/input behavior."}
(a.out / "inputs.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps(receipt, indent=2))
