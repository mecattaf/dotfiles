import contextlib
import copy
import importlib.util
import io
import shlex
import sys
import unittest
from unittest.mock import patch


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


executor = load("executor", sys.argv.pop(1))
transport = load("transport", sys.argv.pop(1))
HOSTS = ["client", "nas", "strix-coordinator", "strix-worker"]
POLICY = {"hosts": HOSTS, "tailnetSuffix": "tail8dd1.ts.net", "subnet": "10.42.0.0/24", "exitNode": "nas"}


def status(host):
    nodes = {name: {"ID": name + "-id", "DNSName": name + ".tail8dd1.ts.net.", "Online": True} for name in HOSTS}
    nodes["nas"].update(ExitNodeOption=True, PrimaryRoutes=[POLICY["subnet"]])
    return {
        "BackendState": "Running", "CurrentTailnet": {"MagicDNSSuffix": POLICY["tailnetSuffix"]},
        "Self": nodes.pop(host), "Peer": nodes,
        **({} if host == "nas" else {"ExitNodeStatus": {"ID": "nas-id", "Online": True}}),
    }


class TransportTest(unittest.TestCase):
    def test_all_four_vantage_points(self):
        for name in HOSTS:
            self.assertEqual(transport.check(status(name), POLICY, name), [])

    def test_reject_incomplete_or_wrong_enrollment(self):
        cases = []
        bad = status("client"); bad["Peer"].pop("strix-worker"); cases.append(bad)
        bad = status("client"); bad["CurrentTailnet"]["MagicDNSSuffix"] = "wrong.ts.net"; cases.append(bad)
        bad = status("client"); bad["Peer"]["strix-worker"]["Online"] = False; cases.append(bad)
        bad = status("client"); bad["Self"]["KeyExpiry"] = "2027-01-01T00:00:00Z"; cases.append(bad)
        bad = status("client"); bad["Peer"]["nas"]["Expired"] = True; cases.append(bad)
        bad = status("client"); bad["ExitNodeStatus"]["ID"] = "other-id"; cases.append(bad)
        bad = status("client"); bad["Peer"]["nas"]["PrimaryRoutes"] = []; cases.append(bad)
        bad = status("client"); bad["Peer"]["nas"]["ExitNodeOption"] = False; cases.append(bad)
        bad = status("client"); bad["Peer"]["duplicate"] = copy.deepcopy(bad["Peer"]["nas"]); cases.append(bad)
        for bad in cases:
            self.assertTrue(transport.check(bad, POLICY, "client"))

    def test_nas_cannot_route_through_itself(self):
        bad = status("nas")
        bad["ExitNodeStatus"] = {"ID": "nas-id", "Online": True}
        self.assertTrue(transport.check(bad, POLICY, "nas"))


class ExecutorTest(unittest.TestCase):
    def test_quotes_remote_cwd_and_every_argument(self):
        cwd = "/home/tom/checkout with 'quotes' $(false)"
        args = ["printf", "%s", "a b", "$(false)", "x'y", "", "line\nbreak"]
        command = executor.ssh_command("strix-worker", cwd, args)
        remote = shlex.split(command[-1])
        self.assertEqual(remote, ["cd", "--", cwd, "&&", "exec", *args])
        self.assertIn("-oStrictHostKeyChecking=yes", command)
        self.assertIn("-oForwardAgent=no", command)
        self.assertEqual(command[-2], "strix-worker")

    def test_rejects_local_target_relative_cwd_and_empty_command(self):
        for host, cwd, args in [("nas", "/tmp", ["make"]), ("strix-worker", "relative", ["make"]), ("strix-worker", "/tmp", [])]:
            with self.assertRaises(ValueError):
                executor.ssh_command(host, cwd, args)

    def test_propagates_failure_and_never_retries_locally(self):
        with patch.object(executor.subprocess, "run") as run:
            run.return_value.returncode = 42
            self.assertEqual(executor.main(["strix-coordinator", "--cwd", "/tmp/checkout", "--", "make"]), 42)
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args.args[0][0], "ssh")
        with patch.object(executor.subprocess, "run", side_effect=OSError("offline")) as run:
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(executor.main(["strix-worker", "--cwd", "/tmp", "--", "make"]), 1)
            self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
