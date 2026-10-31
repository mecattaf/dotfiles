"""Storage-owner dispatch keeps source audio and retains failed compute work."""
import contextlib
import importlib.machinery
import io
import os
from pathlib import Path
import subprocess
import tempfile
import types
import unittest


source = os.environ.get('CALL_DIARIZE_REMOTE_SCRIPT',
                        str(Path(__file__).parents[2] / 'home/dot_local/bin/call-diarize-remote'))
module = types.ModuleType('call_diarize_remote')
importlib.machinery.SourceFileLoader(module.__name__, source).exec_module(module)


class RecordingDispatchTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.source = Path(temporary.name) / 'recording with spaces'
        self.source.mkdir()
        (self.source / 'mix.wav').write_bytes(b'original recording')
        self.commands = []

    def fake_run(self, command, *, check):
        self.assertTrue(check)
        self.commands.append(command)

    def test_results_return_before_scratch_removal_and_source_audio_is_excluded(self):
        module.dispatch(self.source, ['--hotwords', 'two words'], self.fake_run)
        create, upload, worker, download, cleanup = self.commands
        remote = create[-1]
        self.assertEqual(create[-4:-1], ['mkdir', '-m', '700'])
        self.assertEqual(worker, ['fleet-exec', 'strix-coordinator', '--cwd', remote,
                                  '--', 'call-diarize', remote, '--hotwords', 'two words'])
        self.assertEqual(upload[-2:], [str(self.source) + '/', 'strix-coordinator:' + remote + '/'])
        self.assertEqual(download[-1], str(self.source) + '/')
        for audio in ('mix.wav', 'far.wav', 'near.wav'):
            self.assertIn(audio, download)
        self.assertIn('--checksum', upload)
        self.assertIn('--checksum', download)
        self.assertEqual(cleanup[-4:], ['rm', '-rf', '--', remote])
        self.assertEqual((self.source / 'mix.wav').read_bytes(), b'original recording')

    def test_failed_processing_or_return_keeps_compute_scratch_and_source(self):
        for failed_step in (2, 3, 4):
            with self.subTest(step=failed_step):
                self.commands.clear()

                def failure(command, *, check):
                    self.fake_run(command, check=check)
                    if len(self.commands) == failed_step:
                        raise subprocess.CalledProcessError(23, command)

                stderr = io.StringIO()
                with contextlib.redirect_stderr(stderr), self.assertRaises(subprocess.CalledProcessError):
                    module.dispatch(self.source, [], failure)
                self.assertIn('Compute scratch retained at strix-coordinator:/tmp/', stderr.getvalue())
                self.assertFalse(any('rm' in command for command in self.commands))
                self.assertEqual((self.source / 'mix.wav').read_bytes(), b'original recording')
