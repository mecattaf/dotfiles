"""Call/playback-hold lifecycle checks with fake capture processes; no audio devices."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest


@unittest.skipUnless(os.environ.get('CALL_RECORD_TEST_SCRIPT'), 'invoked by test_call_record.sh with explicit recorder path')
class HoldLifecycle(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.state = self.root / 'state'
        self.runtime = self.root / 'runtime'
        self.bin = self.root / 'bin'
        for directory in (self.home, self.state, self.runtime, self.bin):
            directory.mkdir()
        self.hold = self.state / 'call-record/active'
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
state=pathlib.Path(os.environ['XDG_STATE_HOME']); output=pathlib.Path(sys.argv[-1])
assert (state/'call-record/active').exists()
if os.environ.get('FAIL_NEAR') and output.name=='near.wav':sys.exit(2)
def stopped(*args):sys.exit(0)
signal.signal(signal.SIGINT,signal.SIG_IGN if os.environ.get('IGNORE_INT') else stopped)
signal.signal(signal.SIGTERM,stopped)
output.write_bytes(b'fake finalized audio')
with open(os.environ['FAKE_EVENTS'],'a') as f:f.write(json.dumps({'event':'capture','pid':os.getpid(),'output':str(output)})+'\\n')
while True:time.sleep(.05)
''')
        self.write_fake('sox', '''import json,os,pathlib,sys
state=pathlib.Path(os.environ['XDG_STATE_HOME']);assert not (state/'call-record/active').exists();assert not (state/'call-record/current').exists()
pathlib.Path(sys.argv[4]).write_bytes(b'mixed')
with open(os.environ['FAKE_EVENTS'],'a') as f:f.write(json.dumps({'event':'mix'})+'\\n')
''')
        self.write_fake('soxi', "print('00:00:01')\n")
        self.write_fake('call-diarize-backfill', '''import json,os,pathlib
assert not (pathlib.Path(os.environ['XDG_STATE_HOME'])/'call-record/active').exists()
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

    def test_hold_spans_capture_and_releases_before_postprocessing(self):
        started = self.invoke('start', 'normal')
        self.assertEqual(started.returncode, 0, started.stderr)
        self.assertEqual(len(self.current.read_text().splitlines()), 5)
        self.assertEqual(len(self.records()), 2)
        self.assertEqual(self.hold.stat().st_mode & 0o777, 0o600)
        stopped = self.invoke('stop')
        self.assertEqual(stopped.returncode, 0, stopped.stderr)
        self.assertFalse(self.current.exists())
        self.assertFalse(self.hold.exists())
        self.assertEqual([x['event'] for x in self.records()][-2:], ['mix', 'enqueue'])

    def test_start_failure_releases_only_after_survivor_stops(self):
        result = self.invoke('start', 'failed', FAIL_NEAR='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.current.exists())
        self.assertFalse(self.hold.exists())
        self.assertEqual(len(self.records()), 1)

    def test_uncertain_failure_preserves_marker_and_recovery_refuses_live_capture(self):
        result = self.invoke('start', 'uncertain', FAIL_NEAR='1', IGNORE_INT='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.hold.exists())
        self.assertFalse(self.current.exists())
        self.assertNotEqual(self.invoke('recover').returncode, 0)
        for event in self.records():os.kill(event['pid'], signal.SIGTERM)
        time.sleep(.15)
        self.assertEqual(self.invoke('recover').returncode, 0)
        self.assertFalse(self.hold.exists())

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
