"""Run the real wrappers and CLI ACP without credentials or inference."""
import json
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading

bin_dir = Path(os.environ['AGY_ACCOUNTS_BIN'])
with tempfile.TemporaryDirectory(prefix='antigravity-native-') as temp:
    fixture = Path(temp)
    user_home = fixture / 'home'
    project = fixture / 'project'
    user_home.mkdir()
    project.mkdir()
    env = dict(os.environ, HOME=str(user_home), XDG_DATA_HOME=str(user_home/'.local/share'))
    for slot, name in enumerate(('agy', 'agy2', 'agy3'), 1):
        version = subprocess.run([str(bin_dir/name), '--version'], env=env, capture_output=True, text=True, timeout=15)
        assert version.returncode == 0, (name, version.returncode, version.stderr)
        assert version.stdout.strip(), name
        process = subprocess.Popen([str(bin_dir/name), 'acp'], cwd=project, env=env,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, start_new_session=True)
        messages = queue.Queue()
        stderr = []
        def read_stdout():
            for line in process.stdout:
                try:
                    messages.put(json.loads(line))
                except json.JSONDecodeError:
                    messages.put({'invalid': line[:100]})
        threading.Thread(target=read_stdout, daemon=True).start()
        threading.Thread(target=lambda: stderr.extend(process.stderr), daemon=True).start()
        def request(identifier, method, params):
            process.stdin.write(json.dumps({'jsonrpc':'2.0','id':identifier,'method':method,'params':params})+'\n')
            process.stdin.flush()
            while True:
                message = messages.get(timeout=15)
                assert 'invalid' not in message, message
                if message.get('id') == identifier:
                    return message
        try:
            initialized = request(1, 'initialize', {'protocolVersion':1,'clientCapabilities':{},'clientInfo':{'name':'nix-offline-check','version':'1'}})
            assert initialized.get('result',{}).get('protocolVersion') == 1, initialized
            unauthenticated = request(2, 'session/new', {'cwd':str(project),'mcpServers':[]})
            assert 'authentication' in json.dumps(unauthenticated.get('error',{})).lower(), unauthenticated
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        token = user_home / f'.local/share/antigravity-cli/accounts/{slot}/antigravity-cli/antigravity-oauth-token'
        assert not token.exists(), f'{name}: offline check created a credential'
        print(f'{name}: {version.stdout.strip()}, ACP initialized, unauthenticated session rejected without login')
