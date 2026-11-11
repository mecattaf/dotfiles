#!/usr/bin/env python3
"""Exercise dsh-turn against fake dshd scripts written by the test itself.

The fakes speak JSON-RPC (one object per line) exactly like `dshd attach`
relays to `dsh acp`, or record argv like `dshd run/wait/read/rm`. The
real dshd is never called: DSH_TURN_DSHD points at the fake and
XDG_STATE_HOME points into a temporary directory.

    python3 -m unittest discover -s tests/dsh-turn -v
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
TURN = ROOT / 'home/dot_local/bin/dsh-turn'

# A fake `dshd attach NAME`: answers initialize, session/new,
# session/resume and set_config_option; on session/prompt it streams a
# few agent_message_chunk updates (and optionally one permission
# request), then answers with stopReason end_turn. Unknown requests get
# an ACP error so the exit-1 path is reachable.
ACP_FAKE = r'''
import json, os, sys

LOG = os.environ.get('FAKE_LOG')

def record(message):
    if LOG:
        with open(LOG, 'a') as f:
            f.write(json.dumps(message) + '\n')

def send(message):
    message['jsonrpc'] = '2.0'
    sys.stdout.write(json.dumps(message) + '\n')
    sys.stdout.flush()

def chunks():
    for text in ('OK', ' done'):
        send({'method': 'session/update', 'params': {
            'sessionId': 'ses_fake', 'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': text}}})

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    frame = json.loads(line)
    record(frame)
    method = frame.get('method')
    ident = frame.get('id')
    if method is None and ident is not None:
        # A response from dsh-turn (e.g. our permission answer).
        ans = os.environ.get('FAKE_ANSWERS')
        if ans:
            with open(ans, 'a') as f:
                f.write(json.dumps(frame) + '\n')
    if method == 'initialize':
        send({'id': ident, 'result': {'protocolVersion': 1}})
    elif method == 'session/new':
        send({'id': ident, 'result': {'sessionId': 'ses_fake'}})
    elif method in ('session/resume', 'session/set_config_option'):
        send({'id': ident, 'result': {}})
    elif method == 'session/prompt':
        if __import__('os').environ.get('FAKE_PERMISSION') == '1':
            send({'id': 77, 'method': 'session/request_permission', 'params': {
                'sessionId': 'ses_fake',
                'options': [{'optionId': 'allow_once', 'kind': 'allow_once'},
                            {'optionId': 'reject_once', 'kind': 'reject_once'}]}})
            answer = json.loads(sys.stdin.readline())
            ans = os.environ.get('FAKE_ANSWERS')
            if ans:
                with open(ans, 'a') as f:
                    f.write(json.dumps(answer) + '\n')
        chunks()
        send({'id': ident, 'result': {'stopReason': 'end_turn'}})
    elif ident is not None:
        send({'id': ident, 'error': {'code': -32601, 'message': 'unhandled: ' + str(method)}})
'''

# A fake headless lane: `run` records argv and prints the instance name,
# `wait` and `rm` succeed, `read --json` answers with one NDJSON record.
HEADLESS_FAKE = r'''
import json, os, sys, time

argv = sys.argv[1:]
log = os.environ['FAKE_LOG']
with open(log, 'a') as f:
    f.write(json.dumps(argv) + '\n')
if argv[0] == 'run':
    print(json.dumps({'name': argv[argv.index('--name') + 1]}))
elif argv[0] == 'read':
    # The real shape (dshd 0.1.0): one object, the run's journal in `lines`.
    events = [{'type': 'session', 'sessionId': 'session-h1', 'cwd': '/home/x'},
              {'type': 'text', 'text': 'headless '}, {'type': 'text', 'text': 'answer'},
              {'type': 'final', 'sessionId': 'session-h1', 'reason': {'kind': 'completed'}, 'text': 'headless answer'}]
    print(json.dumps({'name': argv[-1], 'invocationId': 'inv1', 'complete': True, 'streams': ['stdout'],
                      'lines': ['dshd-run: run started'] + [json.dumps(e) for e in events] + ['dshd-run: run ended: success']}))
sys.exit(0)
'''

# A fake that refuses the attach right away, like an occupied instance.
REFUSING_FAKE = r'''
import sys
sys.stderr.write('instance busy: another controller is attached\n')
sys.exit(3)
'''


class DshTurn(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.log = self.root / 'calls.jsonl'
        self.env = dict(os.environ,
                        DSH_TURN_DSHD=str(self.make_fake('dshd-acp', ACP_FAKE)),
                        XDG_STATE_HOME=str(self.root / 'state'),
                        FAKE_LOG=str(self.log),
                        FAKE_ANSWERS=str(self.root / 'answers.jsonl'))
        self.state = self.root / 'state' / 'dsh-turn'

    def make_fake(self, name, source):
        path = self.root / name
        path.write_text('#!' + sys.executable + '\n' + source)
        path.chmod(0o755)
        return path

    def turn(self, *argv, env=None):
        return subprocess.run([sys.executable, str(TURN), *argv],
                              env=dict(self.env, **(env or {})),
                              text=True, capture_output=True, timeout=30)

    def calls(self):
        rows = []
        if self.log.exists():
            for line in self.log.read_text().splitlines():
                if line.strip():
                    row = json.loads(line)
                    # ACP frames are recorded as [method, params]; headless
                    # dshd invocations as their argv list.
                    if isinstance(row, dict):
                        rows.append([row.get('method'), row.get('params')])
                    else:
                        rows.append(row)
        return rows

    def answers(self):
        # Frames our controller sent (responses to the fake's requests).
        path = self.root / 'answers.jsonl'
        rows = []
        if path.exists():
            for line in path.read_text().splitlines():
                if line.strip():
                    rows.append(json.loads(line))
        return rows

    def test_turn_streams_chunks_summary_and_state(self):
        result = self.turn('Reply ok')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'OK done\n')
        self.assertIn('dsh-turn: session=ses_fake stop=end_turn', result.stderr)
        self.assertEqual((self.state / 'cc-acp.last').read_text().strip(), 'ses_fake')

    def test_json_mode_prints_ndjson(self):
        result = self.turn('--json', 'Reply ok')
        self.assertEqual(result.returncode, 0, result.stderr)
        events = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
        self.assertEqual(events[-1], {'event': 'done', 'session': 'ses_fake', 'stop': 'end_turn'})
        self.assertNotIn('dsh-turn:', result.stdout)
        self.assertIn('dsh-turn: session=ses_fake stop=end_turn', result.stderr)

    def test_permission_without_approve_is_rejected_and_turn_ends(self):
        result = self.turn('Reply ok', env={'FAKE_PERMISSION': '1'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'OK done\n')
        answered = self.answers()
        self.assertEqual(len(answered), 1)
        self.assertEqual(answered[0]['result']['outcome'],
                         {'outcome': 'selected', 'optionId': 'reject_once'})

    def test_approve_picks_allow_once(self):
        result = self.turn('--approve', 'Reply ok', env={'FAKE_PERMISSION': '1'})
        self.assertEqual(result.returncode, 0, result.stderr)
        answered = self.answers()
        self.assertEqual(len(answered), 1)
        self.assertEqual(answered[0]['result']['outcome'],
                         {'outcome': 'selected', 'optionId': 'allow_once'})

    def test_session_last_resumes_saved_id(self):
        self.state.mkdir(parents=True)
        (self.state / 'cc-acp.last').write_text('ses_saved\n')
        result = self.turn('--session', 'last', 'Continue')
        self.assertEqual(result.returncode, 0, result.stderr)
        methods = [row[0] for row in self.calls()]
        self.assertIn('session/resume', methods)
        resumed = next(row for row in self.calls() if row[0] == 'session/resume')
        self.assertEqual(resumed[1]['sessionId'], 'ses_saved')
        self.assertNotIn('session/new', methods)

    def test_acp_error_exits_1(self):
        broken = ACP_FAKE.replace("elif method == 'session/prompt':",
                                  "elif False:\n        pass\n    elif method == 'session/prompt':")
        # Force the prompt response to be an error frame.
        broken = broken.replace("send({'id': ident, 'result': {'stopReason': 'end_turn'}})",
                                "send({'id': ident, 'error': {'code': -32000,"
                                " 'message': 'boom'}})")
        env = {'DSH_TURN_DSHD': str(self.make_fake('dshd-error', broken))}
        result = self.turn('Reply ok', env=env)
        self.assertEqual(result.returncode, 1)
        self.assertIn('session/prompt failed', result.stderr)

    def test_attach_refused_exits_3(self):
        env = {'DSH_TURN_DSHD': str(self.make_fake('dshd-refuse', REFUSING_FAKE))}
        result = self.turn('Reply ok', env=env)
        self.assertEqual(result.returncode, 3)
        self.assertIn('another controller', result.stderr)

    def test_missing_prompt_exits_2(self):
        result = self.turn()
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.calls(), [])

    # -- via headless ----------------------------------------------------

    def headless(self, *argv, env=None):
        env = dict(env or {})
        env['DSH_TURN_DSHD'] = str(self.make_fake('dshd-headless', HEADLESS_FAKE))
        return self.turn(*argv, env=env)

    def test_headless_runs_waits_reads_and_removes(self):
        result = self.headless('--via', 'headless', 'Hi there')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('headless answer', result.stdout)
        rows = self.calls()
        self.assertEqual(len(rows), 4)
        run = rows[0]
        self.assertEqual(run[:3], ['run', '--bg', '--json'])
        name = run[run.index('--name') + 1]
        self.assertRegex(name, r'^cct-\d+$')
        self.assertEqual(run[run.index('--name') + 2:],
                         ['--', 'headless', '--json', 'Hi there'])
        self.assertEqual(rows[1], ['wait', name])
        self.assertEqual(rows[2][:2], ['read', '--json'])
        self.assertEqual(rows[2][2:], [name])
        self.assertEqual(rows[3], ['rm', name])
        # The Session id from the final event, not the throwaway run name.
        self.assertIn('dsh-turn: session=session-h1', result.stderr)

    def test_headless_session_id_is_passed_through(self):
        result = self.headless('--via', 'headless', '--session', 'ses_old', 'Hi')
        self.assertEqual(result.returncode, 0, result.stderr)
        run = self.calls()[0]
        self.assertEqual(run[run.index('--session-id') + 1], 'ses_old')
        tail = run[run.index('--session-id') + 2:]
        self.assertEqual(tail[-1], 'Hi')


if __name__ == '__main__':
    unittest.main()
