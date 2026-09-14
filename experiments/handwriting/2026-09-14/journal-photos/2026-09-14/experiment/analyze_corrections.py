#!/usr/bin/env python3
"""Analyze disposable crop-correction proposals; never patch notes or call a model."""
import argparse
from collections import Counter
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import re
from score_quality import ROOT, normalized, score, save, load_completed_output

ARMS=['off-crop','off-crop-hints','low-crop-hints','medium-crop-hints']
POLICY='consensus'
METHOD='''Proposals replace exactly one literal occurrence of the frozen old span in its original off baseline. All found, nonempty readings are analyzed, including self-reported uncertainty; clear-only acceptance is reported separately. Consensus accepts only when off-crop and low-crop-hints both find a clear, nonempty reading and agree after casefolding and whitespace collapse only. Agreement is not independent proof of correctness: these calls share a model and hints may bias one arm. Otherwise the target remains for review. No notebook files are edited.

Each available result is scored before/after against frozen Codex references using score_quality. Negative known-word delta means less reference disagreement; positive means regression. A change wholly aligned to uncertain reference tokens is labeled unknown_reference_unscorable rather than correct. Mixed uncertain/certain targets are marked. Dates are separately compared by the scorer. These are provisional visual references, not author-confirmed truth. Development is01–08; held out is09–17. Missing responses remain pending and never count as observed unchanged outcomes.

Candidate files are full baseline pages with at most one experimental replacement. Untargeted pages copy baseline; pending targeted pages retain baseline and carry pending metadata. Per-arm candidates include all valid found proposals; clear-only candidate arms apply only clear proposals. Consensus candidates apply only agreed clear proposals. Costs sum the original baseline request plus the correction calls needed by that arm (two for consensus), including review/rejection calls. Latency sums are observed components under their recorded cache states, not a controlled end-to-end benchmark; incomplete timing coverage produces no total latency. Only available result cells enter outcome summaries; baseline copies are not correction successes.'''


def read(path):
    if not path.exists(): return None
    try: return json.loads(path.read_text())
    except (ValueError,OSError): return None


def agreement_key(value): return ' '.join(value.casefold().split())


def valid_result(obj):
    if not (isinstance(obj,dict) and isinstance(obj.get('found'),bool) and
            (obj.get('reading') is None or isinstance(obj.get('reading'),str)) and
            obj.get('difficulty') in ('clear','uncertain','unreadable') and
            isinstance(obj.get('alternatives'),list) and len(obj['alternatives'])<=3 and
            all(isinstance(x,str) for x in obj['alternatives']) and isinstance(obj.get('evidence'),str)):
        return False
    if not obj['found'] and obj['reading'] is not None:return False
    if obj['difficulty']=='clear' and (not obj['found'] or not obj['reading'] or not obj['reading'].strip()):return False
    return True


def propose(baseline, old, result):
    """Return full candidate, disposition; requires exact single literal replacement."""
    if not valid_result(result): return deepcopy(baseline),'pending_or_invalid'
    if not result['found']: return deepcopy(baseline),'not_found'
    reading=result.get('reading')
    if not isinstance(reading,str) or not reading.strip(): return deepcopy(baseline),'empty_reading'
    if not old or baseline['transcription'].count(old)!=1: return deepcopy(baseline),'old_span_not_unique'
    candidate=deepcopy(baseline)
    start=baseline['transcription'].index(old)
    candidate['transcription']=baseline['transcription'].replace(old,reading,1)
    uncertainties=[]
    replacement_flag_added=False
    for u in candidate.get('uncertainties',[]):
        flag=u.get('text','')
        # Selection can expand a reported stem to its split filename suffix.
        # Retire flags wholly covered by that exact replacement, preserving others.
        covered=bool(flag) and baseline['transcription'].count(flag)==1 and start<=baseline['transcription'].index(flag) and baseline['transcription'].index(flag)+len(flag)<=start+len(old)
        if covered:
            if result['difficulty']!='clear' and not replacement_flag_added:
                uncertainties.append({'text':reading,'alternatives':result.get('alternatives',[]),'difficulty':'unreadable' if result['difficulty']=='unreadable' else 'uncertain','reason':result.get('evidence','')})
                replacement_flag_added=True
        else: uncertainties.append(u)
    candidate['uncertainties']=uncertainties
    return candidate,'proposed' if reading!=old else 'same_reading'


def consensus(left,right):
    if not valid_result(left) or not valid_result(right): return None,'pending_or_invalid'
    for obj in (left,right):
        if not obj['found'] or obj['difficulty']!='clear' or not isinstance(obj.get('reading'),str) or not obj['reading'].strip():
            return None,'review_not_both_clear'
    if agreement_key(left['reading'])!=agreement_key(right['reading']): return None,'review_disagreement'
    return deepcopy(left),'accepted_agreement'


def target_reference_status(before, old):
    needle=normalized(old)['tokens'];tokens=before['output_tokens']
    starts=[i for i in range(len(tokens)-len(needle)+1) if needle and tokens[i:i+len(needle)]==needle]
    if len(starts)!=1:return 'unlocatable_normalized_target'
    indices=set(range(starts[0],starts[0]+len(needle)))
    refs=[op['reference_index'] for op in before['operations'] if op['output_index'] in indices and op['reference_index'] is not None]
    if not refs:return 'no_aligned_reference_tokens'
    mask=before['reference_uncertain_mask'];flags=[mask[i] for i in refs]
    return 'unknown_reference_only' if all(flags) else ('mixed_reference_uncertainty' if any(flags) else 'known_reference')


def evaluate(reference,baseline,candidate,old):
    before=score(reference,baseline);after=score(reference,candidate)
    bm,am=before['metrics'],after['metrics']
    delta=am['known_disagreement_operations']-bm['known_disagreement_operations']
    changed=baseline['transcription']!=candidate['transcription']
    status=target_reference_status(before,old)
    outcome=('unknown_reference_unscorable' if changed and status=='unknown_reference_only' else
             'improved' if delta<0 else 'regressed' if delta>0 else 'unchanged')
    return {'outcome':outcome,'target_reference_status':status,'text_changed':changed,'known_word_delta':delta,'full_word_delta':am['full_disagreement_operations']-bm['full_disagreement_operations'], 'before_metrics':bm,'after_metrics':am,'date_match_before':bm['dates_match'],'date_match_after':am['dates_match'], 'date_output_changed':bm['output_dates']!=am['output_dates']}


def cost(parsed_paths):
    metas=[read(Path(str(p).replace('-parsed.json','-metadata.json'))) for p in parsed_paths]
    elapsed=[m['elapsed_seconds'] for m in metas if isinstance(m,dict) and isinstance(m.get('elapsed_seconds'),(int,float))]
    usage=Counter()
    for m in metas:
        if isinstance(m,dict) and isinstance(m.get('usage'),dict):
            usage.update({k:v for k,v in m['usage'].items() if isinstance(v,(int,float))})
    return {'request_components':list(map(str,parsed_paths)),'expected_calls':len(parsed_paths),'timed_calls':len(elapsed),'elapsed_seconds':sum(elapsed) if len(elapsed)==len(parsed_paths) else None,'available_elapsed_seconds':sum(elapsed),'available_usage':dict(usage),'usage_calls':sum(isinstance(m,dict) and isinstance(m.get('usage'),dict) for m in metas)}


def summary(rows):
    evaluated=[r for r in rows if r.get('evaluation')]
    clear=[r for r in evaluated if r.get('clear_accepted')]
    def group(selected):
        timed=[r for r in selected if r['cost']['elapsed_seconds'] is not None]
        return {'evaluated_cells':len(selected),'outcomes':dict(Counter(r['evaluation']['outcome'] for r in selected)), 'known_word_delta_sum':sum(r['evaluation']['known_word_delta'] for r in selected if r['evaluation']['outcome']!='unknown_reference_unscorable'), 'unknown_reference_changes':sum(r['evaluation']['outcome']=='unknown_reference_unscorable' for r in selected),'changed_text_cells':sum(r['evaluation']['text_changed'] for r in selected),'latency_complete_cells':len(timed),'latency_seconds_sum':sum(r['cost']['elapsed_seconds'] for r in timed),'calls_for_latency_complete_cells':sum(r['cost']['expected_calls'] for r in timed)}
    return {'task_cells':len(rows),'available_result_cells':sum(r['result_available'] for r in rows),'pending_cells':sum(not r['result_available'] for r in rows),'all_available_results':group(evaluated),'clear_only_accepted':group(clear),'dispositions':dict(Counter(r['disposition'] for r in rows))}


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root',type=Path,default=ROOT)
    ap.add_argument('--tasks',default='correction/tasks-validated.json')
    ap.add_argument('--runs',default='runs/correction')
    ap.add_argument('--reference',default='codex-reviewed')
    ap.add_argument('--baseline',default='runs/baseline/off')
    ap.add_argument('--output',default=None)
    args=ap.parse_args();root=args.root;out=root/(args.output or args.runs)
    document=read(root/args.tasks)
    if not isinstance(document,dict) or not isinstance(document.get('tasks'),list):
        save(out/'correction-summary.json',{'complete':False,'expected_cells':None,'status':'validated_task_document_missing_or_invalid'})
        print('Validated tasks unavailable; analysis remains pending.');return
    tasks={t['capture']:t for t in document['tasks']}
    if len(tasks)!=len(document['tasks']) or any(n not in range(1,18) for n in tasks):raise ValueError('Duplicate or invalid capture task')
    rows=[];candidate_coverage=[]
    for n in range(1,18):
        task=tasks.get(n);baseline_path=root/(task['baseline'] if task else f'{args.baseline}/capture-{n:02}-parsed.json')
        baseline,baseline_verification,baseline_error=load_completed_output(baseline_path);reference=read(root/args.reference/f'capture-{n:02}.json')
        if not isinstance(baseline,dict) or not isinstance(baseline.get('transcription'),str):
            candidate_coverage.append({'capture':n,'status':'baseline_missing'})
            continue
        if task and task.get('baseline_sha256') and hashlib.sha256(baseline_path.read_bytes()).hexdigest()!=task['baseline_sha256']:
            raise ValueError(f'Frozen baseline hash mismatch capture{n:02}')
        old=(task.get('oldspan') or task.get('old_span') or task.get('text') or '') if task else ''
        loaded={arm:load_completed_output(root/args.runs/arm/f'capture-{n:02}-parsed.json') for arm in ARMS} if task else {}
        results={arm:item[0] for arm,item in loaded.items()}
        combined,consensus_status=consensus(results.get('off-crop'),results.get('low-crop-hints')) if task else (None,'untargeted_baseline')
        for arm in ARMS+[POLICY]:
            relevant=['off-crop','low-crop-hints'] if arm==POLICY else [arm]
            paths=[root/args.runs/a/f'capture-{n:02}-parsed.json' for a in relevant] if task else []
            c=cost([baseline_path]+paths)
            result=combined if arm==POLICY else results.get(arm)
            available=all(valid_result(results.get(a)) for a in relevant) if task else True
            candidate,disposition=propose(baseline,old,result) if task else (deepcopy(baseline),'untargeted_baseline')
            if arm==POLICY and task and combined is None:disposition=consensus_status
            accepted=task is not None and result is not None and result.get('difficulty')=='clear' and disposition in ('proposed','same_reading')
            evaluation=evaluate(reference,baseline,candidate,old) if task and available and reference else None
            row={'capture':n,'partition':'development' if n<=8 else 'heldout','arm':arm,'old_span':old,'result':result,'result_available':available,'disposition':disposition,'clear_accepted':accepted,'evaluation':evaluation,'cost':c,'hints':task.get('hints',[]) if task else [],'completion_provenance':{'baseline':baseline_verification,'corrections':{a:{'verification':loaded[a][1],'error':loaded[a][2]} for a in relevant} if task else {}}}
            if task:rows.append(row)
            variants={arm:candidate}
            if arm!=POLICY:variants[arm+'-clear-only']=candidate if accepted else deepcopy(baseline)
            for name,transcript in variants.items():
                prefix=out/'candidates'/name/f'capture-{n:02}'
                save(Path(str(prefix)+'-parsed.json'),transcript)
                meta={'capture':n,'mode':name,'partition':row['partition'],'targeted':task is not None,'complete':available,'parsed':True,'finish_reason':'stop' if available else None,'synthetic_candidate':True,'finish_reason_scope':'candidate assembly, not a new inference response','source_completion_verification':{'baseline':baseline_verification,'corrections':{a:loaded[a][1] for a in relevant} if task else {}},'disposition':disposition,'clear_accepted':accepted,'candidate_only':True,'baseline':str(baseline_path),'cost':c,'elapsed_seconds':c['elapsed_seconds'],'usage':c['available_usage'],'reference_scoring_available':reference is not None,'note':'Experimental candidate; not applied to notebook. Pending targets preserve baseline.'}
                if name.endswith('-clear-only') and not accepted:meta['disposition']='baseline_retained_'+disposition
                save(Path(str(prefix)+'-metadata.json'),meta)
        candidate_coverage.append({'capture':n,'status':'generated','targeted':task is not None})
    expected=len(tasks)*len(ARMS)
    available=sum(r['result_available'] for r in rows if r['arm']!=POLICY)
    rejected=[]
    for row in rows:
        if row['arm']==POLICY or row['result_available']:continue
        path=root/args.runs/row['arm']/f"capture-{row['capture']:02}-metadata.json"
        meta=read(path)
        if meta and meta.get('complete') and meta.get('parsed') is False:
            rejected.append({'capture':row['capture'],'arm':row['arm'],'reason':meta.get('parse_error'),'metadata':str(path)})
    summaries={arm:{split:summary([r for r in rows if r['arm']==arm and (split=='all' or r['partition']==split)]) for split in ['development','heldout','all']} for arm in ARMS+[POLICY]}
    payload={'method':METHOD,'expected_cells':expected,'available_cells':available,'complete':available==expected and len(candidate_coverage)==17 and all(x['status']=='generated' for x in candidate_coverage),'task_count':len(tasks),'summaries':summaries,'candidate_coverage':candidate_coverage,'cells':rows,'tasks_sha256':hashlib.sha256((root/args.tasks).read_bytes()).hexdigest()}
    payload.update(rejected_completed_cells=rejected,all_attempts_finished=available+len(rejected)==expected)
    save(out/'correction-summary.json',payload)
    status=('complete.' if payload['complete'] else f"All requests finished; {len(rejected)} completed response(s) rejected by schema validation." if payload['all_attempts_finished'] else 'PARTIAL. Pending responses are not scored as unchanged.')
    lines=['# Crop correction experiment analysis','',f'Correction result coverage: **{available}/{expected}** usable cells; '+status,'',METHOD,'','| Arm | Split | Available/evaluated | Improved / regressed / unchanged / unknown | Known-word delta | Clear accepted | Timed cells / total seconds |','|---|---|---:|---:|---:|---:|---:|']
    for arm,splits in summaries.items():
        for split,s in splits.items():
            g=s['all_available_results'];d=g['outcomes'];cl=s['clear_only_accepted']
            lines.append(f"| {arm} | {split} | {s['available_result_cells']}/{g['evaluated_cells']} | {d.get('improved',0)} / {d.get('regressed',0)} / {d.get('unchanged',0)} / {d.get('unknown_reference_unscorable',0)} | {g['known_word_delta_sum']:+} | {cl['evaluated_cells']} | {g['latency_complete_cells']} / {g['latency_seconds_sum']:.2f} |")
    lines+=['','Full candidate transcripts and request-cost metadata are under `candidates/`. JSON summary includes clear-only outcome counts and deltas separately, exact proposals, pending dispositions, date comparisons, and coverage. Baseline/clear-only/consensus copies are experiment artifacts, not accepted journal content.','']
    if rejected:
        lines+=['Rejected completed responses remain preserved and were not retried inside this comparison:']+[f"- Capture {r['capture']:02}, {r['arm']}: {r['reason']}" for r in rejected]+['']
    (out/'CORRECTION-ANALYSIS.md').write_text('\n'.join(lines))
    print(f'Analyzed {available}/{expected} correction cells; {out / "CORRECTION-ANALYSIS.md"}')

if __name__=='__main__':main()
