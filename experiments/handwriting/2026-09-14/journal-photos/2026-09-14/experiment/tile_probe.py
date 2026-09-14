#!/usr/bin/env python3
"""Bounded, disposable two-photo/four-request native-resolution tiling probe.

Default action freezes the rule only. --prepare performs no inference. --run is
an explicit opt-in for the orchestrator after the other sweeps have finished.
"""
import argparse
import base64
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import threading
import time
import unicodedata
import urllib.request
from PIL import Image
from benchmark import (ROOT, SYSTEM, USER, MODES, get, save, parse, archive_incomplete,
                       completed_cell, record_failure, ENDPOINT)
from score_quality import normalized, score, load_completed_output, WORD
from summarize_runtime import summarize, report as runtime_report

OUT=ROOT/'runs/tile-probe'
RULE={
 'version':1,
 'scope':'Exactly two photographs, four serial off-mode tile requests; exploratory development and held-out probes, no collection-wide generalization claim.',
 'selection':{'partitions':{'development':list(range(1,9)),'heldout':list(range(9,18))},
              'measure':'Number of score_quality.normalized(transcription) tokens in successful baseline/off JSON. No reference errors or uncertainty counts used.',
              'winner':'Highest count independently in each partition; lowest capture number breaks ties.',
              'requires':'All17 off-baseline outputs have complete=true, parsed=true, finish_reason=stop metadata.'},
 'geometry':{'source':'Original decoded RGB, visually verified input-manifest rotation; do not crop from the downsampled baseline input.',
             'top_height_fraction':0.60,'bottom_start_fraction':0.40,'overlap_full_height_fraction':0.20,
             'max_area':3686400,'stride':32,'resample':'BICUBIC',
             'rounding':'Ceil top end, floor bottom start. Round native dimensions to stride if within cap; otherwise floor max-area scale to stride. No upscale beyond nearest stride.'},
 'inference':{'system_sha256':hashlib.sha256(SYSTEM.encode()).hexdigest(),'user':USER,'mode':'off',
              'settings':{'temperature':0,'max_tokens':16384,'stream':False,'drafter':'mtp',**MODES['off']},
              'ordering':'Development selected photo top then bottom, heldout selected photo top then bottom. One tile/request.'},
 'stitch':{'normalization':'NFKC, case-fold words, ignore punctuation and internal apostrophes; retain original NFKC text for splice.',
           'regions':'Lower token half of top response; upper token half of bottom response.',
           'minimum_anchor_words':10,
           'acceptance':'Maximal exact runs >=10 words must share one top-minus-bottom token offset; longest anchor must be unique. Otherwise refuse. Splice after the shared anchor.',
           'refusal':'Retain both tile texts and anchors; no full-capture candidate on missing/ambiguous anchor.'},
 'scoring':'Freeze copies of the same reviewed references after selecting photographs; before/after use those identical copies and score_quality.score. Selection never reads them.',
 'cost':'Report two model calls per selected photo and their sum, separately from one-call baseline. No production pipeline change.'}


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def freeze(path,obj):
    if path.exists():
        if json.loads(path.read_text())!=json.loads(json.dumps(obj)):raise ValueError(f'Frozen artifact changed: {path}')
    else:
        path.parent.mkdir(parents=True,exist_ok=True)
        save(path,obj)


def upright(image,rotation):
    image=image.convert('RGB')
    if rotation==0:return image
    if rotation==90:return image.transpose(Image.Transpose.ROTATE_90)
    raise ValueError('Only visually verified 0/90-degree orientations are expected')


def tile_boxes(width,height):
    return {'top':(0,0,width,math.ceil(height*.60)),
            'bottom':(0,math.floor(height*.40),width,height)}


def target_size(width,height):
    stride=RULE['geometry']['stride'];cap=RULE['geometry']['max_area']
    size=tuple(max(stride,round(s/stride)*stride) for s in (width,height))
    if size[0]*size[1]>cap:
        factor=math.sqrt(width*height/cap)
        size=tuple(max(stride,math.floor(s/factor/stride)*stride) for s in (width,height))
    if size[0]*size[1]>cap:raise ValueError('Unsupported extreme tile aspect ratio')
    return size


def choose(rows):
    """rows contain only capture ids and off-model text, no reference information."""
    expected=set(range(1,18))
    if {r['capture'] for r in rows}!=expected or len(rows)!=17:raise ValueError('Need all17 unique baseline off outputs')
    counts={r['capture']:len(normalized(r['transcription'])['tokens']) for r in rows}
    return [{'partition':partition,'capture':min(captures,key=lambda n:(-counts[n],n)),
             'all_counts':{str(n):counts[n] for n in captures}}
            for partition,captures in RULE['selection']['partitions'].items()]


def prepare(root=ROOT,out=OUT):
    freeze(root/'tile-protocol.json',RULE)
    models=[];hashes={}
    for n in range(1,18):
        path=root/f'runs/baseline/off/capture-{n:02}-parsed.json'
        output,verification,error=load_completed_output(path)
        if error or verification!='verified_success_metadata':raise ValueError(f'Off capture{n:02} is not complete/parsed: {error or verification}')
        models.append({'capture':n,'transcription':output['transcription']});hashes[str(n)]=sha(path)
    selected=choose(models)
    selection={'protocol_sha256':sha(root/'tile-protocol.json'),'all_off_sha256':hashes,'selected':selected}
    # Selection is persisted before references are read/copied.
    freeze(out/'selection.json',selection)
    manifest={r['capture_order']:r for r in json.loads((root/'input-manifest.json').read_text())['captures']}
    tasks=[]
    for chosen in selected:
        n=chosen['capture'];row=manifest[n];original=root/'originals'/row['file']
        if sha(original)!=row['sha256']:raise ValueError('Original image hash mismatch')
        im=upright(Image.open(original),row['rotation_ccw'])
        for part,box in tile_boxes(*im.size).items():
            crop=im.crop(box);size=target_size(*crop.size)
            if crop.size!=size:crop=crop.resize(size,Image.Resampling.BICUBIC)
            path=out/'inputs'/f'capture-{n:02}-{part}.png';path.parent.mkdir(parents=True,exist_ok=True)
            # Deterministic PNG bytes are checked against frozen task hashes below.
            crop.save(path)
            tasks.append({'capture':n,'physical_page':row['page'],'partition':chosen['partition'],'part':part,
                          'original':str(original),'original_sha256':sha(original),'rotation_ccw':row['rotation_ccw'],
                          'upright_native_size':list(im.size),'native_box':list(box),'input_size':list(size),
                          'image':str(path),'image_sha256':sha(path),'image_tokens':size[0]*size[1]//1024,
                          'baseline_sha256':hashes[str(n)]})
    freeze(out/'tasks.json',{'selection_sha256':sha(out/'selection.json'),'tasks':tasks})
    for chosen in selected:
        n=chosen['capture'];source=root/f'codex-reviewed/capture-{n:02}.json';target=out/f'reference/capture-{n:02}.json'
        freeze(target,json.loads(source.read_text()))
    freeze(out/'reference-hashes.json',{str(c['capture']):sha(out/f"reference/capture-{c['capture']:02}.json") for c in selected})
    return tasks


def word_spans(text):
    text=unicodedata.normalize('NFKC',text)
    matches=list(WORD.finditer(text))
    return text,[re.sub("['’]",'',m.group().casefold()) for m in matches],[(m.start(),m.end()) for m in matches]


def stitch(top,bottom,minimum=10):
    a,at,apos=word_spans(top);b,bt,bpos=word_spans(bottom)
    alo=len(at)//2;bhi=math.ceil(len(bt)/2);anchors=[]
    # Enumerate maximal runs so repeated text cannot hide behind one chosen match.
    for i in range(alo,len(at)):
        for j in range(bhi):
            if at[i]!=bt[j]:continue
            if i>alo and j>0 and at[i-1]==bt[j-1]:continue
            length=0
            while i+length<len(at) and j+length<bhi and at[i+length]==bt[j+length]:length+=1
            if length>=minimum:anchors.append({'top_start':i,'bottom_start':j,'words':length,'offset':i-j})
    result={'status':'no_anchor','anchors':anchors,'transcription':None,'top_text':top,'bottom_text':bottom}
    if not anchors:return result
    longest=max(x['words'] for x in anchors);best=[x for x in anchors if x['words']==longest]
    if len({x['offset'] for x in anchors})!=1 or len(best)!=1:
        result['status']='ambiguous_anchor';return result
    match=best[0];aend=apos[match['top_start']+match['words']-1][1];bend=bpos[match['bottom_start']+match['words']-1][1]
    # The lower response supplies punctuation/newline following the anchor.
    result.update(status='stitched',anchor=match,transcription=a[:aend]+b[bend:],top_kept_characters=[0,aend],bottom_kept_characters=[bend,len(b)])
    return result


@contextmanager
def memory_capture(out,stamp):
    code=Path('/home/tom/huion/ocr/worker_memory_sampler.py').read_text().replace('end = time.monotonic() + 1200','end = time.monotonic() + 14400')
    (out/f'worker_memory_sampler-{stamp}.py').write_text(code)
    child=subprocess.Popen(['ssh','-o','BatchMode=yes','worker','sudo','-n','/etc/profiles/per-user/tom/bin/python3','-u','-'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    child.stdin.write(code);child.stdin.close();ready=threading.Event();state={'last_received':None,'error':None}
    def collect():
        try:
            with (out/f'memory-{stamp}.jsonl').open('w') as f:
                for line in child.stdout:
                    obj=json.loads(line);obj['received_monotonic_ns']=time.monotonic_ns();f.write(json.dumps(obj)+'\n');f.flush();state['last_received']=obj['received_monotonic_ns'];ready.set()
        except Exception as e:state['error']=f'{type(e).__name__}: {e}'
    thread=threading.Thread(target=collect,daemon=True);thread.start()
    def check():
        if state['error'] or state['last_received'] is None or time.monotonic_ns()-state['last_received']>5e9:raise RuntimeError('Tile memory sampler unavailable: '+str(state))
    try:
        if not ready.wait(15):raise RuntimeError('Tile sampler did not start')
        start=time.monotonic_ns();time.sleep(10);check();save(out/f'idle-{stamp}.json',{'start_ns':start,'end_ns':time.monotonic_ns()})
        yield check
        if get('/health')['in_flight']:raise RuntimeError('Server occupied at final idle boundary')
        start=time.monotonic_ns();time.sleep(10);check();save(out/f'final-idle-{stamp}.json',{'start_ns':start,'end_ns':time.monotonic_ns()})
    finally:
        child.terminate()
        try:child.wait(timeout=5)
        except subprocess.TimeoutExpired:child.kill();child.wait()
        thread.join(timeout=3);save(out/f'sampler-status-{stamp}.json',state)
        (out/f'sampler-stderr-{stamp}.txt').write_text(child.stderr.read())


def run(tasks,out=OUT):
    # Only the orchestrator invokes --run after its other sequential sweeps.
    expected=[ROOT/f'runs/baseline/{mode}/capture-{n:02}-metadata.json' for mode in MODES for n in range(1,18)]
    if not all(p.exists() and json.loads(p.read_text()).get('complete') for p in expected):raise ValueError('Wait for all68 vanilla baseline responses')
    if len(tasks)!=4 or len({t['capture'] for t in tasks})!=2:raise ValueError('Probe must contain exactly2 photos/4 tile requests')
    health=get('/health')
    if health['in_flight'] or health['model']!='halogen-qwen3.8-flash-next' or not health['vision']['enabled']:raise ValueError('Halogen must be idle with expected vision model')
    stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ');save(out/f'health-{stamp}.json',health)
    (out/f'tile-source-{stamp}.py').write_bytes(Path(__file__).read_bytes())
    with memory_capture(out,stamp) as check:
        for task in tasks:
            raw=Path(task['image']).read_bytes()
            if hashlib.sha256(raw).hexdigest()!=task['image_sha256']:raise ValueError('Tile image changed')
            settings={'model':health['model'],**RULE['inference']['settings']}
            request_record={'settings':settings,'system':SYSTEM,'user':USER,'image':task['image'],'image_sha256':task['image_sha256'],'encoding':'image/png; base64 data URL'}
            folder=out/('off-'+task['part']);folder.mkdir(exist_ok=True);prefix=folder/f"capture-{task['capture']:02}"
            if completed_cell(prefix,request_record):continue
            check();archive_incomplete(prefix);save(Path(str(prefix)+'-request.json'),request_record)
            mp=Path(str(prefix)+'-metadata.json')
            meta={'capture':task['capture'],'physical_page':task['physical_page'],'partition':task['partition'],'mode':'off-'+task['part'],'image_tokens':task['image_tokens'],'complete':False,'start_monotonic_ns':time.monotonic_ns(),'started_utc':datetime.now(timezone.utc).isoformat(),'cache_before':get('/cache')};save(mp,meta)
            messages=[{'role':'system','content':SYSTEM},{'role':'user','content':[{'type':'text','text':USER},{'type':'image_url','image_url':{'url':'data:image/png;base64,'+base64.b64encode(raw).decode()}}]}]
            request=urllib.request.Request(ENDPOINT+'/v1/chat/completions',data=json.dumps({**settings,'messages':messages}).encode(),headers={'Content-Type':'application/json'})
            print(f"Start capture{task['capture']:02} {task['part']} tile",flush=True)
            try:
                with urllib.request.urlopen(request,timeout=1200) as r:response=json.load(r)
            except Exception as e:record_failure(mp,meta,e,'request');raise
            meta['end_monotonic_ns']=time.monotonic_ns();meta['elapsed_seconds']=(meta['end_monotonic_ns']-meta['start_monotonic_ns'])/1e9
            save(Path(str(prefix)+'-response.json'),response);save(mp,meta)
            try:
                choice=response['choices'][0];content=choice['message'].get('content') or ''
                meta.update(finish_reason=choice['finish_reason'],usage=response.get('usage'),timings=response.get('timings'))
            except (KeyError,IndexError,TypeError,AttributeError) as e:record_failure(mp,meta,e,'response_structure');raise
            Path(str(prefix)+'-answer.txt').write_text(content+'\n')
            try:save(Path(str(prefix)+'-parsed.json'),parse(content));meta['parsed']=True
            except (ValueError,TypeError,AttributeError) as e:meta.update(parsed=False,parse_error=str(e))
            try:meta['cache_after']=get('/cache')
            except Exception as e:meta['cache_after_error']=str(e)
            meta['complete']=choice['finish_reason']=='stop' and bool(content.strip());save(mp,meta)
            print(json.dumps({k:meta[k] for k in ['capture','mode','elapsed_seconds','complete','parsed']}),flush=True)
            if not meta['complete']:raise RuntimeError('Incomplete tile response; evidence retained')
            check()
    save(out/f'health-after-{stamp}.json',get('/health'))


def produce_report(out=OUT):
    for folder in ('stitch','proposed','score'):
        (out/folder).mkdir(parents=True,exist_ok=True)
    selection=json.loads((out/'selection.json').read_text());references=json.loads((out/'reference-hashes.json').read_text())
    rows=[]
    for selected in selection['selected']:
        n=selected['capture'];refpath=out/f'reference/capture-{n:02}.json'
        if sha(refpath)!=references[str(n)]:raise ValueError('Frozen reference changed')
        basepath=ROOT/f'runs/baseline/off/capture-{n:02}-parsed.json'
        if sha(basepath)!=selection['all_off_sha256'][str(n)]:raise ValueError('Selected baseline changed')
        ref=json.loads(refpath.read_text());baseline=json.loads(basepath.read_text());before=score(ref,baseline)
        parts=[];costs=[];missing=[]
        for part in ['top','bottom']:
            path=out/f'off-{part}/capture-{n:02}-parsed.json';obj,verification,error=load_completed_output(path)
            if error or verification!='verified_success_metadata':missing.append({'part':part,'reason':error or verification});continue
            parts.append(obj);costs.append(json.loads(path.with_name(path.name.replace('-parsed.json','-metadata.json')).read_text()))
        row={'capture':n,'partition':selected['partition'],'before':before['metrics'],'tile_calls_complete':len(parts),'missing':missing}
        if len(parts)==2:
            combined=stitch(parts[0]['transcription'],parts[1]['transcription']);row['stitch_status']=combined['status']
            save(out/f'stitch/capture-{n:02}.json',combined)
            row['cost']={'tile_requests':2,'tile_wall_seconds':sum(c['elapsed_seconds'] for c in costs),'baseline_requests':1,
                         'baseline_wall_seconds':json.loads(basepath.with_name(basepath.name.replace('-parsed.json','-metadata.json')).read_text())['elapsed_seconds'],
                         'tile_completion_tokens':sum(c.get('usage',{}).get('completion_tokens',0) for c in costs)}
            if combined['status']=='stitched':
                text=combined['transcription'];flags=[]
                for obj in parts:
                    for flag in obj['uncertainties']:
                        if flag.get('text') and flag['text'] in text and flag not in flags:flags.append(flag)
                candidate={'transcription':text,'uncertainties':flags,'cut_edges':'See raw top/bottom results; synthetic anchor stitch'}
                save(out/f'proposed/capture-{n:02}.json',candidate);(out/f'proposed/capture-{n:02}.md').write_text(text+'\n')
                after=score(ref,candidate);save(out/f'score/capture-{n:02}-before.json',before);save(out/f'score/capture-{n:02}-after.json',after)
                row['after']=after['metrics']
            else:
                for suffix in ['json','md']:
                    candidate=out/f'proposed/capture-{n:02}.{suffix}'
                    if candidate.exists():raise ValueError('Prior proposal exists but current stitch refuses; preserve evidence and inspect')
        rows.append(row)
    save(out/'tile-summary.json',{'rule_sha256':sha(ROOT/'tile-protocol.json'),'probes':rows,'caveat':'Two selected-photo probes, not a generalization claim. Proposed stitches need visual review. Scores are disagreement against the same frozen Codex reference copies, not writer-confirmed accuracy.'})
    lines=['# Native-tile OCR probe','', 'Two selected photographs; two serial requests per photograph. Selection used only baseline off-output normalized word count, independently in development and held-out partitions. Results do not establish collection-wide improvement.', '', '| Capture | Split | Stitch | Before known differences | After known differences | Baseline s (1 call) | Tiles s (2 calls) |','|---:|---|---|---:|---:|---:|---:|']
    for r in rows:
        after=r.get('after');cost=r.get('cost',{})
        before=f"{r['before']['known_disagreement_operations']}/{r['before']['known_reference_words']}"
        av=f"{after['known_disagreement_operations']}/{after['known_reference_words']}" if after else 'not scored'
        lines.append(f"| {r['capture']} | {r['partition']} | {r.get('stitch_status','waiting')} | {before} | {av} | {cost.get('baseline_wall_seconds','—')} | {cost.get('tile_wall_seconds','—')} |")
    lines+=['','The stitch requires at least ten matching normalized words in the prescribed overlap regions and refuses competing offsets or a tied longest anchor. Both raw tile texts remain in `stitch/`, including refusals. Proposed full-capture Markdown is in `proposed/`; it does not replace the reviewed notebook.', '', 'All before/after alignments use the same frozen reference copy for each capture. Uncertainty flags are inherited from retained text spans and are not calibrated probabilities. Sampling/runtime details are in RUNTIME.md; rows are overlapping memory views, not additive allocations.']
    (out/'TILE-PROBE.md').write_text('\n'.join(lines)+'\n')
    stats=summarize(out,expected=4);save(out/'runtime-summary.json',stats);(out/'RUNTIME.md').write_text(runtime_report(stats))
    return rows


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    group=ap.add_mutually_exclusive_group();group.add_argument('--prepare',action='store_true');group.add_argument('--run',action='store_true');group.add_argument('--report',action='store_true')
    args=ap.parse_args();freeze(ROOT/'tile-protocol.json',RULE)
    if args.prepare or args.run:
        tasks=prepare();print('Selected '+', '.join(f"capture{t['capture']:02}-{t['part']}" for t in tasks),flush=True)
        if args.run:run(tasks);produce_report()
    elif args.report:produce_report()
    else:print('Tile selection/geometry/stitch rule frozen; no inference. --prepare after17 successful off outputs; orchestrator explicitly launches --run after other sweeps.')


if __name__=='__main__':main()
