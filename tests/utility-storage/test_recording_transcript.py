"""Completion publication is local, immutable, explicit and retryable."""
import json
from concurrent.futures import ThreadPoolExecutor
import os
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import recording_transcript_fixture as publisher


class TranscriptPublicationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / 'call with spaces'
        self.source.mkdir()
        (self.source / 'asr-raw').mkdir()
        (self.source / 'transcript.md').write_text('# Finished call\n\nTom: hello.\n')
        (self.source / 'review-queue.md').write_text('# Review\n\nNone.\n')
        (self.source / 'asr-raw/manifest.json').write_text(json.dumps({
            'schema': 1, 'all_inference_gpu_backed': True,
            'asr_model': 'VibeVoice-ASR-Streaming-7B',
            'cleanup_models': ['qwen3.8-flash-next'],
        }))
        self.output = self.root / 'private output'

    def test_finished_snapshot_is_private_and_idempotent(self):
        with patch.dict(os.environ, {'RECORDINGS_ROOT': str(self.output)}):
            first = publisher.publish(self.source)
            receipt = (first / 'receipt.json').read_bytes()
            second = publisher.publish(self.source)
        self.assertEqual(first, second)
        self.assertEqual((second / 'receipt.json').read_bytes(), receipt)
        self.assertEqual(first.parent, self.output / 'transcripts')
        self.assertEqual(first.stat().st_mode & 0o777, 0o700)
        self.assertEqual((first / 'transcript.md').stat().st_mode & 0o777, 0o600)
        self.assertEqual((first / 'transcript.md').read_bytes(),
                         (self.source / 'transcript.md').read_bytes())
        self.assertTrue(json.loads(receipt)['review_required'])
        self.assertFalse(list(first.parent.glob('.pending-*')))

    def test_new_revision_preserves_previous_snapshot(self):
        first = publisher.publish(self.source, self.output)
        (self.source / 'transcript.md').write_text('# Revised completed transcript\n')
        second = publisher.publish(self.source, self.output)
        self.assertNotEqual(first, second)
        self.assertIn('Tom: hello.', (first / 'transcript.md').read_text())

    def test_concurrent_duplicate_events_converge_without_partial_directories(self):
        with ThreadPoolExecutor(max_workers=2) as workers:
            targets = list(workers.map(lambda _: publisher.publish(self.source, self.output), range(2)))
        self.assertEqual(targets[0], targets[1])
        self.assertEqual(list((self.output / 'transcripts').iterdir()), [targets[0]])

    def test_missing_or_unfinished_outputs_never_publish(self):
        for name in publisher.FILES:
            with self.subTest(name=name):
                path = self.source / name
                original = path.read_bytes()
                path.unlink()
                with self.assertRaises(OSError):
                    publisher.publish(self.source, self.output)
                path.write_bytes(original)
        manifest = self.source / 'asr-raw/manifest.json'
        manifest.write_text('{"schema":1,"all_inference_gpu_backed":false}')
        with self.assertRaises(ValueError):
            publisher.publish(self.source, self.output)
        self.assertFalse(self.output.exists())

    def test_symlink_source_and_corrupted_existing_copy_are_refused(self):
        path = self.source / 'transcript.md'
        original = path.read_text()
        path.unlink()
        other = self.root / 'outside.md'
        other.write_text(original)
        path.symlink_to(other)
        with self.assertRaises(OSError):
            publisher.publish(self.source, self.output)
        path.unlink()
        path.write_text(original)
        target = publisher.publish(self.source, self.output)
        (target / 'transcript.md').write_text('corrupted')
        with self.assertRaises(ValueError):
            publisher.publish(self.source, self.output)
        self.assertEqual((target / 'transcript.md').read_text(), 'corrupted')

    def test_changing_source_during_staging_never_publishes(self):
        real = publisher.read_regular
        reads = 0
        def changing(path):
            nonlocal reads
            reads += 1
            if reads == 4:
                (self.source / 'transcript.md').write_text('changed after initial read')
            return real(path)
        with patch.object(publisher, 'read_regular', changing), self.assertRaises(ValueError):
            publisher.publish(self.source, self.output)
        self.assertFalse(list((self.output / 'transcripts').iterdir()))

    @unittest.skipUnless(os.environ.get('RECORDING_STAGE_BIN'), 'built package CLI not supplied')
    def test_packaged_cli_resolves_local_storage_and_reuses_exact_receipt(self):
        command = [os.environ['RECORDING_STAGE_BIN'], str(self.source)]
        env = {**os.environ, 'RECORDINGS_ROOT': str(self.output)}
        first = subprocess.run(command, env=env, capture_output=True, text=True, check=True)
        target = Path(first.stdout.strip())
        self.assertEqual(target.parent, self.output / 'transcripts')
        before = (target / 'receipt.json').read_bytes()
        second = subprocess.run(command, env=env, capture_output=True, text=True, check=True)
        self.assertEqual(second.stdout, first.stdout)
        self.assertEqual((target / 'receipt.json').read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
