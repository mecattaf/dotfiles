#!/usr/bin/env python3
"""Private Unix socket transport for the socket-activated GPU worker.

Wire: little-endian uint32 length followed by s16le PCM; zero length commits.
Disconnect without zero cancels. One owner, no queued recordings, 60-second cap.
SSH carries this protocol; no TCP listener or virtual microphone is involved.
systemd owns the listening socket and starts this on the first connect; the
model is released again after --idle-timeout so nothing sits resident.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import select
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time

MAX_BYTES = 60 * 16000 * 2
MAX_FRAME = 65536
LISTEN_FDS_START = 3


def listener(args):
    """Adopt systemd's activation socket, or bind our own when run by hand.

    Returns the socket and whether we own the path: systemd created the socket
    file and outlives us, so an activated server must not unlink it on exit.
    The LISTEN_* variables are popped so the engine subprocess cannot inherit
    an activation contract that is not its own.
    """
    count = int(os.environ.pop('LISTEN_FDS', 0) or 0)
    pid = os.environ.pop('LISTEN_PID', None)
    os.environ.pop('LISTEN_FDNAMES', None)
    if count and (pid is None or int(pid) == os.getpid()):
        if count != 1:
            raise RuntimeError(f'expected one activation socket, got {count}')
        return socket.socket(socket.AF_UNIX, socket.SOCK_STREAM, fileno=LISTEN_FDS_START), False
    sock = socket.socket(socket.AF_UNIX)
    args.socket.unlink(missing_ok=True)
    sock.bind(str(args.socket))
    sock.listen(4)
    return sock, True


def exact(stream, count):
    data = bytearray()
    while len(data) < count:
        part = stream.recv(count - len(data))
        if not part:
            raise EOFError('capture disconnected before commit')
        data.extend(part)
    return bytes(data)


def receive(stream, handle):
    total = 0
    deadline = time.monotonic() + 65
    while True:
        stream.settimeout(min(5, max(.01, deadline - time.monotonic())))
        size, = struct.unpack('<I', exact(stream, 4))
        if size == 0:
            if total < 9600:
                raise ValueError('capture shorter than 300 ms')
            return total
        if size > MAX_FRAME or size % 2 or total + size > MAX_BYTES:
            raise ValueError('invalid frame or capture exceeds 60 seconds')
        if time.monotonic() > deadline:
            raise TimeoutError('capture deadline')
        handle.write(exact(stream, size))
        total += size


def reply(stream, value):
    stream.sendall(json.dumps(value).encode() + b'\n')


class Engine:
    def __init__(self, command):
        self.proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.ready = self.read(120)
        if not self.ready.get('ready'):
            raise RuntimeError('engine did not become ready')

    def read(self, seconds):
        if not select.select([self.proc.stdout], [], [], seconds)[0]:
            self.proc.kill()
            raise TimeoutError('inference worker timed out')
        line = self.proc.stdout.readline(65537)
        if not line or len(line) > 65536:
            raise RuntimeError('inference worker exited or returned oversized response')
        return json.loads(line)

    def run(self, path):
        self.proc.stdin.write(json.dumps(str(path)).encode() + b'\n')
        self.proc.stdin.flush()
        return self.read(90)

    def close(self):
        if self.proc.poll() is None:
            self.proc.stdin.close()
            try:
                self.proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
        return self.proc.returncode


def serve(args):
    args.socket.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.umask(0o077)
    lockfile = (args.socket.parent / 'server.lock').open('a')
    fcntl.flock(lockfile, fcntl.LOCK_EX | fcntl.LOCK_NB)
    cache = os.environ.get("ORT_MIGRAPHX_MODEL_CACHE_PATH")
    if cache: Path(cache).mkdir(parents=True, exist_ok=True)
    engine = Engine([args.engine, str(args.model)])
    owner = threading.Lock()
    stopping = threading.Event()
    threads = []
    sock, owns_path = listener(args)
    sock.settimeout(.2)
    idle_deadline = time.monotonic() + args.idle_timeout if args.idle_timeout else None

    def handle(conn):
        try:
            reply(conn, {'ready': True})
            with tempfile.TemporaryDirectory(prefix='capture-', dir=args.socket.parent) as temp:
                path = Path(temp) / 'audio.pcm'
                with path.open('wb') as target:
                    count = receive(conn, target)
                result = engine.run(path)
                result['audio_seconds'] = count / 32000
                reply(conn, result)
        except (OSError, EOFError, ValueError, TimeoutError, RuntimeError) as exc:
            try: reply(conn, {'error': str(exc)})
            except OSError: pass
        finally:
            conn.close(); owner.release()

    def stop(*_): stopping.set()
    signal.signal(signal.SIGTERM, stop); signal.signal(signal.SIGINT, stop)
    print(json.dumps(engine.ready), flush=True)
    try:
        while not stopping.is_set():
            if engine.proc.poll() is not None:
                raise RuntimeError('GPU worker died')
            try: conn, _ = sock.accept()
            except socket.timeout:
                threads = [t for t in threads if t.is_alive()]
                if idle_deadline is None: continue
                # A live handler is work, not idle: hold the deadline off.
                if threads: idle_deadline = time.monotonic() + args.idle_timeout
                elif time.monotonic() > idle_deadline: break
                continue
            if idle_deadline is not None: idle_deadline = time.monotonic() + args.idle_timeout
            if not owner.acquire(blocking=False):
                conn.settimeout(.1)
                try: reply(conn, {'error': 'another capture owns transcription'})
                except OSError: pass
                conn.close(); continue
            thread = threading.Thread(target=handle, args=(conn,), daemon=True)
            threads = [t for t in threads if t.is_alive()]
            threads.append(thread); thread.start()
    finally:
        sock.close()
        if owns_path: args.socket.unlink(missing_ok=True)
        for thread in threads: thread.join(timeout=1)
        code = engine.close()
        if code: raise RuntimeError(f'GPU worker shutdown failed: {code}')


def relay(args):
    with socket.socket(socket.AF_UNIX) as sock:
        sock.settimeout(100); sock.connect(str(args.socket))
        stream = sock.makefile('rb')
        ready = json.loads(stream.readline(65537))
        if not ready.get('ready'): raise RuntimeError(ready.get('error', 'not ready'))
        # In framed mode only the client can commit; SSH EOF is cancellation.
        while data := os.read(sys.stdin.fileno(), MAX_FRAME):
            if not args.framed: sock.sendall(struct.pack('<I', len(data)))
            sock.sendall(data)
        if not args.framed: sock.sendall(struct.pack('<I', 0))
        sock.shutdown(socket.SHUT_WR)
        response = json.loads(stream.readline(65537))
        if 'error' in response: raise RuntimeError(response['error'])
        sys.stdout.write(response['text']); sys.stdout.flush()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('mode', choices=['serve', 'relay'])
    p.add_argument('--socket', type=Path, default=Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'parakeet-service/engine.sock')
    p.add_argument('--engine', default='parakeet-service-engine')
    p.add_argument('--model', type=Path, default=Path('/var/lib/local-models/parakeet-tdt-0.6b-v3-onnx'))
    p.add_argument('--idle-timeout', type=float, default=0,
                   help='seconds with no capture before the server exits and releases the model; 0 stays up')
    p.add_argument('--framed', action='store_true')
    args = p.parse_args()
    try: serve(args) if args.mode == 'serve' else relay(args)
    except Exception as exc:
        print(f'parakeet-service: {exc}', file=sys.stderr); return 1
    return 0

if __name__ == '__main__': sys.exit(main())
