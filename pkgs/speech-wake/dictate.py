#!/usr/bin/env python3
"""Herdr's local capture helper. stdin finish/cancel, stdout bounded JSON events."""
import fcntl
import json
import os
from pathlib import Path
import select
import re
import signal
import socket
import subprocess
import sys
import time
from wake import Inhibitors, StreamingRelay, capture, find_microphone, stop
from playback import PlaybackMonitor


def emit(**fields): print(json.dumps(fields), flush=True)


def main():
    if socket.gethostname() not in ('client', 'coordinator'): raise RuntimeError('Dictation requires a physical seat')
    pane = os.environ.get("HERDR_DICTATION_PANE")
    if not pane or not re.fullmatch(r"[A-Za-z0-9:_-]+", pane): raise RuntimeError("Native Herdr pane identity required")
    def occupant():
        args = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "coordinator", "herdr", "pane", "process-info", "--pane", pane]
        response = subprocess.run(args, check=True, capture_output=True, text=True, timeout=8, stdin=subprocess.DEVNULL)
        info = json.loads(response.stdout)["result"]["process_info"]
        return (info.get("shell_pid"), info.get("foreground_process_group_id"), tuple((p["pid"], p.get("cmdline")) for p in info.get("foreground_processes", [])))
    initial_occupant = occupant()
    os.umask(0o077)
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
    state = Path(os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state')))
    lock = (runtime/'speech-dictation.lock').open('a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    inhibitors = Inhibitors(state)
    inhibitors.wake.mkdir(parents=True, exist_ok=True, mode=0o700)
    epoch = str(time.time_ns()).encode()
    temp = inhibitors.wake / f'epoch.{os.getpid()}'
    temp.write_bytes(epoch); temp.replace(inhibitors.wake/'epoch')
    rec = relay = cue = monitor = None
    cancelled = False
    control = bytearray()
    def instruction():
        nonlocal cancelled
        if select.select([sys.stdin], [], [], 0)[0]:
            part = os.read(sys.stdin.fileno(), 4096)
            control.extend(part)
            if not part and b'finish\n' not in control: cancelled = True
            if b'cancel\n' in control: cancelled = True
        return cancelled or b'finish\n' in control
    def blocked():
        instruction()
        reasons, current_epoch = inhibitors.snapshot()
        return cancelled or current_epoch != epoch or any(r != 'held-dictation' for r in reasons)
    def terminate(*_):
        nonlocal cancelled
        cancelled = True
    signal.signal(signal.SIGTERM, terminate); signal.signal(signal.SIGINT, terminate)
    try:
        # A running listener must acknowledge releasing its microphone first.
        active = subprocess.run(['systemctl','--user','is-active','--quiet','speech-wake.service'], stdin=subprocess.DEVNULL).returncode == 0
        deadline = time.monotonic()+2
        while active and (not (inhibitors.wake/'ack').exists() or (inhibitors.wake/'ack').read_bytes()!=epoch):
            if instruction(): return
            if time.monotonic()>deadline: raise RuntimeError('Wake listener did not release microphone')
            time.sleep(.02)
        monitor = PlaybackMonitor(); inhibitors.playback_monitor = monitor
        deadline = time.monotonic()+2
        while monitor.snapshot_reason() == 'playback-monitor-unavailable':
            if instruction(): return
            if time.monotonic()>deadline: raise RuntimeError('Playback monitor unavailable')
            time.sleep(.02)
        if blocked(): raise RuntimeError('Dictation inhibited by call or playback')
        serial = find_microphone()
        if not serial: raise RuntimeError('iContact USB microphone unavailable')
        rec = capture(serial)
        deadline = time.monotonic()+2
        while not select.select([rec.stdout],[],[],.02)[0]:
            if instruction() or blocked(): return
            if time.monotonic()>deadline: raise RuntimeError('USB microphone did not produce audio')
        if not os.read(rec.stdout.fileno(),2560): raise RuntimeError('USB microphone ended')
        cue = subprocess.Popen(['speech-listening-cue'],stdout=subprocess.DEVNULL,stdin=subprocess.DEVNULL)
        while cue.poll() is None:
            if instruction() or blocked(): return
            if select.select([rec.stdout],[],[],.02)[0]: os.read(rec.stdout.fileno(),8192)
        if cue.returncode: raise RuntimeError('Listening cue failed')
        relay = StreamingRelay()
        emit(status='Listening — release Space to transcribe')
        count=0; started=time.monotonic()
        while not instruction():
            if blocked(): return
            if time.monotonic()-started>60: raise RuntimeError('Dictation reached 60-second limit')
            if select.select([rec.stdout],[],[],.02)[0]:
                pcm=os.read(rec.stdout.fileno(),2560)
                if not pcm: raise RuntimeError('USB microphone disconnected')
                count+=len(pcm); relay.feed(pcm)
        stop(rec); rec=None
        if cancelled or count<9600: return
        emit(status='Transcribing…')
        text=relay.finish(blocked);relay=None
        if not text and not blocked():
            raise RuntimeError('No speech detected')
        if text and not blocked():
            if occupant() != initial_occupant: raise RuntimeError("Pane application changed; dictation cancelled")
            # Finish cleanup before native Herdr consumes the result.
            monitor.close();monitor=None;inhibitors.playback_monitor=None
            lock.close()
            emit(text=' '.join(text.split()))
    finally:
        stop(cue);stop(rec)
        if relay:relay.cancel()
        if monitor:monitor.close()
        if not lock.closed:lock.close()

if __name__=='__main__':
    try: main()
    except Exception as exc: emit(error=str(exc))
