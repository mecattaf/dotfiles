#!/usr/bin/env python3
"""Client-only final-WAV playback with wake inhibition and call gating."""
import fcntl, io, json, os, socket, subprocess, sys, time, wave
from pathlib import Path

def main():
    if socket.gethostname() != 'client': raise RuntimeError('Playback is client-only')
    state=Path.home()/'.local/state'; gate=state/'mykonos-wake'
    runtime=Path(os.environ.get('XDG_RUNTIME_DIR',f'/run/user/{os.getuid()}'))
    gate.mkdir(parents=True,exist_ok=True,mode=0o700)
    locks=runtime/'qwen-speech';locks.mkdir(parents=True,exist_ok=True,mode=0o700)
    def call(): return any(p.exists() for p in [gate/'call-record',gate/'manual-call',state/'call-record/current'])
    if call(): return 75
    data=sys.stdin.buffer.read(128*1024*1024+1)
    if len(data)>128*1024*1024: raise ValueError('WAV too large')
    with wave.open(io.BytesIO(data)) as wav:
        if wav.getnchannels()!=1 or wav.getsampwidth()!=2 or wav.getframerate()!=24000:
            raise ValueError('Expected final mono PCM16 24kHz WAV')
    with (locks/'playback.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        if call(): return 75
        epoch=str(time.time_ns()).encode();marker=gate/'playback';marker.touch(mode=0o600)
        temp=gate/f'.epoch-{os.getpid()}';temp.write_bytes(epoch);temp.replace(gate/'epoch')
        player=None
        try:
            listener=runtime/'mykonos-wake/lock'
            listening=False
            if listener.exists():
                with listener.open('a') as handle:
                    try: fcntl.flock(handle,fcntl.LOCK_EX|fcntl.LOCK_NB)
                    except BlockingIOError: listening=True
            if listening:
                deadline=time.monotonic()+2
                while not ((gate/'ack').exists() and (gate/'ack').read_bytes()==epoch):
                    if time.monotonic()>deadline: return 75
                    time.sleep(.02)
            if call(): return 75
            # Use a private file so monitoring cannot block behind a full stdin pipe.
            import tempfile
            with tempfile.NamedTemporaryFile(suffix='.wav') as wavfile:
                wavfile.write(data);wavfile.flush()
                player=subprocess.Popen(['pw-play','--properties','{"node.name":"mykonos-speech-playback"}',wavfile.name])
                while player.poll() is None:
                    if call():
                        player.terminate();player.wait(timeout=3);return 2
                    time.sleep(.08)
                return 0 if player.returncode==0 else 2
        finally:
            if player and player.poll() is None: player.terminate();player.wait(timeout=3)
            temp.write_text(str(time.time_ns()));temp.replace(gate/'epoch');marker.unlink(missing_ok=True)
if __name__=='__main__':
    try:sys.exit(main())
    except Exception as exc:print(f'mykonos-play: {exc}',file=sys.stderr);sys.exit(2)
