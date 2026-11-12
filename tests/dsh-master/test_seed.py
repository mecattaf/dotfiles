"""`dsh-master settings seed` against a stub of the floor's settings API.

Usage: DSH_MASTER=<path to dsh-master.py> SEED=<settings.seed.json> python3 -m unittest test_seed

The stub answers like the fork's routes (src/app/http.ts, src/app/settings.ts):
GET /orchestrator/api/settings gives {blocks: {policy, eval: {value, revision}}};
PUT /orchestrator/api/settings/<block> with {value, revision} bumps the revision,
answers 409 on a stale one, and every request without
`x-orchestrator-request: 1` and a loopback Host is a 403.
"""

import contextlib
import importlib.util
import io
import json
import os
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

spec = importlib.util.spec_from_file_location("dsh_master", os.environ["DSH_MASTER"])
dsh_master = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dsh_master)
SEED = os.environ["SEED"]


class Floor:
    def __init__(self, mode="observe"):
        self.blocks = {
            "policy": {"value": {"rules": [{"id": "own", "name": "Own", "enabled": True, "instruction": "Keep me."}], "sources": {}}, "revision": 3},
            "eval": {"value": {"mode": mode, "timeoutSeconds": 120, "model": None}, "revision": 5},
        }
        self.puts = []
        self.conflicts = 0


def serve(floor):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def reply(self, code, body):
            data = json.dumps(body).encode()
            self.send_response(code)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def guarded(self):
            port = self.server.server_address[1]
            if self.headers.get("x-orchestrator-request") != "1" or self.headers.get("host") != f"127.0.0.1:{port}":
                self.reply(403, {"error": "Same-origin management request required"})
                return False
            return True

        def do_GET(self):
            if self.guarded() and self.path == "/orchestrator/api/settings":
                self.reply(200, {"blocks": floor.blocks, "sources": []})

        def do_PUT(self):
            if not self.guarded():
                return
            block = self.path.rsplit("/", 1)[1]
            body = json.loads(self.rfile.read(int(self.headers["content-length"])))
            if floor.conflicts:
                floor.conflicts -= 1
                floor.blocks[block]["revision"] += 1
            if body["revision"] != floor.blocks[block]["revision"]:
                self.reply(409, {"error": "Settings changed. Reload before saving."})
                return
            floor.blocks[block] = {"value": body["value"], "revision": body["revision"] + 1}
            floor.puts.append(block)
            self.reply(200, {"revision": body["revision"] + 1})

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


class Seed(unittest.TestCase):
    def run_seed(self, floor):
        server = serve(floor)
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = dsh_master.main(["settings", "seed", SEED, "--url", f"http://127.0.0.1:{server.server_address[1]}"])
        return code, out.getvalue(), err.getvalue()

    def test_seed_file_fits_the_rule_and_admission_schemas(self):
        # Limits of the fork's RuleSchema and AdmissionRowSchema (src/policy.ts, src/limits.ts).
        with open(SEED, encoding="utf-8") as stream:
            seed = json.load(stream)
        self.assertEqual(sorted(seed), ["admission", "eval", "rules"])
        self.assertEqual(seed["eval"], {"mode": "auto"})
        for rule in seed["rules"]:
            self.assertEqual(sorted(rule), ["enabled", "id", "instruction", "name"])
            self.assertRegex(rule["id"], r"^[a-zA-Z0-9_-]{1,80}$")
            self.assertLessEqual(len(rule["name"]), 100)
            self.assertLessEqual(len(rule["instruction"].strip()), 2000)
        self.assertEqual([rule["id"] for rule in seed["rules"]], ["scheduled", "workflow-node"])
        # The scheduled Source's second header line starts "Due <time>" for a schedule record and
        # "Requested <time>" for a run asked for by hand (src/sources/scheduled.ts header()).
        self.assertIn("judged from the Due or Requested time", seed["rules"][0]["instruction"])
        for table in seed["admission"].values():
            for row in table.values():
                self.assertLessEqual(set(row), {"listedUnaddressed", "unlistedAddressed", "unlistedUnaddressed"})

    def test_seeds_rules_admission_and_mode_then_is_idempotent(self):
        floor = Floor()
        self.assertEqual(self.run_seed(floor), (0, "changed policy eval\n", ""))
        self.assertEqual(floor.puts, ["policy", "eval"])
        policy = floor.blocks["policy"]["value"]
        self.assertEqual([rule["id"] for rule in policy["rules"]], ["own", "scheduled", "workflow-node"])
        self.assertEqual(policy["sources"]["scheduled"]["admission"]["occurrence"], {"unlistedUnaddressed": "inferred"})
        self.assertEqual(policy["sources"]["workflow"]["admission"]["workflow"], {"unlistedUnaddressed": "inferred"})
        self.assertEqual(floor.blocks["eval"]["value"], {"mode": "auto", "timeoutSeconds": 120, "model": None})
        self.assertEqual(self.run_seed(floor), (0, "unchanged\n", ""))
        self.assertEqual(floor.puts, ["policy", "eval"])

    def test_replaces_a_rule_that_differs_and_keeps_other_cells(self):
        floor = Floor(mode="auto")
        policy = floor.blocks["policy"]["value"]
        policy["rules"].append({"id": "scheduled", "name": "Old", "enabled": False, "instruction": "old"})
        policy["sources"]["scheduled"] = {"allowed": [{"id": "x"}], "admission": {"occurrence": {"listedUnaddressed": "explicit"}}}
        self.assertEqual(self.run_seed(floor), (0, "changed policy\n", ""))
        policy = floor.blocks["policy"]["value"]
        self.assertEqual([rule["name"] for rule in policy["rules"]], ["Own", "Scheduled items", "Workflow node"])
        self.assertEqual(policy["sources"]["scheduled"]["allowed"], [{"id": "x"}])
        self.assertEqual(policy["sources"]["scheduled"]["admission"]["occurrence"], {"listedUnaddressed": "explicit", "unlistedUnaddressed": "inferred"})

    def test_never_turns_a_mode_down(self):
        floor = Floor(mode="off")
        code, out, err = self.run_seed(floor)
        self.assertEqual((code, out), (0, "changed policy\n"))
        self.assertIn("eval.mode is off", err)
        self.assertEqual(floor.blocks["eval"]["value"]["mode"], "off")

    def test_leaves_an_unknown_mode_alone(self):
        floor = Floor(mode="paused")
        code, out, err = self.run_seed(floor)
        self.assertEqual((code, out), (0, "changed policy\n"))
        self.assertIn("eval.mode is 'paused'", err)
        self.assertEqual(floor.blocks["eval"]["value"]["mode"], "paused")

    def test_rereads_once_on_a_conflict_and_fails_on_a_second(self):
        floor = Floor()
        floor.conflicts = 1
        self.assertEqual(self.run_seed(floor)[:2], (0, "changed policy eval\n"))
        floor = Floor()
        floor.conflicts = 2
        code, out, err = self.run_seed(floor)
        self.assertEqual((code, out), (1, ""))
        self.assertIn("changed twice", err)


if __name__ == "__main__":
    unittest.main()
