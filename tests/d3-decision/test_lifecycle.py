"""Exercise the production supervisor with CPU-only children in runtime-test."""
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys
import tempfile
import time
import unittest


SUPERVISOR = Path(os.environ.get(
    "D3_SUPERVISOR", Path(__file__).resolve().parents[2] / "modules/d3-decision-supervise.sh",
))
WORKER = r"""
import os, pathlib, signal, sys, time
root = pathlib.Path(sys.argv[1])
def stop(signum, frame):
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    (root / 'term').write_text('received')
    time.sleep(0.6)
    (root / 'stopped').write_text('released')
    raise SystemExit(143)
signal.signal(signal.SIGTERM, stop)
(root / 'server.pid').write_text(str(os.getpid()))
if sys.argv[2] == 'normal':
    time.sleep(0.6)
else:
    while True:
        time.sleep(1)
"""
PROBE = r"""
import os, pathlib, sys, time
root = pathlib.Path(sys.argv[1])
while not (root / 'server.pid').exists():
    time.sleep(0.01)
(root / 'guard.pid').write_text(str(os.getppid()))
print(0 if sys.argv[2] == 'low' else 1000000)
"""


def await_file(path, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists() and path.read_text():
            return path.read_text()
        time.sleep(0.01)
    raise AssertionError(f"child did not create {path}")


class Supervisor(unittest.TestCase):
    def exercise(self, *, pressure=False, normal=False):
        with tempfile.TemporaryDirectory(prefix="d3-lifecycle-") as directory:
            root = Path(directory)
            # Source this complete, inspected function-only file, never a text
            # range from a Nix module. It is also included verbatim in production.
            launcher = "\n".join([
                "set -euo pipefail",
                shlex.join([sys.executable, "-c", WORKER, str(root), "normal" if normal else "wait"]) + " &",
                "server=$!",
                "reserve_gib=12; reserve_kib=100",
                "memory_probe=(" + shlex.join([
                    sys.executable, "-c", PROBE, str(root), "low" if pressure else "high",
                ]) + ")",
                "poll_sleep=(sleep 0.05)",
                "source " + shlex.quote(str(SUPERVISOR)),
                "d3_supervise",
            ])
            with (root / "launcher.log").open("w+") as log:
                process = subprocess.Popen(
                    ["bash", "-c", launcher], stdout=log, stderr=log, start_new_session=True,
                )
                try:
                    server = int(await_file(root / "server.pid"))
                    guard = int(await_file(root / "guard.pid"))
                    self.assertNotEqual(guard, process.pid)
                    self.assertNotEqual(guard, server)
                    if not pressure and not normal:
                        # Match llama-swap's process-group TERM delivery.
                        os.killpg(process.pid, signal.SIGTERM)
                    if not normal:
                        await_file(root / "term")
                        time.sleep(0.1)
                        self.assertIsNone(process.poll(), "launcher exited before its slow worker")
                    self.assertEqual(process.wait(timeout=5), 0 if normal else 143)
                    if not normal:
                        self.assertTrue((root / "stopped").exists(), "worker did not finish shutdown")
                    for pid in (server, guard):
                        self.assertFalse(Path(f"/proc/{pid}").exists(), f"unreaped child {pid}")
                    if pressure:
                        log.flush()
                        log.seek(0)
                        self.assertIn("MemAvailable fell below", log.read())
                except BaseException:
                    log.flush()
                    log.seek(0)
                    print(log.read(), file=sys.stderr)
                    raise
                finally:
                    # Clean only this test's private process group, including
                    # descendants if an assertion exposes broken supervision.
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait(timeout=5)

    def test_proxy_term_waits_for_slow_worker_and_reaps_children(self):
        self.exercise()

    def test_memory_guard_waits_for_slow_worker_and_reaps_children(self):
        self.exercise(pressure=True)

    def test_worker_exit_reaps_the_memory_guard(self):
        self.exercise(normal=True)


if __name__ == "__main__":
    unittest.main()
