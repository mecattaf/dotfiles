"""NAS half of kitty-dsh agent windows: the stdio MCP server and its runner.

They serve two tools to NAS agents, domicile_open_terminal and
domicile_open_chat, and forward one fixed request over strict Tailscale SSH
to the desktop helper in modules/imagine-helpers/agent-windows. Every case
here stops at argument validation, so no SSH connection is ever attempted.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid

HERE = Path(__file__).resolve()
DIRECTORY = HERE.parents[2] / "modules/imagine-helpers/agent-windows"
sys.path.insert(0, str(DIRECTORY))
from transport import ssh_command, tools, validate  # noqa: E402

# The copies running on the NAS agent host since 2026-11-06. The repository
# copy must stay byte-identical until a reviewed change replaces both.
INSTALLED_SHA256 = {
    "server.py": "41f9ce74c2aaa717719148b6ad36d313338b70d9a68acc38ec493c65049420f5",
    "runner.py": "0c3cae75fc20d9e63140baae07fc57cbe5b6acf492ffdcb630e8abf5f353a318",
}
REGISTRY = {"desktops": {"desk": {"tailnetIp": "100.64.0.10", "sshAlias": "desk", "hostKeyAlias": "desk",
                                  "agentWindowLauncher": "/fixed/agent-windows/client"}}}


class Transport(unittest.TestCase):
    def test_two_fixed_tools(self):
        self.assertEqual([t["name"] for t in tools(["desk"])], ["domicile_open_terminal", "domicile_open_chat"])
        for tool in tools(["desk"]):
            self.assertFalse(tool["inputSchema"]["additionalProperties"])
            self.assertEqual(tool["inputSchema"]["properties"]["desktop"]["enum"], ["desk"])

    def test_agent_cannot_choose_focus_workspace_or_command(self):
        value = dict(desktop="desk", requestId=str(uuid.uuid4()), kind="terminal", cwd="/srv/project")
        self.assertEqual(validate(value, ["desk"]), value)
        for key in ["focus", "workspace", "command", "url", "argv"]:
            with self.assertRaises(ValueError):
                validate(dict(value, **{key: "x"}), ["desk"])

    def test_tailnet_only_fixed_remote_command(self):
        record = REGISTRY["desktops"]["desk"]
        args = ssh_command(record)
        self.assertEqual(args[-1], "/fixed/agent-windows/client")
        for option in ["-oBatchMode=yes", "-oStrictHostKeyChecking=yes", "-oForwardAgent=no", "-oClearAllForwardings=yes"]:
            self.assertIn(option, args)
        with self.assertRaises(ValueError):
            ssh_command(dict(record, tailnetIp="192.168.1.10"))


class Server(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.registry = Path(self.temp.name) / "desktops.json"
        self.registry.write_text(json.dumps(REGISTRY))

    def tearDown(self):
        self.temp.cleanup()

    def exchange(self, messages):
        server = DIRECTORY / "server.py"
        self.assertTrue(server.is_file(), "server.py is missing from modules/imagine-helpers/agent-windows")
        # No -I: like its installed wrapper, server.py imports transport from its own directory.
        result = subprocess.run([sys.executable, "-B", "-E", "-s", str(server), "--registry", str(self.registry)],
                                input="".join(json.dumps(m) + "\n" for m in messages),
                                text=True, capture_output=True, timeout=20, check=True)
        return {reply["id"]: reply for reply in map(json.loads, result.stdout.splitlines())}

    def test_byte_identical_to_installed_copy(self):
        for name, digest in INSTALLED_SHA256.items():
            path = DIRECTORY / name
            self.assertTrue(path.is_file(), f"{name} is missing from modules/imagine-helpers/agent-windows")
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), digest, name)

    def test_mcp_handshake_and_listing(self):
        replies = self.exchange([
            dict(jsonrpc="2.0", id=1, method="initialize", params=dict(protocolVersion="2025-06-18")),
            dict(jsonrpc="2.0", id=2, method="tools/list"),
            dict(jsonrpc="2.0", method="notifications/initialized"),
            dict(jsonrpc="2.0", id=3, method="tools/list"),
            dict(jsonrpc="2.0", id=4, method="ping"),
            dict(jsonrpc="2.0", id=5, method="tools/call", params=dict(name="shell_exec", arguments={})),
        ])
        self.assertEqual(replies[1]["result"]["protocolVersion"], "2025-06-18")
        self.assertEqual(replies[1]["result"]["serverInfo"]["name"], "agency-domicile-windows")
        self.assertIn("error", replies[2])  # tools/list before notifications/initialized
        self.assertEqual([t["name"] for t in replies[3]["result"]["tools"]], ["domicile_open_terminal", "domicile_open_chat"])
        self.assertEqual(replies[4]["result"], {})
        self.assertEqual(replies[5]["error"]["code"], -32602)

    def test_invalid_calls_refused_without_transport(self):
        # One call per server: a second call while the first is in flight is answered "busy".
        for arguments in [dict(desktop="desk", requestId="not-a-uuid", cwd="/srv"),
                          dict(desktop="desk", requestId=str(uuid.uuid4()), cwd="/srv", workspace="3"),
                          dict(desktop="other", requestId=str(uuid.uuid4()), cwd="/srv")]:
            with self.subTest(arguments=arguments):
                replies = self.exchange([
                    dict(jsonrpc="2.0", id=1, method="initialize", params=dict(protocolVersion="2025-06-18")),
                    dict(jsonrpc="2.0", method="notifications/initialized"),
                    dict(jsonrpc="2.0", id=2, method="tools/call", params=dict(name="domicile_open_terminal", arguments=arguments)),
                ])
                self.assertTrue(replies[2]["result"]["isError"])
                body = json.loads(replies[2]["result"]["content"][0]["text"])
                self.assertEqual(body["code"], "invalid-arguments")
                self.assertFalse(body["retryAutomatically"])

    def test_runner_refuses_before_any_transport(self):
        runner = DIRECTORY / "runner.py"
        self.assertTrue(runner.is_file(), "runner.py is missing from modules/imagine-helpers/agent-windows")
        request = dict(desktop="desk", requestId=str(uuid.uuid4()), kind="terminal", cwd="relative")
        result = subprocess.run([sys.executable, "-B", "-I", str(runner)], input=json.dumps(dict(registry=REGISTRY, request=request)),
                                text=True, capture_output=True, timeout=20, check=True)
        body = json.loads(result.stdout)
        self.assertFalse(body["ok"])
        self.assertIn(body["code"], {"invalid-arguments", "unavailable"})
        self.assertEqual((body["focusChanged"], body["workspaceChanged"], body["retryAutomatically"]), (False, False, False))


if __name__ == "__main__":
    unittest.main()
