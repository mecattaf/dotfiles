#!/usr/bin/env python3
"""Prove native swap recovery without saving the edited source file.

Run with runtime-test -- python3 this.py --nvim /path/to/nvim.
Only a private editor is deliberately killed; no desktop or user service is used.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

assert Path("/proc/1/comm").read_text().strip() == "bwrap", "use runtime-test"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--nvim", required=True)
parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[2])
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="nvim-swap-recovery-") as folder:
    root = Path(folder)
    env = dict(os.environ, HOME=str(root), XDG_STATE_HOME=str(root / "state"),
               XDG_CONFIG_HOME=str(root / "config"), XDG_DATA_HOME=str(root / "data"),
               XDG_CACHE_HOME=str(root / "cache"), NVIM_APPNAME="nvim-remote")
    filename = root / "recover me.md"
    filename.write_text("disk original\n")
    init = root / "init.lua"
    options = args.source_root / "home/dot_config/nvim/lua/options.lua"
    init.write_text("dofile(" + json.dumps(str(options)) + ")\n")
    socket = root / "server.sock"
    process = subprocess.Popen([args.nvim, "--headless", "-u", str(init),
                                "--listen", str(socket), str(filename)],
                               env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        for _ in range(100):
            if socket.exists():
                break
            if process.poll() is not None:
                raise AssertionError(process.communicate())
            time.sleep(.05)
        assert socket.exists(), "private editor did not start"
        def rpc(expression):
            result = subprocess.run([args.nvim, "--server", str(socket),
                                     "--remote-expr", expression],
                                    env=env, capture_output=True, text=True,
                                    timeout=5, check=True)
            return result.stdout.strip()
        rpc("""execute('call setline(1, ["RECOVERED UNSAVED", "second line"]) | preserve')""")
        swap = Path(rpc("swapname(bufnr())"))
        assert swap.is_file() and swap.stat().st_size > 0
        assert str(swap).startswith(str(root / "state"))
        assert filename.read_text() == "disk original\n"
        process.kill()
        process.wait(timeout=5)
        recovered = root / "recovered.txt"
        command = "call writefile(getline(1, '$'), " + json.dumps(str(recovered)) + ")"
        result = subprocess.run([args.nvim, "--headless", "-u", str(init),
                                 "-r", str(filename), "-c", command, "-c", "qall!"],
                                env=env, capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, result.stderr
        assert recovered.read_text() == "RECOVERED UNSAVED\nsecond line\n", result.stderr
        assert filename.read_text() == "disk original\n"
        print("SWAP_RECOVERY_OK: unsaved buffer recovered; source file unchanged")
    finally:
        if process.poll() is None:
            process.kill()
        process.communicate(timeout=5)
