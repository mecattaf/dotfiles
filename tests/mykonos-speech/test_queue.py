import datetime, importlib.util, json, tempfile, unittest
from pathlib import Path
from unittest.mock import patch
p=Path(__file__).parents[2]/'pkgs/mykonos-speech/queue.py'
spec=importlib.util.spec_from_file_location('queue_impl',p);q=importlib.util.module_from_spec(spec);spec.loader.exec_module(q)
class QueueTests(unittest.TestCase):
    def test_print_hours(self):
        for hour in range(24):self.assertEqual(q.quiet(datetime.datetime(2026,9,14,hour)),hour<6)
    def test_quiet_preserves_intake(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'intake').mkdir();(root/'intake/test.md').write_text('Hello')
            with patch.object(q,'quiet',return_value=True),patch.object(q.subprocess,'run') as run:q.sweep(root,'qwen','play')
            self.assertTrue((root/'intake/test.md').exists());run.assert_not_called()
    def test_uncertain_playback_not_replayed(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'work/turn').mkdir(parents=True)
            (root/'work/turn/source.md').write_text('hello')
            with patch.object(q,'quiet',return_value=False),patch.object(q.subprocess,'run') as run:q.sweep(root,'qwen','play')
            self.assertTrue((root/'failed/turn/failure.json').exists());run.assert_not_called()
    def test_call_defers_completed_wav(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);job=root/'outbox/turn';job.mkdir(parents=True)
            (job/'source.md').write_text('hello');(job/'spoken.txt').write_text('hello');(job/'speech.wav').write_bytes(b'test')
            with patch.object(q,'quiet',return_value=False),patch.object(q.subprocess,'run',return_value=type('P',(),{'returncode':75})()):q.sweep(root,'qwen','play')
            self.assertTrue((job/'speech.wav').exists());self.assertFalse((root/'spoken/turn').exists())
if __name__=='__main__':unittest.main()
