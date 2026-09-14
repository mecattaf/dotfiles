#!/usr/bin/env python3
"""Offline comparison of two immutable vanilla passes; never sends a model request."""
import difflib,hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
NEW=Path(__file__).resolve().parent
OLD=ROOT/'runs/fresh-off'
def load(p): return json.loads(p.read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
rows=[]
for n in range(1,18):
 name=f'capture-{n:02}'
 a,b=OLD/'off'/name,NEW/'off'/name
 def f(p,s):return Path(str(p)+s)
 if not f(b,'-parsed.json').exists():continue
 oa,nb=load(f(a,'-parsed.json')),load(f(b,'-parsed.json'))
 om,nm=load(f(a,'-metadata.json')),load(f(b,'-metadata.json'))
 request_equal=load(f(a,'-request.json'))==load(f(b,'-request.json'))
 row={'capture':n,'request_equal':request_equal,'complete':nm['complete'],
      'answer_bytes_equal':f(a,'-answer.txt').read_bytes()==f(b,'-answer.txt').read_bytes(),
      'parsed_object_equal':oa==nb,'transcription_exact_equal':oa['transcription']==nb['transcription'],
      'uncertainties_equal':oa['uncertainties']==nb['uncertainties'],
      'previous_seconds':om['elapsed_seconds'],'current_seconds':nm['elapsed_seconds'],
      'previous_cache_n':om['timings']['cache_n'],'current_cache_n':nm['timings']['cache_n'],
      'previous_answer_sha256':sha(f(a,'-answer.txt')),'current_answer_sha256':sha(f(b,'-answer.txt')),
      'transcription_diff':list(difflib.unified_diff(oa['transcription'].splitlines(),nb['transcription'].splitlines(),fromfile='previous',tofile='confirmation',lineterm=''))}
 rows.append(row)
result={'previous_run':str(OLD),'confirmation_run':str(NEW),'expected':17,'compared':len(rows),
        'counts':{k:sum(r[k] for r in rows) for k in ['request_equal','complete','answer_bytes_equal','parsed_object_equal','transcription_exact_equal','uncertainties_equal']},'captures':rows,
        'interpretation':'Repeatability of the same frozen request recipe, not writer-confirmed accuracy or a cold-cache reproducibility guarantee. No writer labels were submitted to the model.'}
(NEW/'comparison.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
print(json.dumps({'compared':len(rows),'counts':result['counts']}))
