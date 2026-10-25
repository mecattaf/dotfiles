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
# Tom, 2026-10-25: the worker is off the tailnet and no host selects the NAS exit.
HOSTS = ["client", "nas", "strix-coordinator"]
EXIT_CLIENTS = []
POLICY = {"hosts": HOSTS, "tailnetSuffix": "tail8dd1.ts.net", "subnet": "10.42.0.0/24", "exitNode": "nas",
          "exitNodeClients": EXIT_CLIENTS}


def status(host):
    nodes = {name: {"ID": name + "-id", "DNSName": name + ".tail8dd1.ts.net.", "Online": True} for name in HOSTS}
    nodes["nas"].update(ExitNodeOption=True, PrimaryRoutes=[POLICY["subnet"]])
    return {
        "BackendState": "Running", "CurrentTailnet": {"MagicDNSSuffix": POLICY["tailnetSuffix"]},
        "Self": nodes.pop(host), "Peer": nodes,
        **({"ExitNodeStatus": {"ID": "nas-id", "Online": True}} if host in EXIT_CLIENTS else {}),
    }


class TransportTest(unittest.TestCase):
    def test_every_vantage_point(self):
        for name in HOSTS:
            self.assertEqual(transport.check(status(name), POLICY, name), [])

    def test_reject_incomplete_or_wrong_enrollment(self):
        for vantage, other in [("client", "strix-coordinator"), ("strix-coordinator", "client")]:
            cases = []
            bad = status(vantage); bad["Peer"].pop(other); cases.append(bad)
            bad = status(vantage); bad["CurrentTailnet"]["MagicDNSSuffix"] = "wrong.ts.net"; cases.append(bad)
            bad = status(vantage); bad["Peer"][other]["Online"] = False; cases.append(bad)
            bad = status(vantage); bad["Self"]["KeyExpiry"] = "2027-01-01T00:00:00Z"; cases.append(bad)
            bad = status(vantage); bad["Peer"]["nas"]["Expired"] = True; cases.append(bad)
            bad = status(vantage); bad["Peer"]["nas"]["PrimaryRoutes"] = []; cases.append(bad)
            bad = status(vantage); bad["Peer"]["nas"]["ExitNodeOption"] = False; cases.append(bad)
            bad = status(vantage); bad["Peer"]["duplicate"] = copy.deepcopy(bad["Peer"]["nas"]); cases.append(bad)
            for bad in cases:
                self.assertTrue(transport.check(bad, POLICY, vantage))

    def test_listed_exit_client_must_select_the_online_nas_exit(self):
        policy = dict(POLICY, exitNodeClients=["strix-coordinator"])
        good = status("strix-coordinator"); good["ExitNodeStatus"] = {"ID": "nas-id", "Online": True}
        self.assertEqual(transport.check(good, policy, "strix-coordinator"), [])
        bad = copy.deepcopy(good); bad["ExitNodeStatus"]["ID"] = "other-id"
        self.assertTrue(transport.check(bad, policy, "strix-coordinator"))
        self.assertTrue(transport.check(status("strix-coordinator"), policy, "strix-coordinator"))

    def test_no_host_selects_an_exit_node(self):
        # D-55 "no-exit-client": a NAS outage must not take the Zenbook's internet,
        # and the recovery coordinator must not depend on the NAS either.
        for vantage in ["client", "strix-coordinator"]:
            bad = status(vantage); bad["ExitNodeStatus"] = {"ID": "nas-id", "Online": True}
            self.assertTrue(transport.check(bad, POLICY, vantage))

    def test_worker_is_not_a_tailnet_identity(self):
        # A stray strix-worker node is not required and not counted as missing.
        extra = status("client")
        extra["Peer"]["strix-worker"] = {"ID": "w-id", "DNSName": "strix-worker.tail8dd1.ts.net.", "Online": False}
        self.assertEqual(transport.check(extra, POLICY, "client"), [])

    def test_policy_without_consumer_list_keeps_every_host_on_the_exit(self):
        legacy = {k: v for k, v in POLICY.items() if k != "exitNodeClients"}
        self.assertTrue(transport.check(status("client"), legacy, "client"))
        on_exit = status("strix-coordinator"); on_exit["ExitNodeStatus"] = {"ID": "nas-id", "Online": True}
        self.assertEqual(transport.check(on_exit, legacy, "strix-coordinator"), [])

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
