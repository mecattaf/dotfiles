"""Event-driven PipeWire playback inhibitor; no microphone or model work."""
import json
import os
import subprocess
import threading
import time

class PlaybackState:
    def __init__(self):
        self.nodes = {}
        self.ready = False
        self.last_active = 0

    def update(self, events):
        for item in events:
            ident = item.get('id')
            if item.get('info', 'missing') is None:
                self.nodes.pop(ident, None)
            elif 'info' in item:
                old = self.nodes.setdefault(ident, {})
                info = item['info']
                old['props'] = dict(old.get('props', {}), **info.get('props', {}))
                if 'state' in info: old['state'] = info['state']
        self.ready = True

    def reason(self):
        if not self.ready: return 'playback-monitor-unavailable'
        active = any(n.get('state') == 'running' and
                     n.get('props', {}).get('media.class') == 'Stream/Output/Audio' and
                     n.get('props', {}).get('node.name') != 'speech-listening-cue'
                     for n in self.nodes.values())
        if active: self.last_active = time.monotonic()
        if active or time.monotonic() - self.last_active < 0.5:
            return 'media-playback'
        return None

class PlaybackMonitor:
    def __init__(self):
        self.state = PlaybackState()
        self.lock = threading.Lock()
        self.proc = subprocess.Popen(['pw-dump', '-m', '-N'], stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def run(self):
        buf = ''; decoder = json.JSONDecoder()
        try:
            while data := os.read(self.proc.stdout.fileno(), 65536):
                buf += data.decode()
                while buf.strip():
                    buf = buf.lstrip()
                    try: events, end = decoder.raw_decode(buf)
                    except json.JSONDecodeError: break
                    with self.lock: self.state.update(events)
                    buf = buf[end:]
                if len(buf) > 16 * 1024 * 1024: break
        finally:
            with self.lock: self.state.ready = False

    def snapshot_reason(self):
        with self.lock: return self.state.reason()

    def close(self):
        self.proc.terminate()
        try: self.proc.wait(timeout=2)
        except subprocess.TimeoutExpired: self.proc.kill(); self.proc.wait()
        self.thread.join(timeout=2)
