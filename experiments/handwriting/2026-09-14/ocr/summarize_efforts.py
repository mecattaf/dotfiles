#!/usr/bin/env python3
"""Summarize measured thinking/memory data without claiming OCR accuracy."""
import json
import statistics
import subprocess
import sys
from pathlib import Path

from baseline import ROOT, save


def load(path):
    return json.loads(path.read_text())


def resources(samples):
    if not samples:
        raise ValueError('No telemetry in request window')
    result={'samples':len(samples)}
    for key in ['gpu_busy_percent','mem_info_gtt_used_bytes','mem_info_vram_used_bytes']:
        vals=[s[key] for s in samples if s.get(key) is not None]
        result[key]={'min':min(vals),'max':max(vals),'mean':statistics.mean(vals),'median':statistics.median(vals)}
    for group in ['engines','frontends']:
        vals=[sum(p.get('VmRSS_bytes',0) for p in s.get(group,{}).values()) for s in samples]
        result[group+'_rss_bytes']={'min':min(vals),'max':max(vals),'median':statistics.median(vals)}
    for key in ['system_used_bytes','ttm_used_bytes']:
        vals=[s['kfd_memory'][key] for s in samples if s.get('kfd_memory') and key in s['kfd_memory']]
        if vals:
            result['kfd_'+key]={'min':min(vals),'max':max(vals),'median':statistics.median(vals)}
    return result


def main():
    run=Path(sys.argv[1]).resolve()
    samples=[json.loads(l) for l in (run/'memory-samples.jsonl').read_text().splitlines()]
    idle=load(run/'idle-window.json')
    idle_resource=resources([s for s in samples if idle['start_ns']<=s['received_monotonic_ns']<=idle['end_ns']])
    summary={'idle':idle_resource,'modes':{}}
    for mode in load(run/'protocol.json')['modes']:
        folder=run/mode
        subprocess.run([sys.executable,str(ROOT/'compare_baseline.py'),str(folder)],check=True,stdout=subprocess.DEVNULL)
        comparison=load(folder/'comparison.json')
        rows=[]
        for meta_path in sorted(folder.glob('*-metadata.json')):
            meta=load(meta_path)
            span=[s for s in samples if meta['start_monotonic_ns']<=s['received_monotonic_ns']<=meta['end_monotonic_ns']]
            meta['resources']=resources(span)
            rows.append(meta)
        normal=[r for r in rows if not r['page_id'].endswith('-large')]
        summary['modes'][mode]={'requests':rows,'seconds':sum(r['elapsed_seconds'] for r in normal),'reasoning_tokens':sum(r['usage']['completion_tokens_details']['reasoning_tokens'] for r in normal),'completion_tokens':sum(r['usage']['completion_tokens'] for r in normal),'cached_requests':sum(r['timings'].get('cache_n',0)>0 for r in normal),'word_disagreements':comparison['word_edits'],'character_disagreements':comparison['character_edits'],'astra_words':comparison['astra_word_count'],'gpu_busy_mean_percent':statistics.mean(s['gpu_busy_percent'] for r in normal for s in samples if r['start_monotonic_ns']<=s['received_monotonic_ns']<=r['end_monotonic_ns']),'peak_gtt_bytes':max(r['resources']['mem_info_gtt_used_bytes']['max'] for r in normal),'peak_engine_rss_bytes':max(r['resources']['engines_rss_bytes']['max'] for r in normal)}
    save(run/'summary.json',summary)
    for mode,stats in summary['modes'].items():
        print(mode,json.dumps({k:v for k,v in stats.items() if k!='requests'}))


if __name__=='__main__':
    main()
