#!/usr/bin/env python3
"""Run the same six pages at three distinct efforts plus no thinking.

Read-only GPU/memory sampling on worker runs for this process lifetime.
Usage: python3 effort_benchmark.py NEW_OUTPUT_DIRECTORY
"""
import base64
import argparse
import hashlib
import json
import subprocess
import sys
import threading
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from baseline import ROOT, ENDPOINT, PROMPT, get, save

MODES = {'low': {'enable_thinking': True, 'reasoning_effort': 'low'},
         'medium': {'enable_thinking': True, 'reasoning_effort': 'medium'},
         'xhigh': {'enable_thinking': True, 'reasoning_effort': 'xhigh'},
         'off': {'enable_thinking': False, 'reasoning_effort': 'medium'}}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('output')
    parser.add_argument('--modes', default='low,medium,xhigh,off')
    parser.add_argument('--large-probe', action='store_true')
    args = parser.parse_args()
    selected = args.modes.split(',')
    if not selected or any(m not in MODES for m in selected):
        parser.error('modes must be selected from low,medium,xhigh,off')
    out = Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=False)
    health = get('/health')
    save(out/'health-before.json', health)
    if health['model'] != 'halogen-qwen3.8-flash-next' or not health['vision']['enabled'] or health['in_flight']:
        raise RuntimeError('Expected idle Flash with vision')
    sampler = subprocess.Popen(['ssh', '-o', 'BatchMode=yes', 'worker', 'sudo -n /etc/profiles/per-user/tom/bin/python3 -u -'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    sampler.stdin.write((ROOT/'worker_memory_sampler.py').read_text())
    sampler.stdin.close()
    received = threading.Event()
    def collect():
        with (out/'memory-samples.jsonl').open('w') as log:
            for line in sampler.stdout:
                sample = json.loads(line)
                sample['received_monotonic_ns'] = time.monotonic_ns()
                log.write(json.dumps(sample)+'\n'); log.flush(); received.set()
    reader = threading.Thread(target=collect, daemon=True); reader.start()
    try:
        if not received.wait(10):
            raise RuntimeError('Worker memory sampling did not start')
        idle_start = time.monotonic_ns()
        print('Measuring 10 seconds with model resident and no benchmark requests.', flush=True)
        time.sleep(10)
        idle_end = time.monotonic_ns()
        save(out/'idle-window.json', {'start_ns': idle_start, 'end_ns': idle_end})
        common = {'model':health['model'], 'temperature':0, 'max_tokens':16384, 'stream':False, 'drafter':'mtp'}
        save(out/'protocol.json', {'prompt':PROMPT, 'common':common, 'modes':{m:MODES[m] for m in selected}, 'aliases':{'minimal':'low','high':'xhigh'}, 'sampling_interval_seconds':0.25, 'ordering':'Each page is tested at all selected modes; mode order rotates by page. One run per page/mode.', 'memory_notes':'Driver GTT/VRAM allocation, process RSS/locked pages, KFD accounting and host meminfo overlap; do not sum these counters. Resident model remains loaded. No power measurement.'})
        for mode in selected:
            fields = MODES[mode]
            folder=out/mode; folder.mkdir()
            save(folder/'protocol.json', {'prompt':PROMPT,'settings':{**common,**fields}})
        pages=json.loads((ROOT/'corpus.json').read_text())['pages']
        if args.large_probe:
            pages.append({'id':'p01-large','source':str(ROOT/'crops/p01/page.png')})
        for i,page in enumerate(pages):
            source=Path(page['source']).with_suffix('.png'); raw=source.read_bytes()
            modes=selected[i%len(selected):]+selected[:i%len(selected)]
            for mode in modes:
                folder=out/mode; pid=page['id']
                payload={**common, **MODES[mode], 'messages':[{'role':'user','content':[{'type':'text','text':PROMPT},{'type':'image_url','image_url':{'url':'data:image/png;base64,'+base64.b64encode(raw).decode()}}]}]}
                save(folder/f'{pid}-request.json',payload)
                meta={'page_id':pid,'mode':mode,'image':str(source),'image_sha256':hashlib.sha256(raw).hexdigest(),'started_utc':datetime.now(timezone.utc).isoformat(),'start_monotonic_ns':time.monotonic_ns()}
                print(f'{pid} {mode}: start',flush=True)
                request=urllib.request.Request(ENDPOINT+'/v1/chat/completions',data=json.dumps(payload).encode(),headers={'Content-Type':'application/json'})
                with urllib.request.urlopen(request,timeout=600) as response:
                    body=response.read()
                meta['end_monotonic_ns']=time.monotonic_ns()
                (folder/f'{pid}-response.json').write_bytes(body)
                result=json.loads(body); choice=result['choices'][0]; content=choice['message'].get('content') or ''
                meta.update(elapsed_seconds=(meta['end_monotonic_ns']-meta['start_monotonic_ns'])/1e9,finish_reason=choice['finish_reason'],complete=choice['finish_reason']=='stop' and bool(content.strip()),usage=result.get('usage'),timings=result.get('timings'))
                save(folder/f'{pid}-metadata.json',meta)
                (folder/f'{pid}-answer.txt').write_text(content+'\n')
                print(json.dumps({k:meta[k] for k in ['page_id','mode','elapsed_seconds','complete','usage']}),flush=True)
                if not meta['complete']:
                    raise RuntimeError('Incomplete request; retained evidence and stopped without retry')
        save(out/'health-after.json',get('/health'))
    finally:
        sampler.terminate()
        try:
            sampler.wait(timeout=5)
        except subprocess.TimeoutExpired:
            sampler.kill(); sampler.wait()
        reader.join(timeout=3)
        (out/'sampler-stderr.txt').write_text(sampler.stderr.read())


if __name__=='__main__':
    main()
