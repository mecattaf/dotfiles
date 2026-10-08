#!/usr/bin/env python3
"""Seat final-WAV playback with call gating.

call-record holds playback with call-record/active for the whole call, and
call-record/current while its session is published."""
import fcntl, io, os, socket, subprocess, sys, time, wave
from pathlib import Path

def main():
    if socket.gethostname() not in ('client', 'coordinator'): raise RuntimeError('Playback requires a physical seat')
    calls=Path.home()/'.local/state/call-record'
    runtime=Path(os.environ.get('XDG_RUNTIME_DIR',f'/run/user/{os.getuid()}'))
    locks=runtime/'qwen-speech';locks.mkdir(parents=True,exist_ok=True,mode=0o700)
    def call(): return any(p.exists() for p in [calls/'active',calls/'current'])
    if call(): return 75
    data=sys.stdin.buffer.read(128*1024*1024+1)
    if len(data)>128*1024*1024: raise ValueError('WAV too large')
    with wave.open(io.BytesIO(data)) as wav:
        if wav.getnchannels()!=1 or wav.getsampwidth()!=2 or wav.getframerate()!=24000:
            raise ValueError('Expected final mono PCM16 24kHz WAV')
    with (locks/'playback.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        if call(): return 75
        player=None
        try:
            # Use a private file so monitoring cannot block behind a full stdin pipe.
            import tempfile
            with tempfile.NamedTemporaryFile(suffix='.wav') as wavfile:
                wavfile.write(data);wavfile.flush()
                player=subprocess.Popen(['pw-play','--properties','{"node.name":"speech-session-playback"}',wavfile.name])
                while player.poll() is None:
                    if call():
                        player.terminate();player.wait(timeout=3);return 2
                    time.sleep(.08)
                return 0 if player.returncode==0 else 2
        finally:
            if player and player.poll() is None: player.terminate();player.wait(timeout=3)
if __name__=='__main__':
    try:sys.exit(main())
    except Exception as exc:print(f'speech-play: {exc}',file=sys.stderr);sys.exit(2)
