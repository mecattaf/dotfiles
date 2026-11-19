"""Agent-window helper: a terminal request opens a persistent session whose
class is kitty-persist-<id>, with the id derived from the request, while the
protocol-version-1 request and reply stay exactly as they were."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(__file__))
import support  # noqa: E402

sys.path.insert(0, str(support.AGENT_WINDOWS))
import transport  # noqa: E402
client = support.load(support.AGENT_WINDOWS / "client.py", "agent_windows_client")
persist = support.load(support.BIN / "domicile-persist", "domicile_persist_for_agents")

REQUEST = {"desktop": "zenbook", "requestId": "6f1c2b9e-0d4a-11ef-8b1a-0242ac120002", "kind": "terminal",
           "cwd": "/srv/project"}
UUID4 = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")


def imagine_pattern():
    text = (support.IMAGINE / "agentIdentity.ts").read_text()
    marker = re.search(r'AGENT_SESSION_MARKER = "([0-9a-f]{8})"', text).group(1)
    terminal = re.search(r'const agentTerminal = "([^"]+)"', text).group(1)
    return marker, re.compile("^" + terminal + "$")


class SessionIds(unittest.TestCase):
    def test_derived_id_is_v4_marked_and_stable(self):
        sid = transport.session_id(REQUEST["requestId"])
        self.assertRegex(sid, UUID4)
        self.assertTrue(sid.startswith(transport.AGENT_SESSION_MARKER + "-"))
        self.assertEqual(sid, transport.session_id(REQUEST["requestId"]))
        self.assertNotEqual(sid, transport.session_id("6f1c2b9e-0d4a-11ef-8b1a-0242ac120003"))

    def test_marker_agrees_across_helper_opener_and_imagine(self):
        marker, pattern = imagine_pattern()
        self.assertEqual(marker, transport.AGENT_SESSION_MARKER)
        self.assertEqual(marker, persist.AGENT_SESSION_MARKER)
        self.assertRegex(client.tag(REQUEST), pattern)

    def test_terminal_tag_is_the_kitty_persist_class(self):
        self.assertEqual(client.tag(REQUEST), "kitty-persist-" + transport.session_id(REQUEST["requestId"]))

    def test_chat_tag_is_unchanged(self):
        chat = {"desktop": "zenbook", "requestId": REQUEST["requestId"], "kind": "chat", "sessionId": "session-x"}
        self.assertRegex(client.tag(chat), r"^agencychata6e17a11[0-9a-f]{24}$")


class Protocol(unittest.TestCase):
    def test_request_fields_stay_fixed(self):
        self.assertEqual(transport.validate(dict(REQUEST), ["zenbook"]), REQUEST)
        for extra in ({"command": "sh"}, {"session": "x"}, {"class": "y"}):
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                transport.validate(dict(REQUEST, **extra), ["zenbook"])

    def test_reply_shape_is_protocol_version_1(self):
        # The hand-installed NAS server keeps its copy; a reply with another
        # field set would be refused there, so the set must not change.
        self.assertEqual(set(transport.failure(REQUEST, "busy")),
                         {"ok", "code", "desktop", "requestId", "kind", "windowId", "workspace",
                          "focusChanged", "workspaceChanged", "retryAutomatically"})

    def test_run_accepts_the_reply_imagine_writes(self):
        reply = dict(transport.failure(REQUEST, "ok"), ok=True, windowId="app:7", workspace="3")
        registry = {"desktops": {"zenbook": {"tailnetIp": "100.64.0.9", "sshAlias": "zenbook",
                                             "hostKeyAlias": "zenbook", "agentWindowLauncher": "/x/client"}}}

        class Child:
            pid, returncode = 1, 0

            def communicate(self, payload=None, timeout=None):
                return json.dumps(reply).encode(), b""

        with tempfile.TemporaryDirectory() as cwd, mock.patch.object(transport.subprocess, "Popen", return_value=Child()):
            self.assertEqual(transport.run(registry, dict(REQUEST, cwd=cwd)), dict(reply, requestId=REQUEST["requestId"]))

    def test_tool_schema_is_unchanged(self):
        terminal = next(t for t in transport.tools(["zenbook"]) if t["name"] == "domicile_open_terminal")
        self.assertEqual(terminal["inputSchema"]["required"], ["desktop", "requestId", "cwd"])
        self.assertFalse(terminal["inputSchema"]["additionalProperties"])
        self.assertIn("persistent", terminal["description"])


class Launch(unittest.TestCase):
    def test_launch_opens_kitty_on_the_persistent_session(self):
        with tempfile.TemporaryDirectory() as home:
            directory = Path(home) / client.ROOT / REQUEST["requestId"].replace("-", "")
            directory.mkdir(parents=True, mode=0o700)
            value = dict(REQUEST, tag=client.tag(REQUEST))
            child = mock.Mock(pid=4242)
            with mock.patch.object(client.Path, "home", return_value=Path(home)), \
                    mock.patch.object(client.subprocess, "Popen", return_value=child) as popen:
                self.assertEqual(client.launch(value), {"tag": value["tag"], "pid": 4242})
            argv = popen.call_args.args[0]
            sid = transport.session_id(REQUEST["requestId"])
            program = str(Path(home) / ".local/bin/domicile-persist")
            self.assertEqual(argv, [client.KITTY, "--class", "kitty-persist-" + sid, "--title", "NAS terminal",
                                    "--override", "shell=" + program + " new",
                                    "-e", program, "new", "--id", sid, "--cwd", "/srv/project"])
            self.assertTrue(popen.call_args.kwargs["start_new_session"])
            self.assertEqual(popen.call_args.kwargs["stdin"], subprocess.DEVNULL)

    def test_launch_refuses_the_old_tag(self):
        old = dict(REQUEST, tag="agencyagent" + REQUEST["requestId"].replace("-", ""))
        with mock.patch.object(client.subprocess, "Popen") as popen, self.assertRaises(ValueError):
            client.launch(old)
        popen.assert_not_called()

    def test_window_program_accepts_the_derived_id(self):
        sid = transport.session_id(REQUEST["requestId"])
        args = persist.parse_args(["new", "--id", sid, "--cwd", "/srv/project"])
        self.assertEqual((args.id, args.cwd), (sid, "/srv/project"))


if __name__ == "__main__":
    unittest.main()
