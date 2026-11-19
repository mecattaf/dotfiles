"""domicile-persist: the window program switches on kitty-persist's exit codes,
and the opener side builds windows from create, attach and list only."""
import json
import os
import pty
import select
import subprocess
import sys
import time
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(__file__))
import support  # noqa: E402

persist = support.load(support.BIN / "domicile-persist", "domicile_persist")
SID = "0f3b2a11-3b1c-4d2e-9f00-0123456789ab"
OTHER = "1a2b3c4d-1111-4222-8333-444455556666"


class Answers:
    """A scripted person at the window: True is Enter, False is Ctrl+D."""

    def __init__(self, *answers):
        self.answers, self.questions = list(answers), []

    def __call__(self, question):
        self.questions.append(question)
        return self.answers.pop(0) if self.answers else False


class Window(unittest.TestCase):
    def setUp(self):
        self.fake = support.Fakes()
        self.addCleanup(lambda: self.fake.close())

    def run_window(self, codes, command="new", answers=(), cwd="/srv/project", cwd_of=None, pauses=None, **env):
        self.fake.codes(codes)
        self.answers = Answers(*answers)
        self.pauses = []
        replies = list(pauses or [])

        def pause(seconds, line):
            self.pauses.append((seconds, line))
            time.sleep(min(seconds, 0.02))
            return replies.pop(0) if replies else True
        with mock.patch.object(persist, "say"), mock.patch.object(persist, "say_inline"):
            return persist.run_window(command, SID, cwd, cwd_of, self.fake.env(**env), ask=self.answers,
                                      pause=pause)

    def sessions_started(self):
        return [c for c in self.fake.calls() if c[0] in ("new", "attach")]

    def test_create_and_open_line(self):
        self.assertEqual(self.run_window([0]), 0)
        self.assertEqual(self.fake.calls(), [["new", "--host", "nas", "--id", SID, "--cwd", "/srv/project",
                                              "--meta", "opener=domicile", "--attach"]])

    def test_reopen_line(self):
        self.assertEqual(self.run_window([0], command="attach", cwd=None), 0)
        self.assertEqual(self.fake.calls(), [["attach", "--host", "nas", SID]])

    def test_host_comes_from_the_desktop_policy(self):
        self.run_window([0], command="attach", DOMICILE_PERSIST_HOST="strix")
        self.assertEqual(self.fake.calls(), [["attach", "--host", "strix", SID]])
        with self.assertRaises(ValueError):
            self.run_window([0], DOMICILE_PERSIST_HOST="nas; rm")

    def test_0_closed_or_detached_leaves_the_session(self):
        self.assertEqual(self.run_window([0]), 0)
        self.assertEqual(self.answers.questions, [])
        self.assertFalse(any(c[0] in ("forget", "kill") for c in self.fake.calls()))

    def test_15_taken_over_closes_quietly(self):
        self.assertEqual(self.run_window([15]), 0)
        self.assertEqual(self.answers.questions, [])
        self.assertEqual(len(self.fake.calls()), 1)

    def test_10_exited_closes_and_keeps_the_record_by_default(self):
        self.assertEqual(self.run_window([10]), 0)
        self.assertEqual(self.answers.questions, [])
        self.assertEqual([c[0] for c in self.fake.calls()], ["new"])

    def test_10_exited_forgets_under_that_policy(self):
        self.assertEqual(self.run_window([10], DOMICILE_PERSIST_ON_EXIT="forget"), 0)
        self.assertEqual(self.fake.calls()[-1], ["forget", "--host", "nas", SID])

    def test_75_reattaches_with_attach(self):
        self.assertEqual(self.run_window([75, 75, 0]), 0)
        self.assertEqual([c[:1] for c in self.sessions_started()], [["new"], ["attach"], ["attach"]])
        self.assertEqual(self.sessions_started()[1], ["attach", "--host", "nas", SID])
        self.assertEqual(self.answers.questions, [])

    def test_75_burst_is_reported_instead_of_looping(self):
        code = self.run_window([75] * 7, answers=(False,))
        self.assertEqual(code, 75)
        self.assertEqual(len(self.sessions_started()), persist.REATTACH_BURST + 1)
        self.assertIn("attach again", self.answers.questions[0])

    def test_14_lost_prompts_and_starts_a_new_id_where_the_old_one_was(self):
        self.fake.listing([support.record(SID, state="lost", cwd="/srv/project/sub")])
        self.assertEqual(self.run_window([14, 0], answers=(True,)), 0)
        self.assertIn("/srv/project/sub", self.answers.questions[0])
        second = self.sessions_started()[1]
        self.assertEqual(second[:3], ["new", "--host", "nas"])
        new_id = second[4]
        self.assertNotEqual(new_id, SID)
        self.assertRegex(new_id, persist.UUID4)
        self.assertEqual(second[5:], ["--cwd-of", SID, "--meta", "opener=domicile", "--attach"])
        self.assertIn(["list", "--host", "nas", "--all", "--json"], self.fake.calls())

    def test_14_lost_prompt_declined_closes_without_a_new_session(self):
        self.fake.listing([support.record(SID, state="lost")])
        self.assertEqual(self.run_window([14], answers=(False,)), 0)
        self.assertEqual(len(self.sessions_started()), 1)

    def test_13_conflict_under_policy_new_starts_without_asking(self):
        self.fake.listing([support.record(SID, state="exited")])
        self.assertEqual(self.run_window([13, 0], DOMICILE_PERSIST_ON_GONE="new"), 0)
        self.assertEqual(self.answers.questions, [])
        self.assertEqual(self.sessions_started()[1][5:7], ["--cwd-of", SID])

    def test_11_no_session_starts_new_in_the_given_directory(self):
        self.assertEqual(self.run_window([11, 0], command="attach", answers=(True,)), 0)
        second = self.sessions_started()[1]
        self.assertEqual(second[0], "new")
        self.assertEqual(second[5:7], ["--cwd", "/srv/project"])
        self.assertNotIn("list", [c[0] for c in self.fake.calls()])

    def test_gone_under_policy_close(self):
        self.assertEqual(self.run_window([14], DOMICILE_PERSIST_ON_GONE="close"), 0)
        self.assertEqual(self.answers.questions, [])
        self.assertEqual(len(self.sessions_started()), 1)

    def test_policy_new_asks_after_three_in_a_row(self):
        self.fake.listing([support.record(SID, state="lost")])
        code = self.run_window([14] * 6, DOMICILE_PERSIST_ON_GONE="new", answers=(False,))
        self.assertEqual(code, 0)
        self.assertEqual(len(self.sessions_started()), 4)
        self.assertEqual(len(self.answers.questions), 1)

    def test_255_reports_and_repeats_the_same_line(self):
        self.assertEqual(self.run_window([255, 0], answers=(True,)), 0)
        first, second = self.sessions_started()
        self.assertEqual(first, second)
        self.assertIn("attach again", self.answers.questions[0])

    def test_255_declined_ends_with_255(self):
        self.assertEqual(self.run_window([255], answers=(False,)), 255)

    def test_255_at_once_is_the_first_connection_wait(self):
        # Opened before the remote host is reachable: no prompt, the same line
        # again until it connects (its S15.13, for the create step too).
        code = self.run_window([255, 255, 0], DOMICILE_PERSIST_CONNECT_WAIT="60")
        self.assertEqual(code, 0)
        self.assertEqual(self.answers.questions, [])
        self.assertEqual(len(self.pauses), 2)
        self.assertIn("Waiting for nas", self.pauses[0][1])
        first, second, third = self.sessions_started()
        self.assertEqual(first, second)
        self.assertEqual(first, third)
        self.assertEqual(first[-1], "--attach")

    def test_first_connection_wait_ends_with_the_prompt(self):
        code = self.run_window([255] * 400, DOMICILE_PERSIST_CONNECT_WAIT="0.3", answers=(False,))
        self.assertEqual(code, 255)
        self.assertGreaterEqual(len(self.pauses), 2)
        self.assertEqual(len(self.answers.questions), 1)
        self.assertIn("attach again", self.answers.questions[0])

    def test_first_connection_wait_q_closes(self):
        code = self.run_window([255, 255, 0], DOMICILE_PERSIST_CONNECT_WAIT="60", pauses=(True, False))
        self.assertEqual(code, 255)
        self.assertEqual(len(self.sessions_started()), 2)
        self.assertEqual(self.answers.questions, [])

    def test_255_after_a_long_run_is_reported_not_waited(self):
        # The attach client already waited its own connect_wait, or q was
        # pressed while it reconnected: ask, do not retry by itself.
        with mock.patch.object(persist, "FAST_FAIL", 0.0):
            self.assertEqual(self.run_window([255, 0], DOMICILE_PERSIST_CONNECT_WAIT="60", answers=(True,)), 0)
        self.assertEqual(self.pauses, [])
        self.assertIn("attach again", self.answers.questions[0])

    def test_reopen_waits_too(self):
        code = self.run_window([255, 0], command="attach", cwd=None, DOMICILE_PERSIST_CONNECT_WAIT="60")
        self.assertEqual(code, 0)
        self.assertEqual(self.sessions_started(), [["attach", "--host", "nas", SID]] * 2)

    def test_log_names_each_call_and_outcome(self):
        log = self.fake.root / "window.jsonl"
        self.fake.listing([support.record(SID, state="exited", cwd="/srv/project")])
        self.assertEqual(self.run_window([13, 10], answers=(True,), DOMICILE_PERSIST_LOG=str(log)), 0)
        lines = [json.loads(line) for line in log.read_text().splitlines()]
        self.assertEqual([(entry.get("code"), entry.get("action")) for entry in lines],
                         [(13, None), (13, "new"), (10, None), (10, "close")])
        self.assertEqual(lines[0]["line"][:4], ["new", "--host", "nas", "--id"])
        self.assertRegex(lines[1]["id"], persist.UUID4)

    def test_78_reports_and_does_not_retry(self):
        self.assertEqual(self.run_window([78, 0], answers=(True,)), 78)
        self.assertEqual(len(self.sessions_started()), 1)
        self.assertIn("close this window", self.answers.questions[0])

    def test_other_codes_are_reported(self):
        for code in (12, 64, 70, 73):
            with self.subTest(code=code):
                self.fake.close()
                self.fake = support.Fakes()
                self.assertEqual(self.run_window([code], answers=(True,)), code)
                self.assertEqual(len(self.sessions_started()), 1)

    def test_missing_program_is_a_requirement_not_met(self):
        env = self.fake.env(PATH="/nonexistent")
        env.pop("DOMICILE_PERSIST_PROGRAM")
        answers = Answers(True)
        with mock.patch.object(persist, "say"), mock.patch.object(persist.Path, "is_file", return_value=False):
            self.assertEqual(persist.run_window("new", SID, None, None, env, ask=answers), 78)


class Lines(unittest.TestCase):
    def test_window_class_and_program(self):
        argv = persist.window_argv("/k/kitty", "/b/domicile-persist", SID, ["new", "--id", SID])
        self.assertEqual(argv, ["/k/kitty", "--class", "kitty-persist-" + SID, "--title", "NAS terminal",
                                "--override", "shell=/b/domicile-persist new", "-e", "/b/domicile-persist",
                                "new", "--id", SID])

    def test_fresh_ids_are_v4_and_never_agent_marked(self):
        import uuid
        marked = uuid.UUID(persist.AGENT_SESSION_MARKER + "-3b1c-4d2e-9f00-0123456789ab")
        plain = uuid.UUID(SID)
        with mock.patch.object(persist.uuid, "uuid4", side_effect=[marked, plain]):
            self.assertEqual(persist.fresh_id(), SID)
        for _ in range(200):
            self.assertRegex(persist.fresh_id(), persist.UUID4)

    def test_ids_must_be_lower_case_v4(self):
        for bad in (SID.upper(), "0f3b2a11-3b1c-1d2e-9f00-0123456789ab", "x", SID + "0"):
            with self.subTest(bad=bad), self.assertRaises(SystemExit), mock.patch("sys.stderr"):
                persist.parse_args(["attach", bad])
        with self.assertRaises(SystemExit), mock.patch("sys.stderr"):
            persist.parse_args(["new", "--cwd", "relative/dir"])
        with self.assertRaises(SystemExit), mock.patch("sys.stderr"):
            persist.parse_args(["new", "--cwd", "/a", "--cwd-of", SID])

    def test_scrub_matches_the_plain_nas_terminal(self):
        terminal = support.load(support.BIN / "domicile-terminal", "domicile_terminal")
        dirty = {"HERDR_PANE_ID": "1", "DOMICILE_HERDR_GATE": "1", "CLAUDECODE": "1",
                 "CLAUDE_CODE_ENTRYPOINT": "cli", "CODEX_THREAD_ID": "t", "HOME": "/h", "PATH": "/p"}
        with mock.patch.dict(os.environ, dirty, clear=True):
            self.assertEqual(terminal.clean_environment(), {"HOME": "/h", "PATH": "/p"})
        self.assertEqual(persist.clean_environment(dirty), {"HOME": "/h", "PATH": "/p"})


class Opener(unittest.TestCase):
    """The opener side as processes, with a fake kitty and kitty-persist."""

    def setUp(self):
        self.fake = support.Fakes()
        self.addCleanup(self.fake.close)

    def run_cli(self, *args, **env):
        return subprocess.run([sys.executable, str(support.BIN / "domicile-persist"), *args],
                              env=self.fake.env(CLAUDECODE="1", HERDR_PANE_ID="3", CODEX_THREAD_ID="t", **env),
                              capture_output=True, text=True, timeout=60)

    def test_open_execs_kitty_with_the_class_and_the_create_line(self):
        result = self.run_cli("open", "--cwd", "/srv/project")
        self.assertEqual(result.returncode, 0, result.stderr)
        [window] = self.fake.windows()
        argv = window["argv"]
        sid = argv[1].removeprefix("kitty-persist-")
        self.assertRegex(sid, persist.UUID4)
        self.assertEqual(argv[0], "--class")
        self.assertEqual(argv[argv.index("-e") + 2:], ["new", "--id", sid, "--cwd", "/srv/project"])
        self.assertTrue(argv[argv.index("--override") + 1].startswith("shell="))
        self.assertTrue(argv[argv.index("--override") + 1].endswith("domicile-persist new"))
        self.assertEqual(window["scrubbed"], ["CLAUDECODE", "HERDR_PANE_ID", "CODEX_THREAD_ID"])

    def test_open_with_a_chosen_id_and_reopen(self):
        self.assertEqual(self.run_cli("open", "--id", SID).returncode, 0)
        self.assertEqual(self.run_cli("reopen", SID).returncode, 0)
        first, second = self.fake.windows()
        self.assertEqual(first["argv"][:2], ["--class", "kitty-persist-" + SID])
        self.assertEqual(first["argv"][first["argv"].index("-e") + 2:], ["new", "--id", SID])
        self.assertEqual(second["argv"][:2], ["--class", "kitty-persist-" + SID])
        self.assertEqual(second["argv"][second["argv"].index("-e") + 2:], ["attach", SID])

    def restore_listing(self):
        mine, theirs, resumed, shown, gone = (
            "11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222",
            "33333333-3333-4333-8333-333333333333", "44444444-4444-4444-8444-444444444444",
            "55555555-5555-4555-8555-555555555555")
        self.fake.listing([
            support.record(mine, labels={"opener": "domicile"}),
            support.record(theirs),
            support.record(resumed, resumed={"at": "2026-11-18T00:00:00Z", "count": 1}),
            support.record(shown, clients=1, labels={"opener": "domicile"}),
            support.record(gone, state="exited", labels={"opener": "domicile"}),
        ])
        return mine, theirs, resumed

    def test_restore_reads_list_and_reopens_detached_sessions(self):
        mine, theirs, resumed = self.restore_listing()
        result = self.run_cli("restore", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"open": [mine, resumed], "resumed": [resumed], "skipped": []})
        self.assertEqual(self.fake.windows(), [])
        self.assertIn(["list", "--host", "nas", "--json"], self.fake.calls())

        result = self.run_cli("restore", "--any", "--limit", "2")
        self.assertEqual(json.loads(result.stdout)["skipped"], [resumed])
        deadline = time.monotonic() + 20
        while len(self.fake.windows()) < 2 and time.monotonic() < deadline:
            time.sleep(.05)
        opened = sorted(w["argv"][1] for w in self.fake.windows())
        self.assertEqual(opened, sorted("kitty-persist-" + s for s in (mine, theirs)))
        for window in self.fake.windows():
            sid = window["argv"][1].removeprefix("kitty-persist-")
            self.assertEqual(window["argv"][window["argv"].index("-e") + 2:], ["attach", sid])

    def test_sessions_reads_list_all(self):
        self.restore_listing()
        result = self.run_cli("sessions", "--all")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(result.stdout.splitlines()), 5)
        self.assertIn("resumed=1", result.stdout)
        self.assertIn(["list", "--host", "nas", "--all", "--json"], self.fake.calls())
        result = self.run_cli("sessions", "--json")
        self.assertEqual(len(json.loads(result.stdout)), 4)

    def test_window_program_requires_a_terminal(self):
        result = self.run_cli("new", "--id", SID)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.fake.calls(), [])


class InWindow(unittest.TestCase):
    """The window program on a real pseudo-terminal, as Kitty would run it."""

    def setUp(self):
        self.fake = support.Fakes()
        self.addCleanup(self.fake.close)

    def run_in_pty(self, args, keys, codes, **env):
        self.fake.codes(codes)
        leader, follower = pty.openpty()
        child = subprocess.Popen([sys.executable, str(support.BIN / "domicile-persist"), *args],
                                 stdin=follower, stdout=follower, stderr=follower,
                                 env=self.fake.env(**env), start_new_session=True)
        os.close(follower)
        seen, deadline = b"", time.monotonic() + 30
        for key in keys:
            while key[0] not in seen and time.monotonic() < deadline:
                ready, _, _ = select.select([leader], [], [], .1)
                if ready:
                    seen += os.read(leader, 4096)
            os.write(leader, key[1])
        while child.poll() is None and time.monotonic() < deadline:
            ready, _, _ = select.select([leader], [], [], .1)
            if ready:
                try:
                    seen += os.read(leader, 4096)
                except OSError:
                    break
        code = child.wait(timeout=10)
        os.close(leader)
        return code, seen.decode(errors="replace")

    def test_lost_session_prompt_on_a_terminal(self):
        self.fake.listing([support.record(SID, state="lost", cwd="/srv/project")])
        code, screen = self.run_in_pty(["new", "--id", SID], [(b"Press Enter", b"\n")], [14, 0])
        self.assertEqual(code, 0, screen)
        self.assertIn("the session is lost", screen)
        started = [c for c in self.fake.calls() if c[0] == "new"]
        self.assertEqual(len(started), 2)
        self.assertEqual(started[1][5:7], ["--cwd-of", SID])

    def test_connection_failure_then_close_with_ctrl_d(self):
        code, screen = self.run_in_pty(["attach", SID], [(b"attach again", b"\x04")], [255])
        self.assertEqual(code, 255, screen)
        self.assertIn("code 255", screen)

    def test_exit_closes_at_once_without_a_line(self):
        code, screen = self.run_in_pty(["new", "--id", SID], [], [10])
        self.assertEqual(code, 0)
        self.assertEqual(screen.strip(), "")


if __name__ == "__main__":
    unittest.main()
