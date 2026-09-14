"""Encode independently reviewed decisions; never infer a literal from alignment alone."""
from pathlib import Path
from collections import Counter
import json,re,hashlib,difflib,datetime
BASE=Path(__file__).resolve().parent;COLL=BASE.parent
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
load=lambda p:json.loads(Path(p).read_text())
tasks=load(BASE/'tasks-to-review.json');assets=load(BASE/'served-assets/manifest.json');crops=load(BASE/'crops/manifest.json')
values={int(n):v for n,v in [s.split('\t',1) for s in (BASE/'decisions.tsv').read_text().splitlines()]}
assert len(tasks)==len(values)==107 and set(values)==set(range(1,108))
writer_path=BASE/'live-events.jsonl';writer_events=[json.loads(x) for x in writer_path.read_text().splitlines()];writer_by_rev={x['revision']:x for x in writer_events}
writers={2:1,4:10,7:11,11:3,12:2,17:15,27:5,49:6,50:19,52:7,62:17,63:19,69:22,81:29}
# Needles select the actual source context, not a filename-wide spelling substitution.
needles={8:'Kitty bugs/problems',9:'get continually',10:'One model',11:'Bottom line cropped',17:'7.',18:'Tally full chapter',21:'Kitty usage',23:'9.',27:'abandoned',28:'Tally full chapter',35:'re-investigate',50:'22.',51:'27.',52:'pretty secondary',56:'23.',63:'22.',64:'unless I do choose',68:'ingest into CRM',74:'receiver',75:'Migr done',79:'closing is HIGH',88:'standard coding',94:'Managing storage',96:'paperless',97:'Managing',103:'Youtube'}
claude_needles={8:'Kitty bugs/problems',10:'One model',11:'P.91',17:'7*',18:'Tally full chapter',23:'9 *',27:'abandoned',28:'Tally full chapter',35:'re-investigate',50:'22 *',51:'to have at best',52:'pretty secondary',56:'23 *',63:'22 *',64:'unless I do choose',68:'ingest into CRM',74:'receiver',75:'Migr done',79:'closing is HIGH',88:'standard coding',94:'Managing storage',96:'paperless',97:'Managing',103:'Youtube'}
crop_for={10:'04-unit',18:'05-conw-herdr',21:'05-kitty',23:'05-opti',28:'05-conw-herdr',50:'06-working',52:'06-margin',63:'06-working',64:'07-number',68:'07-nick',75:'09-lacie',79:'10-enoki',88:'11-request',94:'13-hygiene'}
visual_notes={
 8:'The target is the crossed-out Tally below the replacement Kitty, not the active word Kitty. Preserve its cancelled status; resolved here means its letters are identifiable.',
 10:'Native crop shows tkns/Day written over an earlier unit. Keep the existing correction annotation; Mtoks/Day is not the surviving unit. Claude expands tokens, so the compact literal comes from Codex and the crop.',
 11:'Capture04 clips this shared heading. Capture05 shows the same Thomas/campaign heading in full; writer event3 settles Bench there. This is one physical inscription across the overlap, not transfer from an unrelated mention.',
 17:'Qwen split the date label into a crossed-out 2 and 126. Writer event15 settles the complete same-line token as 2H26. This is a whole-label correction, not a blind replacement of every 126.',
 18:'The final IP strokes overlap at the end of CONWIP; native crop supports the full acronym, consistent with both other readers.',
 21:'Qwen reported Kitty usage but omitted it from transcription. Native crop locates the two words at the right margin after item1/direct; both other readers include them. This is present source text, not absent merely because Qwen has no matching output span.',
 22:'All readers identify MELS; the final handwritten S is small. Retain the reviewed acronym case, without treating capitalization as a different word.',
 23:'Native crop shows the abbreviated Qwen-optimizat with a raised terminal mark, represented as ° by the reviewed Codex transcript. Do not expand the ending to optimized; Claude also preserves the abbreviation with different mark notation.',
 28:'Native crop reads the herdr name in item1. Claude capitalizes Herdr; this is the same sequence of letters, and the reviewed lowercase convention is retained.',
 35:'The visually located text is re-investigate under item26. The initial cursive re is not number92. This decision concerns the re prefix; preserve the rest of re-investigate and its arrow.',
 37:'Both transcripts identify Agency with a small raised 2; retain the superscript notation from the reviewed source.',
 50:'The last word of item22’s final three-word phrase is it. The writer confirmed the whole phrase working towards it in event19; native crop locates the final word. Qwen’s dr. is not a separate abbreviation to preserve. Sentence punctuation belongs to the enclosing line.',
 51:'The phrase at the end of the item27 line is for now, agreed by both readers. Qwen merged the two words into format.',
 52:'The existing app context mistakenly points to ha inside harness on item15 (12 substring hits). The Qwen flag reason refers to a cut-off word at the line end. Native crop locates ha/rn in the item26 margin after Memory drain &, exactly the span marked unreadable by writer event7. Do not replace harness or promote the saved ha / rn… form value into literal truth.',
 56:'Both references preserve the shortened optimizat after Qwen-. Do not expand it to optimizing. Terminal abbreviation-mark notation differs; this flag concerns the word stem.',
 62:'Writer event17 confirms workerd.nix at item16, overriding Claude’s workherd.mix and Qwen’s workord mix at this exact location.',
 63:'The first word of item22’s last phrase is working under writer event19. Native crop verifies this is the first word in the writer-selected three-word phrase, not another worky occurrence. The full phrase is working towards it.',
 64:'The nominal 38* is a cancelled item label before unless I do choose, not a new active numbered item. Native crop shows overlapping cancellation strokes; exact former digits cannot be certified. Preserve an unreadable crossed-out label rather than silently add an active38 or declare no ink.',
 69:'Codex identifies workerd.nix at item34. Writer event22 settles its nix suffix at that exact location; the workerd. prefix agrees with Qwen’s flag itself. The event does not indiscriminately confirm every filename in the collection.',
 74:'Both Imzone occurrences are on the same receiver/charger line, and both other readers read Inzone in both positions. Resolve the two identified locations together; no arbitrary first-occurrence selection.',
 80:'Both source versions contain two Mykonos mentions (standalone and Post-Mykonos). They agree on the letters; Claude uses internal capital K. Preserve reviewed Mykonos case and the two separate locations.',
 81:'Writer event29 (latest of repeated saves) confirms nix in the FR12 Tally.nix line. The prefix Tally. is uncontested. This does not import an unrelated nix decision.',
 94:'Native crop has a dotted i immediately after h, then descending g: literal higiene, consistent with Claude and Qwen. Codex’s hygiene standardizes the spelling. Preserve the written nonstandard spelling; this is a newly adjudicated model reading, not a new writer label.',
 96:'Both readers identify paperless and NGX; only spacing differs. Retain the reviewed paperless NGX spacing without claiming the gap identifies a different software name.',
 97:'The raised2 following Ag is retained as superscript²; Claude uses a baseline2. This is notation agreement, not an additional word.',
 103:'Both independent transcripts read the compact name indiedevdan in the Youtube line. Qwen splits it into three tokens; resolve the identifier without substituting an unrelated independent.',
}
unreadable_intended={68:'nick-iconiq',75:'LaCie migration',79:'Enoki',88:'request'}
pending_notes={
 68:'Known intended referent is nick-iconiq from prior contextual adjudication, but the native crop still leaves the literal middle/final spelling ambiguous (nick-icong / nick-iconq / iconiq). No writer decision covers this name. Retain unreadable literal status with intended=nick-iconiq; do not mislabel a context normalization as confirmed handwriting.',
 75:'FR03’s intended referent is LaCie migration, established earlier. Native crop does not reliably distinguish the compressed c in Lacie from Laie; the Codex reference explicitly retains both and Claude chooses Lacie. Louie is rejected, but exact literal spelling remains unreadable while intended=LaCie migration records the settled referent.',
 79:'FR04’s intended referent is Enoki, established earlier. The native crop’s compressed middle letters still permit the Codex Emaki/Enaki candidates as well as Claude Enoki; there is no writer decision for this name. Record intended=Enoki with unreadable literal status: context resolves meaning, not a unique literal spelling.',
 88:'The tiny final word of item7 is an abbreviation/full-word ambiguity: Codex request, Claude reqst., Qwen req. Both the native capture11 crop and the larger facing-page capture13 view show the same coding req…t ending but do not reliably distinguish compressed internal letters from shorthand. Record intended=request with unreadable literal; do not silently expand it.',
}

norm=lambda s:re.sub(r'\s+',' ',s.casefold()).strip()
def line_evidence(reader,capture,t,needle=None):
 p=COLL/reader/f'capture-{capture:02}.json';j=load(p);trans=j['transcription'];lines=trans.splitlines(keepends=True)
 if needle:
  hits=[(i,line) for i,line in enumerate(lines) if needle.casefold() in line.casefold()]
  assert len(hits)==1,(t['audit_index'],reader,needle,len(hits))
  ix,line=hits[0]
 else:
  ranked=sorted(((difflib.SequenceMatcher(None,norm(t['line']),norm(line)).ratio(),i,line) for i,line in enumerate(lines) if line.strip()),reverse=True)
  score,ix,line=ranked[0]
  assert score>.30,(t['audit_index'],reader,score,line)
 start=sum(len(x) for x in lines[:ix]);end=start+len(line.rstrip('\n'))
 return {'path':str(p),'sha256':sha(p),'reader':'Codex independently cross-reviewed' if reader=='codex-reviewed' else 'Claude first pass; model metadata self-reported claude-opus-5','location':{'field':'transcription','line_number':ix+1,'character_range':[start,end],'text':line.rstrip('\n')}}

resolved=[];pending=[];audit=[]
for t in tasks:
 n=t['audit_index'];capture=t['capture'];value=values[n]
 code_ev=line_evidence('codex-reviewed',capture,t,needles.get(n))
 cl_ev=line_evidence('claude-first',capture,t,claude_needles.get(n,needles.get(n)))
 src=Path(t['source']);assert sha(src)==t['source_sha256']
 evidence=[{'path':str(src),'sha256':t['source_sha256'],'reader':'Qwen off baseline; flagged hypothesis, not authority','location':{'field':'uncertainties','reported_text':t['raw'],'app_context':t['line'],'app_occurrences':t.get('occurrences')}},code_ev,cl_ev]
 image_ev=assets[t['image']];evidence.append({'path':image_ev['path'],'sha256':image_ev['sha256'],'reader':'Photograph supplied by writer; app image evidence','location':{'asset_id':t['image'],'capture':capture}})
 if n==8:
  cp=COLL/'claude-first/capture-03.json';cj=load(cp)
  evidence.append({'path':str(cp),'sha256':sha(cp),'reader':'Claude first-pass uncertainty metadata','location':{'field':'uncertainties[1].alternatives[0]','text':cj['uncertainties'][1]['alternatives'][0]}})
 if n in writers:
  rev=writers[n];e=writer_by_rev[rev]
  evidence.append({'path':str(writer_path),'sha256':sha(writer_path),'reader':'writer','location':{'format':'JSONL event','revision':rev,'task_id':e['task_id'],'action':e['action'],'literal':e['literal'],'box':e.get('box'),'page_key':e['page_key']}})
 if n==11:
  evidence.append(line_evidence('codex-reviewed',5,t,'P.21 of pdf Thomas'));evidence.append(line_evidence('claude-first',5,t,'P.21 of pdf Thomas'))
 if n in crop_for:
  c=crops[crop_for[n]];crop=Path(c['crop_path'])
  evidence.append({'path':str(crop),'sha256':sha(crop),'reader':'Codex model review; native crop visually inspected','location':{'original_path':c['original'],'original_sha256':c['original_sha256'],'rotation_ccw':c['rotation_ccw'],'upright_size':c['upright_size'],'box_upright_px':c['box_upright_px']}})
 if n in (68,75,79):
  cp=COLL/'CONTEXT-ADJUDICATION.md';evidence.append({'path':str(cp),'sha256':sha(cp),'reader':'Prior local-context investigation, not literal writer confirmation','location':{'section':'nick-iconiq' if n==68 else 'LaCie' if n==75 else 'Enoki'}})
 if n==88:
  c=crops['13-facing-request'];crop=Path(c['crop_path'])
  evidence.append({'path':str(crop),'sha256':sha(crop),'reader':'Codex model review; second native view inspected','location':{'original_path':c['original'],'original_sha256':c['original_sha256'],'rotation_ccw':c['rotation_ccw'],'upright_size':c['upright_size'],'box_upright_px':c['box_upright_px'],'note':c['note']}})
 note=pending_notes[n] if n in unreadable_intended else visual_notes.get(n)
 if not note:
  note='Reviewed the flag in its matching source sentence against the Codex cross-review and Claude first pass; the selected literal is supported at this location. Model adjudication only, not writer confirmation.'
 method='writer_override_at_same_location' if n in writers else 'native_crop_and_reference_review' if n in crop_for else 'context_matched_reference_review'
 row={'audit_index':n,'task_id':t['id'],'revision':t['revision'],'capture':capture,'page':t['page'],'raw':t['raw'],'intended':unreadable_intended.get(n,''),'note':note,'evidence':evidence,'method':method,'source_sha256':t['source_sha256'],'image_sha256':image_ev['sha256'],'actor':'model_review','reuse':False,'writer_confirmed':False,'automatic_transcript_replacement_authorized':False}
 if value=='!pending':
  row.update(status='pending',reason=pending_notes[n],note=pending_notes[n]);pending.append(row)
 else:
  row.update(action='unreadable' if value=='!unreadable' else 'resolved',literal='' if value=='!unreadable' else value);resolved.append(row)
 audit.append(row)

counts={'audited':len(tasks),'resolution_items':len(resolved),'actions':dict(Counter(x['action'] for x in resolved)),'pending':len(pending),'methods':dict(Counter(x['method'] for x in resolved)),'writer_override_items':sum(x['method']=='writer_override_at_same_location' for x in resolved),'source_counts':{'codex_capture_files':len({e['path'] for r in audit for e in r['evidence'] if e['reader']=='Codex independently cross-reviewed'}),'claude_capture_files':len({e['path'] for r in audit for e in r['evidence'] if e['reader'].startswith('Claude first')}),'writer_event_revisions':sorted(set(writers.values())),'native_crops_inspected':len(crops),'served_image_assets_sha256_verified':len(assets)},'writer_labels_created':0,'reusable_examples_approved':0}
doc={'version':1,'collection':str(COLL),'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'Prepared model-review decisions only; live state, notebook and frozen references unchanged','items':resolved,'pending':pending,'stats':counts}
(BASE/'resolutions.json').write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n')
(BASE/'audit-all107.json').write_text(json.dumps({'stats':counts,'items':audit},ensure_ascii=False,indent=2)+'\n')
lines=['# Reconciliation of all 107 Qwen flags','','Every pending Qwen task was inspected in its source context against the independently cross-reviewed Codex capture and Claude first-pass capture. Existing writer decisions take precedence only at their identified inscription; native photographs/crops were inspected for conflict, overlap, cancellation and locator problems. No blind string-substitution or majority-vote pass was used.','',f"Prepared **{len(resolved)} decisions**: {counts['actions'].get('resolved',0)} resolved literal readings and {counts['actions'].get('unreadable',0)} unreadable inscriptions. **{len(pending)} literal conflicts remain pending** with precise reasons below. No live event has been written, no notebook has been changed and no frozen benchmark reference has been edited by this pass. Model decisions must be imported with actor=model_review, not writer; none approves a reusable visual example.",'','## Retained literal unknowns','']
for r in resolved:
 if r['action']=='unreadable':lines.append(f"- Capture{r['capture']:02}, `{r['raw']}` (task `{r['task_id']}`): {r['note']}")
lines+=['','## Location and preservation checks','','- `ha` was wrongly located inside `harness` by substring matching. It belongs to the item26 margin already marked unreadable by writer event7; that status transfers to the same ink, not to harness.','- `Kitty usage` is visually present in item1’s right margin despite being absent from Qwen’s transcription. It is resolved as present, not removed.','- Both `Imzone` reports refer to Inzone in the receiver/charger line. Both locations agree; no arbitrary first hit was selected.','- The false `38*` before “unless I do choose” is a cancelled label. Its exact overwritten digits remain unreadable; no new active item number is inserted.','- `Thomas Bend` on capture04 uses the fully visible same heading on overlapping capture05 and writer event3 for Bench.','- `126`, `worky`, and `dr.` are malformed fragments of larger writer-reviewed units. Notes identify the complete 2H26 / working towards it context; the resolution file is not a license for raw global replacement.','- `higiene` on capture13 is retained literally after native-crop review, agreeing with Claude and Qwen. The frozen Codex hygiene spelling is not silently changed.','- Known name referents nick-iconiq, LaCie and Enoki remain available from the earlier context notes, but exact visual spelling uncertainty is not relabeled as writer confirmation.','','## All decisions','','| # | Capture | Qwen flag | Disposition / literal | Evidence method |','| --- | --- | --- | --- | --- |']
for r in audit:
 lit='pending' if r.get('status')=='pending' else '[unreadable]'+('; intended: '+r['intended'] if r['intended'] else '') if r['action']=='unreadable' else r['literal']
 lines.append(f"| {r['audit_index']} | {r['capture']:02} | {r['raw'].replace('|',chr(92)+'|')} | {lit.replace('|',chr(92)+'|')} | {r['method']} |")
lines+=['','## Import contract','','`resolutions.json` contains `items` with task_id, live base revision, action (resolved/unreadable), literal, intended, note, evidence, method, source_sha256 and image_sha256. Additional provenance fields explicitly mark model_review/reuse=false/writer_confirmed=false. `pending` is an audit list, not an action to import. An importer must check the base revision and source/image identity before writing, preserve writer decisions, and create no writer-approved example. `automatic_transcript_replacement_authorized:false` means this task-review file is not a notebook patch.','','Each evidence location identifies its source JSON field and exact line/character range, writer event revision, or a inspected native crop with source-image hash and actual coordinate basis. Hashes are SHA-256. Character offsets refer to the decoded transcription string and are zero-based/end-exclusive; line numbers are one-based. The app asset is separately hashed from its bytes.','','No new human annotation is requested by this artifact. All107 tasks have explicit dispositions, including six unreadable task readings; this does not mean every letter is settled. The ha item duplicates the existing writer-unreadable margin. Three names and the request abbreviation carry intended referents without an invented literal. The cancelled number remains explicitly unreadable.']
(BASE/'AUDIT.md').write_text('\n'.join(lines)+'\n')
print(json.dumps(counts,indent=2))
for r in audit:print(str(r['audit_index']).rjust(3),r['raw'],'=>',r.get('literal','PENDING'),'| C:',r['evidence'][1]['location']['text'],'| L:',r['evidence'][2]['location']['text'])
