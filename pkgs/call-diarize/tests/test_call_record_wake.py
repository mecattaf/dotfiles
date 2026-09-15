"""Call/wake lifecycle checks with fake capture processes; no audio devices."""
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest


@unittest.skipUnless(os.environ.get('CALL_RECORD_TEST_SCRIPT'), 'invoked by test_call_record.sh with explicit recorder path')
class WakeLifecycle(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.state = self.root / 'state'
        self.runtime = self.root / 'runtime'
        self.bin = self.root / 'bin'
        for directory in (self.home, self.state, self.runtime, self.bin):
            directory.mkdir()
        self.wake = self.state / 'speech-wake'
        self.current = self.state / 'call-record/current'
        self.events = self.root / 'events.jsonl'
        self.env = dict(os.environ, HOME=str(self.home), XDG_STATE_HOME=str(self.state),
                        XDG_RUNTIME_DIR=str(self.runtime), PATH=str(self.bin)+':'+os.environ['PATH'],
                        FAKE_EVENTS=str(self.events))
        self.script = os.environ['CALL_RECORD_TEST_SCRIPT']
        self.bash = os.environ['CALL_RECORD_TEST_BASH']
        self.write_fake('pw-dump', '''import json
print(json.dumps([{'info': {'props': {'media.class': c, 'node.name': 'INZONE-'+c}}} for c in ['Audio/Sink', 'Audio/Source']]))
''')
        self.write_fake('pw-record', '''import json,os,pathlib,signal,sys,time
state=pathlib.Path(os.environ['XDG_STATE_HOME']); wake=state/'speech-wake'; output=pathlib.Path(sys.argv[-1])
assert (wake/'call-record').exists() and (wake/'epoch').exists()
if os.environ.get('REQUIRE_ACK'):assert (wake/'ack').read_bytes()==(wake/'epoch').read_bytes()
if os.environ.get('FAIL_NEAR') and output.name=='near.wav':sys.exit(2)
def stopped(*args):sys.exit(0)
signal.signal(signal.SIGINT,signal.SIG_IGN if os.environ.get('IGNORE_INT') else stopped)
signal.signal(signal.SIGTERM,stopped)
output.write_bytes(b'fake finalized audio')
with open(os.environ['FAKE_EVENTS'],'a') as f:f.write(json.dumps({'event':'capture','pid':os.getpid(),'output':str(output),'epoch':(wake/'epoch').read_text()})+'\\n')
while True:time.sleep(.05)
''')
        self.write_fake('sox', '''import json,os,pathlib,sys
state=pathlib.Path(os.environ['XDG_STATE_HOME']);assert not (state/'speech-wake/call-record').exists();assert not (state/'call-record/current').exists()
pathlib.Path(sys.argv[4]).write_bytes(b'mixed')
with open(os.environ['FAKE_EVENTS'],'a') as f:f.write(json.dumps({'event':'mix'})+'\\n')
''')
        self.write_fake('soxi', "print('00:00:01')\n")
        self.write_fake('call-diarize-backfill', '''import json,os,pathlib
assert not (pathlib.Path(os.environ['XDG_STATE_HOME'])/'speech-wake/call-record').exists()
with open(os.environ['FAKE_EVENTS'],'a') as f:f.write(json.dumps({'event':'enqueue'})+'\\n')
''')

    def write_fake(self, name, body):
        path = self.bin / name
        path.write_text('#!'+sys.executable+'\n'+body)
        path.chmod(0o755)

    def invoke(self, *args, timeout=9, **extra):
        return subprocess.run([self.bash, self.script, *args], env=dict(self.env, **extra),
                              text=True, capture_output=True, timeout=timeout)

    def records(self):
        return [json.loads(x) for x in self.events.read_text().splitlines()] if self.events.exists() else []

    def tearDown(self):
        for event in self.records():
            if event['event'] == 'capture':
                try:os.kill(event['pid'], signal.SIGTERM)
                except ProcessLookupError:pass
        self.temp.cleanup()

    def test_entry_exit_epoch_and_release_before_postprocessing(self):
        started = self.invoke('start', 'normal')
        self.assertEqual(started.returncode, 0, started.stderr)
        epoch = (self.wake/'epoch').read_bytes()
        self.assertEqual(len(self.current.read_text().splitlines()), 5)
        self.assertEqual(len(self.records()), 2)
        self.assertTrue(all(x['epoch'].encode() == epoch for x in self.records()))
        self.assertEqual((self.wake/'call-record').stat().st_mode & 0o777, 0o600)
        stopped = self.invoke('stop')
        self.assertEqual(stopped.returncode, 0, stopped.stderr)
        self.assertFalse(self.current.exists())
        self.assertFalse((self.wake/'call-record').exists())
        self.assertNotEqual(epoch, (self.wake/'epoch').read_bytes())
        self.assertEqual([x['event'] for x in self.records()][-2:], ['mix', 'enqueue'])

    def test_start_failure_releases_only_after_survivor_stops(self):
        result = self.invoke('start', 'failed', FAIL_NEAR='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.current.exists())
        self.assertFalse((self.wake/'call-record').exists())
        self.assertEqual(len(self.records()), 1)

    def test_uncertain_failure_preserves_marker_and_recovery_refuses_live_capture(self):
        result = self.invoke('start', 'uncertain', FAIL_NEAR='1', IGNORE_INT='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.wake/'call-record').exists())
        self.assertFalse(self.current.exists())
        self.assertNotEqual(self.invoke('recover').returncode, 0)
        for event in self.records():os.kill(event['pid'], signal.SIGTERM)
        time.sleep(.15)
        self.assertEqual(self.invoke('recover').returncode, 0)
        self.assertFalse((self.wake/'call-record').exists())

    def listener_lock(self):
        path = self.runtime/'speech-wake/lock'
        path.parent.mkdir()
        handle = path.open('w')
        fcntl.flock(handle, fcntl.LOCK_EX)
        return handle

    def test_live_listener_ack_before_capture(self):
        with self.listener_lock():
            errors = []
            def acknowledge():
                try:
                    deadline = time.monotonic()+3
                    while not (self.wake/'epoch').exists():
                        if time.monotonic()>deadline:raise TimeoutError('No epoch')
                        time.sleep(.01)
                    time.sleep(.1)
                    self.assertFalse(self.events.exists())
                    (self.wake/'ack').write_bytes((self.wake/'epoch').read_bytes())
                except BaseException as error:errors.append(error)
            thread = threading.Thread(target=acknowledge)
            thread.start()
            result = self.invoke('start', 'acknowledged', REQUIRE_ACK='1')
            thread.join()
            self.assertFalse(errors, errors)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.invoke('stop').returncode, 0)

    def test_missing_ack_fails_closed_without_capture(self):
        with self.listener_lock():
            result = self.invoke('start', 'no-ack')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('did not acknowledge', result.stderr)
            self.assertEqual(self.records(), [])
            self.assertTrue((self.wake/'call-record').exists())
            self.assertFalse(self.current.exists())
        self.assertEqual(self.invoke('recover').returncode, 0)

    def test_concurrent_starts_are_serialized_and_capture_does_not_hold_lock(self):
        first = subprocess.Popen([self.bash,self.script,'start','first'],env=self.env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        second = subprocess.Popen([self.bash,self.script,'start','second'],env=self.env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        first.communicate(timeout=4)
        second.communicate(timeout=4)
        self.assertEqual(sorted([first.returncode,second.returncode]), [0,1])
        self.assertEqual(len(self.records()), 2)
        self.assertEqual(self.invoke('stop', timeout=4).returncode, 0)


if __name__ == '__main__':
    unittest.main()
