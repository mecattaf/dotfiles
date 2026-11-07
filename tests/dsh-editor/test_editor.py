#!/usr/bin/env python3
"""Run through runtime-test on compute; uses only temporary files and owned Nvim PIDs."""

import concurrent.futures
import json
import os
from pathlib import Path
import pty
import shutil
import signal
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
EDITOR = ROOT / "home/dot_local/bin/dsh-editor"
NVIM = shutil.which("nvim")


class EditorIntegration(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="editor-test-", dir=ROOT)
        self.base = Path(self.temp.name)
        self.project = self.base / "project with spaces"
        self.project.mkdir()
        self.env = dict(os.environ, XDG_STATE_HOME=str(self.base / "state"), TERM="xterm-kitty")
        self.servers = set()
        self.clients = []

    def tearDown(self):
        for client in self.clients:
            if client.poll() is None:
                client.terminate()
                client.wait(timeout=5)
        for pid in self.servers:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            alive = False
            for pid in self.servers:
                try:
                    os.kill(pid, 0)
                    alive = True
                except ProcessLookupError:
                    pass
            if not alive:
                break
            time.sleep(0.02)
        self.temp.cleanup()

    def launch(self, directory=None, *files):
        out = subprocess.run([str(EDITOR), "--nvim", NVIM, "--init", "NONE", "--directory",
                              str(directory or self.project), "--no-attach", "--json", "--", *files],
                             check=True, env=self.env, text=True, capture_output=True, timeout=25)
        record = json.loads(out.stdout)
        self.servers.add(record["pid"])
        return record

    def lua(self, server, source):
        body = source if ';' in source or source.startswith('return ') else 'return ' + source
        expression = "json_encode(luaeval(" + json.dumps('(function() ' + body + ' end)()') + "))"
        out = subprocess.run([NVIM, "--headless", "-u", "NONE", "--server", server["socket"], "--remote-expr", expression],
                             check=False, env=self.env, text=True, capture_output=True, timeout=5)
        self.assertEqual(out.returncode, 0, out.stderr)
        return json.loads(out.stdout)

    def wait_for(self, callback, seconds=5):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            value = callback()
            if value:
                return value
            time.sleep(0.05)
        self.fail("condition did not become true")

    def attach(self, server):
        master, slave = pty.openpty()
        client = subprocess.Popen([NVIM, "--server", server["socket"], "--remote-ui"],
                                  stdin=slave, stdout=slave, stderr=slave, env=self.env,
                                  start_new_session=True)
        os.close(slave)
        self.clients.append(client)
        self.wait_for(lambda: self.lua(server, "#vim.api.nvim_list_uis()") == 1)
        return client, master

    def test_directory_identity_concurrency_and_safe_file_arguments(self):
        link = self.base / "alias"
        link.symlink_to(self.project, target_is_directory=True)
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            records = list(executor.map(lambda _: self.launch(link), range(4)))
        self.assertEqual(len({r["pid"] for r in records}), 1)
        server = records[0]
        name = "-notes $(touch should-not-exist).md"
        original = self.project / name
        original.write_text("saved\n")
        again = self.launch(self.project, name)
        self.assertEqual(server["socket"], again["socket"])
        self.assertEqual(self.lua(server, "vim.api.nvim_buf_get_name(0)"), str(original))
        self.assertFalse((self.project / "should-not-exist").exists())
        other = self.base / "other"
        other.mkdir()
        self.assertNotEqual(self.launch(other)["pid"], server["pid"])
        self.assertEqual(Path(server["state"]).stat().st_mode & 0o777, 0o700)

    def test_native_ui_disconnect_keeps_unsaved_live_buffer(self):
        saved = self.project / "work.md"
        saved.write_text("on disk\n")
        server = self.launch(self.project, "work.md")
        self.lua(server, "vim.api.nvim_buf_set_lines(0, 0, -1, false, {'unfinished work'}); return true")
        client, master = self.attach(server)
        client.kill()
        client.wait(timeout=5)
        os.close(master)
        self.wait_for(lambda: self.lua(server, "#vim.api.nvim_list_uis()") == 0)
        self.assertEqual(self.launch()["pid"], server["pid"])
        self.assertEqual(self.lua(server, "vim.api.nvim_buf_get_lines(0, 0, -1, false)"), ["unfinished work"])
        self.assertEqual(saved.read_text(), "on disk\n")
        second, master = self.attach(server)
        self.lua(server, "vim.cmd('detach'); return true")
        second.wait(timeout=5)
        os.close(master)
        self.assertEqual(self.launch()["pid"], server["pid"])

    def test_crash_recovers_named_and_unnamed_without_overwriting_files(self):
        saved = self.project / "draft.md"
        saved.write_text("original file\n")
        server = self.launch(self.project, "draft.md")
        self.lua(server, "vim.api.nvim_buf_set_lines(0,0,-1,false,{'unsaved named'}); "
                 "vim.cmd('enew'); vim.api.nvim_buf_set_lines(0,0,-1,false,{'unsaved scratch'}); "
                 "vim.cmd('DshCheckpoint'); return true")
        manifest = Path(server["state"]) / "recovery.json"
        index = json.loads(manifest.read_text())
        self.assertEqual(len(index["buffers"]), 2)
        for filename in index["buffers"]:
            self.assertEqual((manifest.parent / filename).stat().st_mode & 0o777, 0o600)
        os.kill(server["pid"], signal.SIGKILL)
        # The native daemon owns only its own socket; ensure() must recognize
        # an actually refused Unix socket rather than unlink a busy server.
        time.sleep(0.1)
        restarted = self.launch()
        self.assertNotEqual(restarted["pid"], server["pid"])
        contents = self.lua(restarted, "(function() local r={} for _,b in ipairs(vim.api.nvim_list_bufs()) do "
                            "if vim.b[b].dsh_recovery_original ~= nil then "
                            "r[#r+1]=vim.api.nvim_buf_get_lines(b,0,-1,false)[1] end end return r end)()")
        self.assertEqual(set(contents), {"unsaved named", "unsaved scratch"})
        self.assertEqual(saved.read_text(), "original file\n")
        self.assertFalse(self.lua(restarted, "pcall(vim.cmd, 'write')"))
        self.lua(restarted, "vim.cmd('DshCheckpoint'); return true")
        self.assertEqual(len(json.loads(manifest.read_text())["buffers"]), 2)
        self.lua(restarted, "vim.cmd('DshRecover'); return true")
        self.assertEqual(self.lua(restarted, "(function() local n=0 for _,b in ipairs(vim.api.nvim_list_bufs()) do "
                         "if vim.b[b].dsh_recovery_original ~= nil then n=n+1 end end return n end)()"), 2)
        destination = self.project / 'recovered-draft.md'
        self.lua(restarted, "vim.cmd('DshRecoverySave ' .. vim.fn.fnameescape(" + json.dumps(str(destination)) + ")); return true")
        self.assertIn(destination.read_text().strip(), {'unsaved named', 'unsaved scratch'})
        self.assertEqual(saved.read_text(), "original file\n")
        self.assertTrue(self.lua(restarted, "vim.o.swapfile"))

    def test_recovery_reports_filesystem_failure(self):
        server = self.launch()
        self.lua(server, "vim.api.nvim_buf_set_lines(0,0,-1,false,{'keep me'}); return true")
        # An impossible atomic target exercises the error path without filling
        # a disk, masking warnings, or touching any live service.
        state = Path(server["state"])
        (state / "recovery.json.tmp").mkdir()
        success = self.lua(server, "pcall(require('dsh_editor').checkpoint)")
        self.assertFalse(success)
        messages = self.lua(server, "local ok,err=pcall(vim.cmd,'DshCheckpoint'); return err or vim.fn.execute('messages')")
        self.assertIn('Editor recovery checkpoint failed', messages)
        (state / 'recovery.json.tmp').rmdir()

    def test_renamed_unsaved_buffer_recovers_under_its_new_destination(self):
        saved = self.project / 'before.md'
        saved.write_text('on disk\n')
        renamed = self.project / 'after.md'
        server = self.launch(self.project, 'before.md')
        self.lua(server, "vim.api.nvim_buf_set_lines(0,0,-1,false,{'renamed unsaved work'}); "
                 "vim.cmd('DshCheckpoint'); return true")
        tick = self.lua(server, 'vim.api.nvim_buf_get_changedtick(0)')
        self.lua(server, 'vim.api.nvim_buf_set_name(0,' + json.dumps(str(renamed)) + '); return true')
        self.assertEqual(self.lua(server, 'vim.api.nvim_buf_get_changedtick(0)'), tick)
        self.lua(server, "vim.cmd('DshCheckpoint'); return true")
        manifest = Path(server['state']) / 'recovery.json'
        index = json.loads(manifest.read_text())
        self.assertEqual(len(index['buffers']), 1)
        snapshot = json.loads((manifest.parent / index['buffers'][0]).read_text())
        self.assertEqual(snapshot['name'], str(renamed))
        os.kill(server['pid'], signal.SIGKILL)
        time.sleep(0.1)
        restarted = self.launch()
        recovered = self.lua(restarted, "(function() for _,b in ipairs(vim.api.nvim_list_bufs()) do "
                             "if vim.b[b].dsh_recovery_original ~= nil then return {"
                             "name=vim.b[b].dsh_recovery_original,lines=vim.api.nvim_buf_get_lines(b,0,-1,false)} end end end)()")
        self.assertEqual(recovered, {'name': str(renamed), 'lines': ['renamed unsaved work']})
        self.assertEqual(saved.read_text(), 'on disk\n')
        self.assertFalse(renamed.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
