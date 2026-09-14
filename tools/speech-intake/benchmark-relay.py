#!/usr/bin/env python3
"""Saved PCM through resident coordinator Voxtype loopback; no physical output."""
import json, os, re, subprocess, time, wave
from pathlib import Path
root=Path('/home/tom/tts-intake-gemma-20260914')
relay=Path(__file__).resolve().parents[2]/'home/dot_local/bin/voxtype-relay'
rows=[]
for fixture in json.loads((root/'fixtures/manifest.json').read_text())[:5]:
    with wave.open(fixture['path']) as wav: pcm=wav.readframes(wav.getnframes())
    start=time.monotonic()
    p=subprocess.run(['bash',str(relay)],input=pcm,capture_output=True,timeout=70,
                     env=dict(os.environ,VOXTYPE_RELAY_TIMING='1'))
    finished=time.time(); elapsed=time.monotonic()-start
    err=p.stderr.decode(); found=re.search(r'audio_endpoint_epoch=([0-9.]+)',err)
    row=dict(id=fixture['id'], duration=fixture['duration'], returncode=p.returncode,
             transcript=p.stdout.decode(), total=elapsed,
             endpoint_to_transcript=finished-float(found[1]) if found else None,
             stderr=err, endpoint_definition='coordinator pw-cat drained, before 200ms loopback tail wait')
    rows.append(row); print(json.dumps(row),flush=True)
    (root/'runs/parakeet-relay-current.json').write_text(json.dumps(rows,indent=2)+'\n')
