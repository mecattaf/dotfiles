"""Root releases client first. Read/check display state; never modify it or open a mic."""
import json,pathlib,subprocess,time
p=pathlib.Path('/home/tom/tts-hotword-scott-20260914');out=p/'latency-brightness-zero-v1';out.mkdir(exist_ok=True)
if any(out.iterdir()):raise SystemExit('Refusing to overwrite existing receipts')
def condition():
 def values(pattern):return {str(f):f.read_text().strip() for f in pathlib.Path('/sys').glob(pattern)}
 d={'utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'brightness':values('class/backlight/*/brightness'),'dpms':values('class/drm/card*-eDP-*/dpms')}
 assert d['brightness'].get('/sys/class/backlight/intel_backlight/brightness')=='0',d
 assert d['brightness'].get('/sys/class/backlight/card1-eDP-2-backlight/brightness')=='0',d
 assert len(d['dpms'])>=2 and all(v=='On' for v in d['dpms'].values()),d
 return d
(out/'display-before.json').write_text(json.dumps(condition(),indent=2)+'\n')
runtime='/nix/store/x8blh7qmwhncji5b62z98nf9wv5mbxi6-scott-wake-npu-compatibility/bin/wake-python'
fixture='/home/tom/tts-hotword-research-20260914/cpu-openwakeword/positive-three-idle30.wav'
for count in [3,1]:
 with (out/f'consecutive-{count}.jsonl').open('w') as stdout,(out/f'consecutive-{count}.log').open('w') as stderr:
  child=subprocess.Popen([runtime,str(p/'replay-scott-latency.py'),'--models','/var/lib/local-models/openwakeword-baker-compat-v051','--wav',fixture,'--seconds','51.856','--consecutive',str(count)],stdout=stdout,stderr=stderr)
  checks=[];started=time.monotonic()
  try:
   while child.poll() is None:
    checks.append(condition())
    if time.monotonic()-started>100:raise TimeoutError('bounded latency check')
    time.sleep(1)
   if child.returncode:raise RuntimeError(f'child exit{child.returncode}')
   checks.append(condition())
  finally:
   if child.poll() is None:
    child.terminate()
    try:child.wait(timeout=5)
    except subprocess.TimeoutExpired:child.kill();child.wait()
   (out/f'display-during-{count}.json').write_text(json.dumps(checks,indent=2)+'\n')
 print(json.dumps({'completed_consecutive':count}),flush=True)
(out/'display-after.json').write_text(json.dumps(condition(),indent=2)+'\n');print(json.dumps({'status':'complete','output':str(out)}),flush=True)
