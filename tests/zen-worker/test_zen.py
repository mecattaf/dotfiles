#!/usr/bin/env python3
"""Offline contract checks. Run with runtime-test; no real provider calls."""
import concurrent.futures
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

ZEN = Path(__file__).resolve().parents[2] / 'home/dot_local/bin/zen'
FAKE = r'''#!/usr/bin/env python3
import json,os,subprocess,sys,time
from pathlib import Path
with open(os.environ['FAKE_CALLS'],'a') as out:
 out.write(json.dumps({'args':sys.argv[1:],'slot_key':os.environ['OPENCODE_API_KEY'],'config':json.loads(os.environ['OPENCODE_CONFIG_CONTENT']),'data':os.environ['XDG_DATA_HOME']})+'\n')
mode=os.environ.get('FAKE_MODE','ok')
if sys.argv[1]=='acp':
 for line in sys.stdin:
  request=json.loads(line)
  print(json.dumps({'jsonrpc':'2.0','id':request['id'],'result':{'protocolVersion':1}}),flush=True)
 sys.exit(0)
if sys.argv[1]=='models':
 if mode=='catalogue_timeout':time.sleep(30)
 for model,cost in [('deepseek-v4.1-flash-free',0),('big-pickle',0),('paid-model',1)]:
  print('opencode/'+model)
  print(json.dumps({'id':model,'providerID':'opencode','status':'active','cost':{'input':cost,'output':cost,'cache':{'read':0,'write':0}}}))
 sys.exit(0)
if mode in ('timeout','cancel','orphan'):
 child=subprocess.Popen([sys.executable,'-c','import signal,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);time.sleep(30)'])
 Path(os.environ['CHILD_PID']).write_text(str(child.pid))
 print(json.dumps({'type':'text','part':{'text':'partial '+os.environ['OPENCODE_API_KEY']}}),flush=True)
 if mode=='orphan':sys.exit(0)
 time.sleep(30)
if mode=='provider_error':
 print(json.dumps({'type':'error','error':{'name':'FreeUsageLimitError','data':{'message':'429 '+os.environ['OPENCODE_API_KEY']}}}))
 sys.exit(0)
print(json.dumps({'type':'text','sessionID':'ses_test','part':{'text':'A useful answer'}}))
if mode!='incomplete':print(json.dumps({'type':'step_finish','part':{'reason':'stop','cost':0,'tokens':{'input':12,'output':5,'reasoning':3,'cache':{'read':2,'write':0},'total':20}}}))
'''


class ZenTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='zen-worker-test-')
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        (self.bin / 'opencode').write_text(FAKE)
        (self.bin / 'opencode').chmod(0o700)
        self.keys = self.root / 'keys'
        self.keys.mkdir()
        for slot in (1, 2):
            (self.keys / f'opencode-zen-key-{slot}').write_text(f'fixture-secret-slot-{slot}')
        self.cwd = self.root / 'workspace'
        self.cwd.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin)+':'+os.environ['PATH'],
                        ZEN_KEY_DIR=str(self.keys), ZEN_STATE_DIR=str(self.root/'state'),
                        ZEN_LEDGER=str(self.root/'ledger.jsonl'), FAKE_CALLS=str(self.root/'calls'),
                        CHILD_PID=str(self.root/'child.pid'))

    def tearDown(self):
        self.temp.cleanup()

    def run_zen(self, *args, mode='ok'):
        return subprocess.run([str(ZEN), *args], cwd=self.cwd, env=dict(self.env, FAKE_MODE=mode),
                              stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=8)

    def results(self):
        return [json.loads(p.read_text()) for p in (self.root/'state/invocations').glob('*/result.json')]

    def assert_child_stopped(self):
        pid = int((self.root/'child.pid').read_text())
        path = Path('/proc') / str(pid) / 'stat'
        # Under runtime-test the dead descendant may await namespace init's reap.
        self.assertTrue(not path.exists() or path.read_text().split()[2] == 'Z')

    def test_usage_and_legacy_cli(self):
        process = self.run_zen('-k','2','-m','opencode/big-pickle','--','--pure','--format','json','Read source')
        self.assertEqual(process.returncode,0,process.stderr)
        result, = self.results()
        self.assertEqual(result['status'],'ok')
        self.assertEqual(result['usage_steps'][0]['total'],20)
        self.assertEqual(result['usage_steps'][0]['reasoning'],3)
        self.assertIsNone(result['accepted'])
        calls = [json.loads(s) for s in (self.root/'calls').read_text().splitlines()]
        self.assertEqual(len(calls),2)
        self.assertEqual(calls[1]['config']['permission']['edit'],'deny')
        self.assertEqual(calls[1]['config']['permission']['*'],'deny')
        self.assertEqual(calls[1]['config']['small_model'],'opencode/big-pickle')
        self.assertEqual(calls[1]['slot_key'],'fixture-secret-slot-2')
        self.assertNotEqual(calls[1]['data'],str(Path.home()/'.local/share'))

    def test_paid_and_absent_models_stop_before_generation(self):
        for model in ('paid-model','old-model-free'):
            process=self.run_zen('-m',model,'Read source')
            self.assertEqual(process.returncode,2,process.stderr)
        self.assertTrue(all(json.loads(s)['args'][0]=='models' for s in (self.root/'calls').read_text().splitlines()))

    def test_vendor_exit_zero_error_is_failure_without_rotation_and_redacted(self):
        process=self.run_zen('Read source',mode='provider_error')
        self.assertNotEqual(process.returncode,0)
        result, = self.results()
        self.assertEqual(result['status'],'429')
        self.assertNotIn('fixture-secret-slot-1',json.dumps(result)+process.stdout+process.stderr)
        self.assertEqual(len((self.root/'calls').read_text().splitlines()),2)
        self.assertEqual(len((self.root/'ledger.jsonl').read_text().splitlines()),1)

    def test_incomplete_success_has_nonzero_exit(self):
        self.assertEqual(self.run_zen('Read source',mode='incomplete').returncode,1)
        self.assertEqual(self.results()[0]['status'],'incomplete')

    def test_absolute_timeout_kills_descendants_and_preserves_partial(self):
        before=time.monotonic()
        process=self.run_zen('--timeout','0.4','Read source',mode='timeout')
        self.assertEqual(process.returncode,124,process.stderr)
        self.assertLess(time.monotonic()-before,2)
        self.assert_child_stopped()
        result, = self.results()
        self.assertEqual(result['text'],['partial [REDACTED]'])

    def test_exited_parent_cannot_escape_deadline_with_inherited_pipe(self):
        process=self.run_zen('--timeout','0.4','Read source',mode='orphan')
        self.assertEqual(process.returncode,124,process.stderr)
        self.assert_child_stopped()

    def test_catalogue_is_within_same_deadline(self):
        process=self.run_zen('--timeout','0.2','Read source',mode='catalogue_timeout')
        self.assertEqual(process.returncode,124,process.stderr)
        self.assertEqual(self.results()[0]['status'],'timeout')
        self.assertEqual(len((self.root/'calls').read_text().splitlines()),1)

    def test_cancellation_kills_only_invocation_group(self):
        process=subprocess.Popen([str(ZEN),'Read source'],cwd=self.cwd,
                                 env=dict(self.env,FAKE_MODE='cancel'),stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        deadline=time.monotonic()+3
        while not (self.root/'child.pid').exists() and time.monotonic()<deadline:time.sleep(.02)
        process.send_signal(signal.SIGTERM)
        _out,err=process.communicate(timeout=3)
        self.assertEqual(process.returncode,130,err)
        self.assert_child_stopped()
        self.assertEqual(self.results()[0]['status'],'cancelled')

    def test_concurrent_invocations_share_only_locked_ledger(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            processes=list(pool.map(lambda _:self.run_zen('--task-id','one-task','Read source'),range(4)))
        self.assertTrue(all(p.returncode==0 for p in processes))
        rows=[json.loads(s) for s in (self.root/'ledger.jsonl').read_text().splitlines()]
        self.assertEqual(len(rows),4)
        self.assertEqual(len({r['invocation_id'] for r in rows}),4)
        self.assertTrue(all(r['task_id']=='one-task' for r in rows))

    def test_edit_requires_explicit_workspace_and_stays_scoped(self):
        self.assertEqual(self.run_zen('--edit','Draft patch').returncode,2)
        process=self.run_zen('--cwd',str(self.cwd),'--edit','Draft patch')
        self.assertEqual(process.returncode,0,process.stderr)
        call=json.loads((self.root/'calls').read_text().splitlines()[-1])
        self.assertEqual(call['config']['permission']['edit'],{'*':'deny',str(self.cwd/'*').lstrip('/'):'allow'})

    def test_acp_passthrough_has_no_catalogue_noise_and_keeps_native_state(self):
        request=json.dumps({'jsonrpc':'2.0','id':1,'method':'initialize','params':{}})+'\n'
        for _ in range(2):
            process=subprocess.run([str(ZEN),'--acp'],cwd=self.cwd,env=self.env,
                                   input=request,capture_output=True,text=True,timeout=5)
            self.assertEqual(process.returncode,0,process.stderr)
            response=json.loads(process.stdout)
            self.assertEqual(response['id'],1)
        calls=[json.loads(s) for s in (self.root/'calls').read_text().splitlines()]
        acp=[row for row in calls if row['args'][0]=='acp']
        self.assertEqual(len(acp),2)
        self.assertEqual(acp[0]['data'],acp[1]['data'])
        self.assertNotIn('paid-model',acp[0]['config']['provider']['opencode']['whitelist'])
        self.assertTrue(all(row['status']=='closed' for row in self.results()))

    def test_no_automatic_burndown(self):
        self.assertEqual(self.run_zen('--burndown','Read source').returncode,2)
        self.assertFalse((self.root/'calls').exists())


if __name__=='__main__':unittest.main()
