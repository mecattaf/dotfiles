"""domicile-persist with the built kitty-persist program, in real Kitty windows.

No stand-in: the window program is the real `kitty-persist`, the windows are
real Kitty windows on a private headless compositor, and the remote host is a
private sshd on the loopback address. The stack (private directories, the
sshd, the ssh shim, the compositor, Kitty's remote control) is kitty-persist's
own end-to-end harness (its tests/e2e/kpe2e), reached through KP_E2E.

Run it only inside runtime-test, never against a live desktop or session:

    KP_E2E=<kitty-persist checkout>/tests/e2e KP_CLIENT=<built kitty-persist> \\
    KP_HOLDER=<the same program, or its holder name> KP_KITTY=... KP_KITTEN=... \\
    runtime-test -- python3 -m unittest -v tests/domicile-opener/test_real_program.py

Without KP_E2E and KP_CLIENT every case is skipped, so the stand-in suite (and
its flake check) is unchanged.
"""
import json
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import support  # noqa: E402

E2E = os.environ.get("KP_E2E")
CLIENT = os.environ.get("KP_CLIENT")
WRAPPER = str(support.BIN / "domicile-persist")
UUID4 = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")
MARKER = "a6e17a12"

harness = None
if E2E and CLIENT and os.path.isdir(os.path.join(E2E, "kpe2e")):
    sys.path.insert(0, E2E)
    from kpe2e import harness  # noqa: E402


def wait_for(predicate, timeout, what, interval=0.15):
    end = time.monotonic() + timeout
    last = None
    while time.monotonic() < end:
        try:
            last = predicate()
        except (OSError, ValueError, subprocess.SubprocessError, KeyError, IndexError):
            last = None
        if last:
            return last
        time.sleep(interval)
    raise AssertionError(f"timed out after {timeout} s waiting for {what}")


class Window:
    """One Kitty instance the opener started, reached over its own socket."""

    def __init__(self, desk, pid, sock, argv):
        self.desk, self.pid, self.sock, self.argv = desk, pid, sock, argv
        self.cls = argv[argv.index("--class") + 1]

    def rc(self, *args, data=None, check=True):
        cp = subprocess.run([self.desk.st.kitten, "@", "--to", "unix:" + self.sock, *args], input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=self.desk.st.laptop_env(),
                            timeout=20)
        if check and cp.returncode:
            raise subprocess.SubprocessError(f"kitten @ {args[0]}: {cp.stderr.decode(errors='replace')[:300]}")
        return cp

    def alive(self):
        return harness.proc_alive(self.pid)

    def user_vars(self):
        ls = json.loads(self.rc("ls").stdout)
        return [w.get("user_vars") or {} for o in ls for t in o.get("tabs", []) for w in t.get("windows", [])][0]

    def text(self):
        return self.rc("get-text", "--extent", "all").stdout.decode("utf-8", "replace")

    def send(self, text):
        self.rc("send-text", "--stdin", data=text.encode())

    def close(self):
        self.rc("close-window", check=False)

    def attached(self, sid=None, timeout=40):
        def ok():
            u = self.user_vars()
            return u.get("persist_state") == "attached" and (sid is None or u.get("persist_id") == sid) and u
        return wait_for(ok, timeout, f"{self.cls} attached to {sid}")["persist_id"]

    def shows(self, needle, timeout=20):
        return wait_for(lambda: needle in self.text(), timeout, f"{needle!r} in {self.cls}")

    def gone(self, timeout=20):
        wait_for(lambda: not self.alive(), timeout, f"{self.cls} to close")


class Desk:
    """A private desktop: compositor, remote host, the opener and its windows."""

    def __init__(self, test, case, sshd=True, settings=()):
        self.test = test
        out = os.environ.get("DP_OUT") or tempfile.mkdtemp(prefix="dp-out-")
        self.st = harness.Stack(f"dp-{case}", os.path.join(out, case))
        test.addCleanup(self.st.teardown)
        self.st.holder_version()
        self.st.require_kitten()
        conf = Path(self.st.d["conf"]) / "persist.conf"
        conf.write_text(conf.read_text() + "".join(f"{line}\n" for line in settings))
        self.root = Path(self.st.root)
        self.log = self.root / "window.jsonl"
        self.launches = self.root / "launches"
        self.shim = Path(self.st.d["bin"]) / "kitty-shim"
        # The opener's kitty, with a private remote-control socket per instance
        # for the test; everything else on the line is the opener's own.
        q = shlex.quote
        self.shim.write_text(
            "#!/bin/sh\n"
            f"sock={q(str(self.root))}/k-$$.sock\n"
            f"printf '%s\\n' \"$$ $sock $*\" >> {q(str(self.launches))}\n"
            f"exec {q(self.st.kitty)} --config {q(self.st.d['conf'])}/kitty.conf --listen-on unix:$sock"
            " -o allow_remote_control=socket-only \"$@\"\n")
        self.shim.chmod(0o700)
        if sshd:
            self.st.start_sshd()
        self.st.start_sway()
        self.seen = 0

    def env(self, **extra):
        env = self.st.laptop_env()
        env.update(DOMICILE_PERSIST_PROGRAM=self.st.kp_bin, DOMICILE_PERSIST_KITTY=str(self.shim),
                   DOMICILE_PERSIST_HOST=harness.HOST_ALIAS, DOMICILE_PERSIST_LOG=str(self.log))
        env.update(extra)
        return env

    def opener(self, *args, **extra):
        """`domicile-persist open|reopen ...`: it execs Kitty, so it is spawned."""
        return self.st.spawn(f"opener-{len(self.st.procs)}", [sys.executable, WRAPPER, *args], self.env(**extra))

    def run(self, *args, **extra):
        return self.st.run([sys.executable, WRAPPER, *args], self.env(**extra), timeout=90)

    def window(self, timeout=30):
        """The next Kitty instance the opener started."""
        def next_launch():
            lines = self.launches.read_text().splitlines() if self.launches.exists() else []
            if len(lines) <= self.seen:
                return None
            pid, sock, *argv = lines[self.seen].split(" ")
            if not os.path.exists(sock):
                return None
            w = Window(self, int(pid), sock, argv)
            w.user_vars()
            self.seen += 1
            return w
        return wait_for(next_launch, timeout, "a Kitty window from the opener")

    def records(self, everything=True):
        cp = self.st.kp("list", "--host", harness.HOST_ALIAS, *(["--all"] if everything else []), "--json")
        self.test.assertEqual(cp.returncode, 0, cp.stderr)
        return json.loads(cp.stdout)

    def record(self, sid):
        return next((r for r in self.records() if r.get("id") == sid), None)

    def outcomes(self):
        lines = self.log.read_text().splitlines() if self.log.exists() else []
        return [json.loads(line) for line in lines]

    def actions(self):
        return [(o["code"], o["action"]) for o in self.outcomes() if "action" in o]

    def processes(self, word):
        """Laptop-side kitty-persist clients of this stack (argv has `word`)."""
        out = []
        for pid in harness._proc_table():
            argv = harness.proc_cmdline(pid)
            if argv and os.path.basename(argv[0]) == "kitty-persist" and word in argv[1:2] \
                    and "--host" in argv and argv[argv.index("--host") + 1] == harness.HOST_ALIAS:
                out.append(pid)
        return out

    def restart_sshd(self):
        """The remote host is reachable again: the same sshd on the same port."""
        cfg = os.path.join(self.st.d["ssh"], "sshd_config")
        sshd = os.path.realpath(harness.which("sshd"))
        self.st.sshd_proc = self.st.spawn(f"sshd-{len(self.st.procs)}", [sshd, "-D", "-e", "-f", cfg],
                                          self.st._clean_env())

    def stop_sshd(self):
        """The remote host is unreachable: the listener and every connection go."""
        for pid in harness.descendants([self.st.sshd_proc.pid]) | {self.st.sshd_proc.pid}:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        self.st.sshd_proc.wait(10)


@unittest.skipIf(harness is None, "needs KP_E2E (kitty-persist's tests/e2e) and KP_CLIENT (the built program)")
class RealProgram(unittest.TestCase):
    maxDiff = None

    def test_daily_entry_point(self):
        """Meta+Return: create and attach, the class, the list; close leaves the
        session; restore and reopen show it again; a second window takes over."""
        d = Desk(self, "daily")
        home = d.st.d["home"]
        d.opener("open", "--cwd", home)
        w = d.window()
        sid = w.cls.removeprefix("kitty-persist-")
        self.assertRegex(sid, UUID4)
        self.assertFalse(sid.startswith(MARKER))
        self.assertEqual(w.attached(sid), sid)
        wait_for(lambda: w.cls in d.st.sway_app_ids(), 10, "the class as the compositor's app id")
        w.send("echo dp-$((2+3))\r")
        w.shows("dp-5")
        r = d.record(sid)
        self.assertEqual((r["state"], r["clients"], r["labels"], r["launch_cwd"]),
                         ("running", 1, {"opener": "domicile"}, home))
        self.assertEqual(d.outcomes(), [])  # still attached: the first call has not ended
        w.close()
        w.gone()
        self.assertEqual(d.actions(), [(0, "close")])
        wait_for(lambda: d.record(sid)["clients"] == 0, 10, "clients 0 after the close")
        self.assertEqual(d.record(sid)["state"], "running")

        cp = d.run("restore")
        self.assertEqual(cp.returncode, 0, cp.stderr)
        self.assertEqual(json.loads(cp.stdout), {"open": [sid], "resumed": [], "skipped": []})
        w2 = d.window()
        self.assertEqual(w2.cls, "kitty-persist-" + sid)
        w2.attached(sid)
        w2.shows("dp-5")
        listed = json.loads(d.run("sessions", "--json").stdout)
        self.assertEqual([(r["id"], r["clients"]) for r in listed], [(sid, 1)])

        d.opener("reopen", sid)
        w3 = d.window()
        w3.attached(sid)
        w2.gone()  # taken over: its client ends with 15 and the window closes quietly
        self.assertEqual(d.actions()[-1], (15, "close"))
        w3.send("echo dp-$((3+4))\r")
        w3.shows("dp-7")
        w3.close()
        w3.gone()
        self.assertEqual(d.actions(), [(0, "close"), (15, "close"), (0, "close")])
        self.assertEqual([o["line"][0] for o in d.outcomes() if "line" in o], ["new", "attach", "attach"])

    def test_session_that_has_exited(self):
        """exit closes the window at once; reopening it closes at once; the same
        id again offers a new session where the old one was; forget policy."""
        d = Desk(self, "exited")
        work = os.path.join(d.st.d["home"], "work")
        os.mkdir(work)
        d.opener("open", "--cwd", d.st.d["home"])
        w = d.window()
        sid = w.attached()
        w.send(f"cd {work}\r")
        wait_for(lambda: d.record(sid)["cwd"] == work or d.record(sid)["cwd"] == "", 10, "cwd")
        w.send("exit\r")
        w.gone()
        self.assertEqual(d.actions(), [(10, "close")])
        self.assertEqual(d.record(sid)["state"], "exited")

        d.opener("reopen", sid)
        d.window().gone()
        self.assertEqual(d.actions()[-1], (10, "close"))
        self.assertEqual(d.record(sid)["state"], "exited")  # kept by default

        d.opener("open", "--id", sid)
        w = d.window()
        w.shows("Press Enter for a new NAS session")
        self.assertIn("the id is taken by a session that is not running", w.text())
        self.assertEqual(d.outcomes()[-1]["code"], 13)
        w.send("\r")
        new = w.attached()
        self.assertNotEqual(new, sid)
        self.assertEqual(w.cls, "kitty-persist-" + sid)  # the OS window keeps its first class
        r = d.record(new)
        self.assertEqual(r["labels"], {"opener": "domicile"})
        old = d.record(sid)
        self.assertEqual(r["launch_cwd"], old["cwd"] or old["launch_cwd"])
        self.assertEqual(d.actions()[-1], (13, "new"))
        w.send("exit\r")
        w.gone()

        d.opener("open", DOMICILE_PERSIST_ON_EXIT="forget")
        w = d.window()
        gone = w.attached()
        w.send("exit\r")
        w.gone()
        self.assertEqual(d.actions()[-1], (10, "forget"))
        wait_for(lambda: d.record(gone) is None, 10, "the record forgotten")

    def test_first_connection_wait(self):
        """A window opened while the remote host is unreachable attaches by itself
        once it is reachable; after the wait it asks, and Enter attaches."""
        d = Desk(self, "connect", settings=("connect_wait 30",))
        d.stop_sshd()
        d.opener("open", DOMICILE_PERSIST_CONNECT_WAIT="40")
        w = d.window()
        w.shows("Waiting for " + harness.HOST_ALIAS)
        time.sleep(3)
        self.assertTrue(w.alive())
        self.assertTrue(all(o.get("action") in (None, "wait") for o in d.outcomes()))
        self.assertTrue(all(o["code"] == 255 for o in d.outcomes()))
        d.restart_sshd()
        sid = w.attached(timeout=30)
        self.assertEqual(w.cls, "kitty-persist-" + sid)
        self.assertEqual(d.record(sid)["clients"], 1)
        w.send("echo dp-$((4+4))\r")
        w.shows("dp-8")
        w.close()
        w.gone()

        start = len(d.outcomes())
        d.stop_sshd()
        d.opener("open", DOMICILE_PERSIST_CONNECT_WAIT="4")
        w = d.window()
        w.shows("Press Enter to attach again", timeout=40)
        self.assertEqual(d.outcomes()[-1]["code"], 255)
        self.assertIn("wait", [o.get("action") for o in d.outcomes()[start:]])
        d.restart_sshd()
        harness.wait_until(lambda: d.st.ssh("true").returncode == 0, 15, 0.2, "sshd")
        w.send("\r")
        sid = w.attached(timeout=40)
        self.assertEqual(d.record(sid)["labels"], {"opener": "domicile"})
        self.assertIn((255, "again"), d.actions())
        w.close()
        w.gone()

    def test_reattach_after_sleep_and_network_loss(self):
        """A laptop sleep (every laptop process frozen while the remote side drops
        the connection) and a plain network loss: the same window shows the same
        session again by itself; the window program never sees an exit."""
        d = Desk(self, "sleep")
        d.opener("open")
        w = d.window()
        sid = w.attached()
        w.send("echo before-$((5+5))\r")
        w.shows("before-10")
        frozen = d.processes("new") + d.st.ssh_client_pids()
        self.assertTrue(d.processes("new"), "the attach client is the window's kitty-persist new")
        for pid in frozen:
            os.kill(pid, signal.SIGSTOP)
        try:
            for pid in d.st.sshd_connection_pids():
                os.kill(pid, signal.SIGKILL)
            time.sleep(20)  # longer than the 15 s dead-link limit (its S15.17)
        finally:
            for pid in frozen:
                try:
                    os.kill(pid, signal.SIGCONT)
                except ProcessLookupError:
                    pass
        w.attached(sid, timeout=60)
        w.send("echo after-$((6+6))\r")
        w.shows("after-12")
        self.assertEqual(d.outcomes(), [])

        for pid in d.st.sshd_connection_pids():
            os.kill(pid, signal.SIGKILL)
        wait_for(lambda: w.user_vars().get("persist_state") != "attached", 30, "the loss noticed")
        w.attached(sid, timeout=60)
        w.send("echo again-$((7+7))\r")
        w.shows("again-14")
        self.assertEqual(d.outcomes(), [])
        self.assertEqual(d.record(sid)["clients"], 1)
        w.close()
        w.gone()
        self.assertEqual(d.actions(), [(0, "close")])

    def test_lost_session(self):
        """The holder goes (a remote restart): the window asks, and Enter starts a
        new session in the same directory, in the same window."""
        d = Desk(self, "lost")
        work = os.path.join(d.st.d["home"], "lost-here")
        os.mkdir(work)
        d.opener("open", "--cwd", work)
        w = d.window()
        sid = w.attached()
        os.kill(d.record(sid)["daemon_pid"], signal.SIGKILL)
        w.shows("Press Enter for a new NAS session", timeout=60)
        self.assertEqual(d.outcomes()[-1]["code"], 14)
        self.assertEqual(d.record(sid)["state"], "lost")
        w.send("\r")
        new = w.attached()
        self.assertNotEqual(new, sid)
        self.assertEqual(d.record(new)["launch_cwd"], work)
        w.send("echo new-$((8+1))\r")
        w.shows("new-9")
        self.assertEqual(d.actions(), [(14, "new")])
        w.close()
        w.gone()

    def test_ten_windows_at_once(self):
        """Desk item 12, step 5: ten openers at the same moment all attach."""
        d = Desk(self, "ten")
        for _ in range(10):
            d.opener("open")
        windows = [d.window(timeout=60) for _ in range(10)]
        ids = [w.attached(timeout=90) for w in windows]
        self.assertEqual(len(set(ids)), 10)
        self.assertEqual({w.cls for w in windows}, {"kitty-persist-" + s for s in ids})
        running = {r["id"]: r["clients"] for r in d.records(everything=False)}
        self.assertEqual({s: running.get(s) for s in ids}, {s: 1 for s in ids})
        for w in windows:
            w.close()
        for w in windows:
            w.gone()
        self.assertEqual(d.actions(), [(0, "close")] * 10)


if __name__ == "__main__":
    unittest.main()
