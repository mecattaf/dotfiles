import importlib.util
import io
from pathlib import Path
import tempfile
import sys
import time
import types
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('wake', Path(__file__).parents[2] / 'pkgs/speech-wake/wake.py')
wake = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wake)


class Process:
    def __init__(self):
        self.returncode = None
        self.stdout = types.SimpleNamespace(fileno=lambda: 3, close=lambda: None)
        self.stdin = None
    def poll(self): return self.returncode
    def terminate(self): self.returncode = -15
    def kill(self): self.returncode = -9
    def wait(self, timeout=None): return self.returncode


class Tests(unittest.TestCase):
    def test_lock_observers_do_not_look_like_active_playback(self):
        import fcntl
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            observer = wake.Inhibitors(root / 'state')
            observer.runtime = root
            lockpath = root / 'qwen-speech/playback.lock'
            lockpath.parent.mkdir()
            with lockpath.open('a') as other_observer:
                fcntl.flock(other_observer, fcntl.LOCK_SH)
                self.assertNotIn('qwen-playback', observer.snapshot()[0])
                fcntl.flock(other_observer, fcntl.LOCK_EX)
                self.assertIn('qwen-playback', observer.snapshot()[0])
            self.assertNotIn('qwen-playback', observer.snapshot()[0])

    def test_relay_sends_before_endpoint_and_finishes(self):
        with tempfile.TemporaryDirectory() as temp:
            marker = Path(temp) / 'received'
            program = ('import sys,pathlib; data=sys.stdin.buffer.read(2560); '
                       'pathlib.Path(sys.argv[1]).write_bytes(data); '
                       'rest=sys.stdin.buffer.read(); print(len(data)+len(rest))')
            relay = wake.StreamingRelay([sys.executable, '-c', program, str(marker)])
            relay.feed(b'a' * 2560)
            deadline = time.monotonic() + 2
            while not marker.exists() and time.monotonic() < deadline:
                time.sleep(.01)
            self.assertTrue(marker.exists(), 'audio must arrive before endpoint')
            relay.feed(b'b' * 2560)
            self.assertEqual(relay.finish(lambda: False), '5120')

    def test_relay_cancellation_closes_process(self):
        relay = wake.StreamingRelay([sys.executable, '-c', 'import time; time.sleep(10)'])
        relay.feed(b'a' * 2560)
        self.assertIsNone(relay.finish(lambda: True))
        self.assertIsNotNone(relay.process.poll())
        self.assertFalse(relay.pending)

    def test_relay_refuses_unbounded_backlog(self):
        relay = wake.StreamingRelay([sys.executable, '-c', 'import time; time.sleep(10)'])
        try:
            with self.assertRaisesRegex(RuntimeError, 'cannot keep up'):
                relay.feed(b'a' * 64001)
        finally:
            relay.cancel()

    def test_no_default_or_duplicate_microphone(self):
        def node(name, serial):
            return {'info': {'props': {'media.class': 'Audio/Source', 'node.name': name, 'object.serial': serial}}}
        self.assertIsNone(wake.microphone([node('internal-default', 1)]))
        self.assertEqual(wake.microphone([node('internal-default', 1), node(wake.MIC, 2)]), '2')
        self.assertIsNone(wake.microphone([node(wake.MIC, 2), node(wake.MIC, 3)]))

    def test_pinned_capture_forbids_fallback_and_movement(self):
        with patch.object(wake.subprocess, 'Popen') as popen:
            wake.capture('1234')
        argv = popen.call_args.args[0]
        self.assertEqual(argv[argv.index('--target')+1], '1234')
        props = wake.json.loads(argv[argv.index('--properties')+1])
        for prop in ['node.dont-fallback', 'node.dont-reconnect', 'node.dont-move']:
            self.assertTrue(props[prop])

    def test_call_exit_changes_epoch_manual_mode_survives(self):
        with tempfile.TemporaryDirectory() as temp:
            state = Path(temp)
            gates = wake.Inhibitors(state)
            gates.manual(True)
            (gates.wake / 'call-record').touch()
            first = gates.snapshot()
            (gates.wake / 'epoch').write_text('call-ended')
            (gates.wake / 'call-record').unlink()
            after = gates.snapshot()
            self.assertIn('manual-call', after[0])
            self.assertNotEqual(first, after)
            gates.acknowledge(after[1])
            self.assertEqual((gates.wake / 'ack').read_bytes(), b'call-ended')
            gates.manual(False)
            self.assertNotIn('manual-call', gates.snapshot()[0])

    def test_legacy_call_and_qwen_playback_inhibit(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(wake.os.environ, {'XDG_RUNTIME_DIR': temp}):
            base = Path(temp); gates = wake.Inhibitors(base)
            (base / 'call-record').mkdir(); (base / 'call-record/current').touch()
            (base / 'qwen-speech').mkdir()
            with (base / 'qwen-speech/playback.lock').open('a') as lock:
                wake.fcntl.flock(lock, wake.fcntl.LOCK_EX)
                self.assertIn('legacy-call-record', gates.snapshot()[0])
                self.assertIn('qwen-playback', gates.snapshot()[0])
            self.assertNotIn('qwen-playback', gates.snapshot()[0])

    def test_call_entry_kills_cue_capture_then_acknowledges(self):
        recorder, cue = Process(), Process()
        blocked = False
        acked = False
        order = []
        def snapshot():
            if acked: raise KeyboardInterrupt
            return (('call-record',), b'new') if blocked else ((), b'old')
        def popen(*args, **kwargs):
            nonlocal blocked
            self.assertEqual(args[0], ['speech-listening-cue'])
            blocked = True
            return cue
        def ack(epoch):
            nonlocal acked
            self.assertEqual(epoch, b'new')
            self.assertIsNotNone(recorder.returncode)
            self.assertIsNotNone(cue.returncode)
            acked = True
        detector = types.SimpleNamespace(feed=lambda pcm: True, reset=lambda: order.append('reset'), frames=25)
        gates = types.SimpleNamespace(snapshot=snapshot, acknowledge=ack)
        with patch.object(wake, 'find_microphone', return_value='42'), patch.object(wake, 'capture', return_value=recorder), patch.object(wake.subprocess, 'Popen', side_effect=popen), patch.object(wake.select, 'select', return_value=([True], [], [])), patch.object(wake.os, 'read', return_value=b'\0'*2560), patch.object(wake.time, 'sleep'), patch.object(wake, 'emit'), patch.dict('sys.modules', {'webrtcvad': types.SimpleNamespace()}):
            with self.assertRaises(KeyboardInterrupt):
                wake.live(types.SimpleNamespace(once=True), detector, gates)
        self.assertTrue(acked)
        self.assertGreaterEqual(len(order), 3)

    def test_call_racing_with_positive_score_cannot_play_cue(self):
        recorder = Process(); blocked = False; acked = False
        def snapshot():
            if acked: raise KeyboardInterrupt
            return (('call-record',), b'new') if blocked else ((), b'old')
        def feed(pcm):
            nonlocal blocked
            blocked = True
            return True
        def ack(epoch):
            nonlocal acked
            acked = True
        detector = types.SimpleNamespace(feed=feed, reset=lambda: None, frames=25)
        with patch.object(wake, 'find_microphone', return_value='42'), patch.object(wake, 'capture', return_value=recorder), patch.object(wake.subprocess, 'Popen') as popen, patch.object(wake.select, 'select', return_value=([True], [], [])), patch.object(wake.os, 'read', return_value=b'\0'*2560), patch.object(wake.time, 'sleep'), patch.object(wake, 'emit'), patch.dict('sys.modules', {'webrtcvad': types.SimpleNamespace()}):
            with self.assertRaises(KeyboardInterrupt):
                wake.live(types.SimpleNamespace(once=True), detector, types.SimpleNamespace(snapshot=snapshot, acknowledge=ack))
        popen.assert_not_called()

    def test_endpoint_is_bounded_and_requires_speech(self):
        silent = types.SimpleNamespace(is_speech=lambda *args: False)
        command = wake.Command(silent)
        results = [command.feed(b'\0'*2560) for _ in range(100)]
        self.assertEqual(results[-1], 'empty')
        voiced = types.SimpleNamespace(is_speech=lambda *args: True)
        command = wake.Command(voiced)
        command.feed(b'\0'*2560); command.feed(b'\0'*2560)
        command.vad = silent
        results = [command.feed(b'\0'*2560) for _ in range(10)]
        self.assertEqual(results[-1], 'complete')
        command = wake.Command(voiced)
        results = [command.feed(b'\0'*2560) for _ in range(375)]
        self.assertEqual(results[-1], 'limit')


if __name__ == '__main__': unittest.main()
