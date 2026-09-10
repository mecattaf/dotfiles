"""Topology regression checks; live laptop reachability is a separate gate."""
import json
from pathlib import Path
import sys

policy = json.loads("\n".join(
    line for line in Path(sys.argv[1]).read_text().splitlines()
    if not line.lstrip().startswith("//")
))
assert set(policy) == {"tagOwners", "acls"}
assert policy["tagOwners"] == {"tag:mesh": ["tom@"], "tag:fleet": ["tom@"]}
assert policy["acls"] == [
    {"action": "accept", "src": ["100.64.0.1/32"], "proto": "tcp", "dst": ["tag:fleet:22"]},
    {"action": "accept", "src": ["tag:fleet"], "proto": "tcp",
     "dst": ["100.64.0.1:8080", "100.64.0.1:8091"]},
]
print("Fleet policy: NAS admin + private updates only; all other flows denied")
