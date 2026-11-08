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
from unittest.mock import patch

import json
import recording_transcript_fixture as recording_transcript


source = os.environ.get('CALL_DIARIZE_REMOTE_SCRIPT',
                        str(Path(__file__).parents[2] / 'home/dot_local/bin/call-diarize-remote'))
module = types.ModuleType('call_diarize_remote')
module.__file__ = source
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
        create, upload, worker, download, publish, cleanup = self.commands
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
        self.assertEqual(publish, [module.sys.executable,
                                  str(Path(source).with_name('recording-transcript-stage')),
                                  str(self.source)])
        self.assertEqual(cleanup[-4:], ['rm', '-rf', '--', remote])
        self.assertEqual((self.source / 'mix.wav').read_bytes(), b'original recording')

    def test_failed_processing_or_return_keeps_compute_scratch_and_source(self):
        for failed_step in (2, 3, 4, 5):
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
                if failed_step < 5:
                    self.assertFalse(any(command[-2].endswith('/recording-transcript-stage')
                                         for command in self.commands))
                self.assertEqual((self.source / 'mix.wav').read_bytes(), b'original recording')

    def test_returned_completion_reaches_real_local_publisher_before_scratch_cleanup(self):
        output = self.source.parent / 'private transcripts'

        def dispatch_fixture(command, *, check):
            self.fake_run(command, check=check)
            if command[0] == 'rsync' and command[-1] == str(self.source) + '/':
                (self.source / 'asr-raw').mkdir()
                (self.source / 'transcript.md').write_text('# Finished fixture\n')
                (self.source / 'review-queue.md').write_text('# Review fixture\n')
                (self.source / 'asr-raw/manifest.json').write_text(json.dumps({
                    'schema': 1, 'all_inference_gpu_backed': True,
                    'asr_model': 'fixture ASR',
                }))
            if command[-2].endswith('/recording-transcript-stage'):
                recording_transcript.publish(Path(command[-1]))
                self.assertFalse(any('rm' in item for item in self.commands))

        with patch.dict(os.environ, {'RECORDINGS_ROOT': str(output)}):
            module.dispatch(self.source, [], dispatch_fixture)
        snapshots = list((output / 'transcripts').iterdir())
        self.assertEqual(len(snapshots), 1)
        self.assertEqual((snapshots[0] / 'transcript.md').read_text(), '# Finished fixture\n')
        self.assertTrue(json.loads((snapshots[0] / 'receipt.json').read_text())['review_required'])
        self.assertEqual(self.commands[-1][-4:], ['rm', '-rf', '--', self.commands[0][-1]])

    def test_successful_worker_exit_without_finished_artifacts_does_not_publish(self):
        output = self.source.parent / 'private transcripts'

        def missing_outputs(command, *, check):
            self.fake_run(command, check=check)
            if command[-2].endswith('/recording-transcript-stage'):
                recording_transcript.publish(Path(command[-1]))

        stderr = io.StringIO()
        with patch.dict(os.environ, {'RECORDINGS_ROOT': str(output)}):
            with contextlib.redirect_stderr(stderr), self.assertRaises(OSError):
                module.dispatch(self.source, [], missing_outputs)
        self.assertIn('Compute scratch retained', stderr.getvalue())
        self.assertFalse(output.exists())
        self.assertFalse(any('rm' in item for item in self.commands))
