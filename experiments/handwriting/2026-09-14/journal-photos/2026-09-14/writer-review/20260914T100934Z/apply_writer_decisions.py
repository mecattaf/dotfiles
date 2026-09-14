from pathlib import Path
from collections import defaultdict
import json,hashlib,datetime,urllib.request,os,re,difflib
ROOT=Path(__file__).resolve().parent
NOTE=Path('/home/tom/sept14-notepad')
COLL=ROOT.parent.parent
sha=lambda b:hashlib.sha256(b).hexdigest()
when=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
OUT=ROOT/('application-'+when)
OUT.mkdir()
mapping=json.loads((ROOT/'notebook-correction-mapping.json').read_text());items=mapping['items']
expected=json.loads((ROOT/'manifest.json').read_text())['notebook_sha256']

def read_live():
 with urllib.request.urlopen('https://handwriting.internal/api/events') as r:raw=r.read()
 rows=[json.loads(x) for x in raw.decode().splitlines() if x];latest={e['task_id']:e for e in rows}
 for i in items:
  assert latest.get(i['task_id'])==i['writer_event'],f"STOP: writer decision changed: {i['task_id']}"
 return raw
raw_events=read_live();(OUT/'events-verified.jsonl').write_bytes(raw_events)
with urllib.request.urlopen('https://handwriting.internal/api/tasks') as r:raw_tasks=r.read()
(OUT/'tasks-verified.json').write_bytes(raw_tasks)
live_tasks={t['id']:t for t in json.loads(raw_tasks)['tasks']}
for i in items:
 t=live_tasks[i['task_id']]
 assert t['revision']==i['writer_event_revision'] and t['source_sha256']==i['source_sha256'],i['task_id']
 assert sha(Path(i['source_path']).read_bytes())==i['source_sha256'],i['source_path']
files=sorted(NOTE.glob('*.md'))+[NOTE/'uncertainties.json']
before={str(p):p.read_bytes() for p in files}
for p,h in expected.items():assert sha(before[p])==h,f'STOP: notebook changed: {p}'
(OUT/'before').mkdir()
for p,b in before.items():(OUT/'before'/Path(p).name).write_bytes(b)
freeze_files=list((COLL/'codex-reviewed').glob('*'))+list((COLL/'runs/baseline/reconstructed/reference-pages').glob('*'))
frozen={str(p):sha(p.read_bytes()) for p in freeze_files if p.is_file()}
after={p:b.decode() for p,b in before.items()};by_page=defaultdict(list)
for i in items:by_page[i['page']].append(i)
replacements=defaultdict(list)
for i in items:
 p=i['proposed_replacement']
 if p:
  text=after[i['notebook_path']];s,e=p['character_range'];assert text[s:e]==p['old'],i['task_id']
  replacements[i['notebook_path']].append((s,e,p['new']))
for path,repls in replacements.items():
 for s,e,value in sorted(repls,reverse=True):after[path]=after[path][:s]+value+after[path][e:]

# The history is editorial provenance after the original source footer, never handwritten text.
for page,rows in by_page.items():
 path=str(NOTE/f'page{page}.md');history=['','---','','## Writer correction history','','Writer decisions saved 14 September 2026; applied to this notebook after revision and source-hash checks. This section is review history, not photographed text. The original model readings remain in the [audit snapshot]('+str(ROOT/'notebook-correction-mapping.json')+').','']
 for i in rows:
  event=i['writer_event_revision'];tag=f"event {event}, task `{i['task_id']}`";p=i['proposed_replacement']
  if p:history.append(f"- {tag}: `{p['old']}` → `{p['new']}`; writer-resolved literal applied.")
  elif i['action']=='unreadable':
   if page==5:history.append(f"- {tag}: tiny two-line margin addition after ‘Memory drain &’ is **writer-unreadable**. The earlier `ha / rn…` candidate remains uncertain, not accepted text.")
   else:history.append(f"- {tag}: **[unclear: disputed insertion in the Asus 42 / zenbook line; writer marked unreadable]**. The `or` form value was not accepted or inserted; the existence and reading of that additional word remain unsettled.")
  else:
   history.append(f"- {tag}: `{i['writer_literal']}` confirmed; existing text already matches.")
   if i.get('location_note'):history.append('  '+i['location_note'])
 history+=['','The two unreadable decisions across this collection remain in [UNKNOWNS.md](UNKNOWNS.md). These selected decisions do not certify a full-page proofread; the separate Qwen-only queue has not been adjudicated.']
 after[path]=after[path].rstrip()+'\n'+'\n'.join(history)+'\n'

unreadables=[]
for i in items:
 if i['action']!='unreadable':continue
 if i['page']==5:
  desc='Tiny two-line margin addition after Memory drain &; earlier model candidate ha / rn… is unaccepted.'
  candidates='ha / rn… (prior model guess, not writer-confirmed)'
 else:
  desc='Disputed insertion in the Asus 42 / zenbook line. Claude proposed or; Codex included no separate word. Writer marked the item unreadable; presence and wording remain unresolved.'
  candidates='or | no separate word (model disagreement; neither writer-confirmed)'
 unreadables.append({'page':i['page'],'candidates':candidates,'context':i['source_transcription_line'],'status':'writer_unreadable','description':desc,'task_id':i['task_id'],'writer_event_revision':i['writer_event_revision'],'writer_literal_field_accepted':False,'source':i['source_path'],'source_sha256':i['source_sha256'],'image_sha256':i['image_sha256']})
after[str(NOTE/'uncertainties.json')]=json.dumps(unreadables,ensure_ascii=False,indent=2)+'\n'
unknown=['# Remaining uncertain readings','','The writer reviewed all 26 priority items: 24 resolved and two marked unreadable. Ten exact replacements are now applied, and 14 decisions confirm existing text. **Two priority readings remain unresolved** below. The 107 separate Qwen-only flags have not been adjudicated; this is not a claim that every line has been writer-verified.','']
for i in unreadables:unknown.append(f"- [Page {i['page']}](page{i['page']}.md): **writer-unreadable** — {i['description']} Event {i['writer_event_revision']}, task `{i['task_id']}`.")
unknown+=['','A populated literal field on an unreadable event is not an accepted label. Neither prior guess has been silently promoted. Crossed-out unreadable material is marked separately in the pages; the initial cropped sliver above page1 remains unavailable. No missing text has been invented.','','The original nine-item uncertainty list and notebook text are preserved in the [pre-edit snapshot]('+str(OUT/'before')+'). Applied decisions and unchanged confirmations are recorded in [RESOLVED.md](RESOLVED.md) and each affected page’s trailing correction history.']
after[str(NOTE/'UNKNOWNS.md')]='\n'.join(unknown)+'\n'
resolved=after[str(NOTE/'RESOLVED.md')].replace('# Readings resolved from local context','# Reading provenance and writer resolutions',1)
resolved+='\n## Writer review applied — 14 September 2026\n\nThe 26 priority decisions comprise 24 resolved and two unreadable. Ten exact replacements below are applied to the final notebook; 14 other decisions confirm existing readings. The contextual names documented above retain their separate context-based provenance and were not newly writer-confirmed by this pass. The original cross-reviewed Codex benchmark remains unchanged.\n\n| Page | Previous notebook reading | Writer literal applied | Event / task |\n| --- | --- | --- | --- |\n'
for i in items:
 p=i['proposed_replacement']
 if p:resolved+=f"| [Page {i['page']}](page{i['page']}.md) | {p['old'].replace('|',chr(92)+'|')} | {p['new']} | {i['writer_event_revision']} / `{i['task_id']}` |\n"
resolved+='\nConfirmed without changing notebook text:\n\n'
for i in items:
 if i['disposition']=='already_matches_no_text_change':resolved+=f"- Page {i['page']}: `{i['writer_literal']}` — event {i['writer_event_revision']}, task `{i['task_id']}`.\n"
resolved+='\nThe page5 margin and page7 disputed insertion remain writer-unreadable; see [UNKNOWNS.md](UNKNOWNS.md). All current decisions have reuse disabled, so this pass approves no reusable visual examples. Each affected page carries a trailing correction history; the original events, source locations and exact replacements are in the [mapping]('+str(ROOT/'notebook-correction-mapping.json')+'). The [application receipt]('+str(OUT/'application-receipt.json')+') records checked writer revisions and before/after hashes. Future corrections must append new history rather than erase these decisions.\n'
after[str(NOTE/'RESOLVED.md')]=resolved
readme=after[str(NOTE/'README.md')]
old='Three ambiguous names are normalized from matching local notes; see [RESOLVED.md](RESOLVED.md). The remaining uncertain spans are unchanged.'
assert readme.count(old)==1
readme=readme.replace(old,'Writer priority review is applied: 24 resolved decisions produced ten exact replacements and 14 confirmations of existing text. Two items remain writer-unreadable, listed in [UNKNOWNS.md](UNKNOWNS.md). The 107 additional Qwen-only flags have not been adjudicated, so this collection is not yet wholly writer-verified.\n\nThree names remain normalized from matching local notes, with separate provenance. See [RESOLVED.md](RESOLVED.md) and the trailing writer correction histories on the reviewed pages. The frozen cross-reviewed Codex benchmark has not changed; this notebook now includes later writer decisions. No model-proposed correction was accepted solely because models agreed.')
after[str(NOTE/'README.md')]=readme
changed={p:s for p,s in after.items() if s.encode()!=before[p]}
# Preserve a complete reviewable diff and preconditions before any notebook mutation.
(OUT/'applied.patch').write_text(''.join(''.join(difflib.unified_diff(before[p].decode().splitlines(keepends=True),text.splitlines(keepends=True),fromfile=p,tofile=p)) for p,text in sorted(changed.items())))
(OUT/'preconditions.json').write_text(json.dumps({'notebook_before_sha256':{p:sha(b) for p,b in before.items()},'frozen_reference_sha256':frozen,'writer_revisions':{i['task_id']:i['writer_event_revision'] for i in items}},indent=2)+'\n')
# Recheck live decisions and all notebook bytes immediately before committing.
raw=read_live();(OUT/'events-precommit.jsonl').write_bytes(raw)
for p,b in before.items():assert Path(p).read_bytes()==b,f'STOP: concurrent notebook change: {p}'
for p,h in frozen.items():assert sha(Path(p).read_bytes())==h,f'STOP: source changed: {p}'
written=[]
for p,text in changed.items():
 path=Path(p);assert path.read_bytes()==before[p],f'STOP: concurrent change; already written {written}'
 temp=path.with_name('.'+path.name+'.writer-'+when)
 with temp.open('x') as f:f.write(text);f.flush();os.fsync(f.fileno())
 assert path.read_bytes()==before[p],f'STOP: concurrent change before rename; already written {written}'
 os.replace(temp,path);written.append(p)
for p in before:assert Path(p).read_bytes()==after[p].encode(),p
for p,h in frozen.items():assert sha(Path(p).read_bytes())==h,p
receipt={'status':'applied','applied_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_audit_snapshot':str(ROOT),'literal_replacements_applied':10,'unchanged_confirmations_recorded':14,'writer_unreadable_retained':2,'writer_priority_revisions':{i['task_id']:i['writer_event_revision'] for i in items},'changed_files':written,'notebook_before_sha256':{p:sha(b) for p,b in before.items()},'notebook_after_sha256':{p:sha(Path(p).read_bytes()) for p in before},'frozen_reference_sha256':frozen,'frozen_references_unchanged':True,'original_mapping_is_historical_proposal':True,'new_reusable_examples':0,'scope_note':'Writer priority corrections applied, not complete writer proofreading; 107 Qwen-only flags remain unadjudicated. Writer unreadable literal fields were not accepted.'}
(OUT/'application-receipt.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
(OUT/'APPLIED.md').write_text('# Writer decisions applied\n\nTen approved replacements and 14 unchanged confirmations are now recorded in the notebook. Two writer-unreadable items remain explicit: page5 margin and page7 disputed insertion. All 26 live priority revisions matched the original audit immediately before editing.\n\n`before/` preserves every original notebook file. `applied.patch` records the complete change, including trailing histories and indexes. `application-receipt.json` records revisions and before/after hashes; frozen benchmark references are unchanged. The parent snapshot and its proposed mapping remain the historical pre-application record.\n\nChanged files:\n\n'+'\n'.join('- '+Path(p).name for p in written)+'\n')
print(json.dumps({'application':str(OUT),'changed_files':[Path(p).name for p in written],'literal_replacements':10,'confirmations':14,'unreadable':2,'frozen_files_verified':len(frozen)},indent=2))
