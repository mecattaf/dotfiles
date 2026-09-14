#!/usr/bin/env python3
"""Same saved WAVs as Gemma, with Voxtype's model-load/inference split preserved."""
import hashlib, importlib.util, json, re, socket, subprocess, time
from pathlib import Path
assert socket.gethostname() == 'coordinator'
root=Path('/home/tom/tts-intake-gemma-20260914')
spec=importlib.util.spec_from_file_location('benchmark',Path(__file__).with_name('benchmark.py'))
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
out=root/'runs/parakeet-file';out.mkdir(exist_ok=True)
rows=[]
for f in json.loads((root/'fixtures/manifest.json').read_text()):
 for i in range(3):
  start=time.monotonic()
  p=subprocess.run(['voxtype','transcribe',f['path'],'--engine','parakeet'],capture_output=True,text=True,timeout=90)
  elapsed=time.monotonic()-start
  log=p.stderr+p.stdout
  loads=re.findall(r'model loaded in ([0-9.]+)s',log)
  infer=re.findall(r'transcription completed in ([0-9.]+)s',log)
  # Voxtype logging may write to stdout; retain only non-log transcript lines.
  text='\n'.join(x for x in p.stdout.splitlines() if x.strip() and not x.startswith(('Loading audio file:', 'Audio format:', 'Processing ')) and not re.match(r'^\d{4}-\d\d-\d\dT',x))
  row=dict(fixture=f['id'],repeat=i+1,audio_seconds=f['duration'],audio_sha256=f['sha256'],process_seconds=elapsed,load_seconds=float(loads[-1]) if loads else None,inference_seconds=float(infer[-1]) if infer else None,text=text,exit_code=p.returncode,wer=b.wer(f['expected'],text))
  (out/f"{f['id']}-{i+1}.log").write_text(log)
  rows.append(row);(out/'summary.json').write_text(json.dumps(rows,indent=2)+'\n');print(json.dumps(row),flush=True)
