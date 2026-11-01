"""Exercise the real supervisor against disposable text/audio HTTP backends."""
import concurrent.futures
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def backend(port, marker, model):
    with open(marker, 'a') as f:
        f.write(model + '\n')
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass
        def do_GET(self):
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'ready', 'data': [{'id': model}]}).encode())
        def do_POST(self):
            data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            self.send_response(200)
            if data.get('stream'):
                self.send_header('Content-Type', 'text/event-stream')
                self.end_headers()
                for i in range(4):
                    self.wfile.write(f'data: {i}\n\n'.encode())
                    self.wfile.flush()
                    time.sleep(0.8)
                self.wfile.write(b'data: [DONE]\n\n')
            else:
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'model': model, 'choices': [{'message': {'content': 'ok'}}]}).encode())
    ThreadingHTTPServer(('127.0.0.1', int(port)), Handler).serve_forever()


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


class Lifecycle(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.marker = self.root / 'starts'
        self.port = free_port()
        config = {'healthCheckTimeout': 15, 'logToStdout': 'both', 'captureBuffer': 0,
                  'performance': {'disabled': True}, 'startPort': free_port(), 'models': {}}
        for model in ['text-a', 'text-b', 'audio']:
            import shlex
            config['models'][model] = {
                'cmd': shlex.join([sys.executable, __file__, '--backend', '${PORT}', str(self.marker), model]),
                'checkEndpoint': '/ready', 'ttl': 1}
        (self.root / 'config.json').write_text(json.dumps(config))
        self.log = (self.root / 'log').open('w+')
        self.proc = subprocess.Popen([os.environ['LLAMA_SWAP'], '-config', str(self.root / 'config.json'),
                                      '-listen', f'127.0.0.1:{self.port}'], stdout=self.log, stderr=self.log)
        self.wait(lambda: self.get('/health') == b'OK')

    def tearDown(self):
        self.proc.terminate()
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()
        self.log.close()
        self.tmp.cleanup()

    def get(self, path):
        with urlopen(f'http://127.0.0.1:{self.port}{path}', timeout=8) as response:
            return response.read()

    def wait(self, predicate):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            try:
                if predicate():
                    return
            except (URLError, ConnectionError, TimeoutError):
                pass
            if self.proc.poll() is not None:
                self.log.seek(0)
                self.fail(self.log.read())
            time.sleep(0.1)
        self.fail('condition timed out')

    def request(self, model='text-a', stream=False, path='/v1/chat/completions'):
        data = json.dumps({'model': model, 'messages': [{'role': 'user', 'content': 'test'}],
                           'stream': stream, 'input': 'test'}).encode()
        return urlopen(Request(f'http://127.0.0.1:{self.port}{path}', data=data,
                               headers={'Content-Type': 'application/json'}), timeout=10)

    def running(self):
        return json.loads(self.get('/running'))['running']

    def test_monitoring_does_not_load_or_keep_models_alive(self):
        for _ in range(3):
            self.get('/health'); self.get('/v1/models'); self.running()
        self.assertFalse(self.marker.exists())
        with self.request() as response:
            self.assertEqual(json.load(response)['model'], 'text-a')
        def sleeping():
            self.get('/health'); self.get('/v1/models')
            return not self.running()
        self.wait(sleeping)
        with self.request() as response:
            self.assertEqual(json.load(response)['model'], 'text-a')
        self.assertEqual(self.marker.read_text().splitlines(), ['text-a', 'text-a'])

    def test_stream_outlives_ttl_without_being_unloaded(self):
        with self.request(stream=True) as response:
            self.assertEqual(response.readline(), b'data: 0\n')
            self.assertTrue(self.running())
            remaining = response.read()
            self.assertIn(b'data: 3', remaining)
            self.assertIn(b'[DONE]', remaining)
        self.assertEqual(self.marker.read_text().splitlines(), ['text-a'])
        self.wait(lambda: not self.running())

    def test_model_and_modality_switching(self):
        for model, path in [('text-a', '/v1/chat/completions'), ('text-b', '/v1/responses'),
                            ('audio', '/v1/audio/speech')]:
            with self.request(model, path=path) as response:
                self.assertEqual(json.load(response)['model'], model)
            self.assertEqual([row['model'] for row in self.running()], [model])
        self.assertEqual(self.marker.read_text().splitlines(), ['text-a', 'text-b', 'audio'])

    def test_concurrent_cold_requests_start_one_backend(self):
        def call():
            with self.request() as response:
                return json.load(response)['model']
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            self.assertEqual(list(pool.map(lambda _: call(), range(2))), ['text-a', 'text-a'])
        self.assertEqual(self.marker.read_text().splitlines(), ['text-a'])

    def test_switch_waits_for_an_active_stream(self):
        with self.request(stream=True) as response:
            self.assertEqual(response.readline(), b'data: 0\n')
            def switch():
                with self.request('text-b') as other:
                    return json.load(other)['model']
            with concurrent.futures.ThreadPoolExecutor(1) as pool:
                future = pool.submit(switch)
                self.assertIn(b'[DONE]', response.read())
                self.assertEqual(future.result(timeout=10), 'text-b')

    def test_unknown_model_does_not_start_any_backend(self):
        with self.assertRaises(HTTPError):
            self.request('unknown')
        self.assertFalse(self.marker.exists())


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--backend':
        backend(*sys.argv[2:])
    else:
        unittest.main()
