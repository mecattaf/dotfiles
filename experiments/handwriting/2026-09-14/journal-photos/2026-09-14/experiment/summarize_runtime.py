#!/usr/bin/env python3
"""Summarize serial OCR experiments without retaining memory samples in RAM.

All time matching uses coordinator received_monotonic_ns, never the worker's
wall clock. Metrics are overlapping observations, not additive allocations.
"""
import argparse
from bisect import bisect_right
from collections import Counter
from datetime import datetime, timezone
import json
from pathlib import Path
from statistics import median

ROOT = Path(__file__).resolve().parents[1]
MEMORY_KEYS = ('kfd_system', 'kfd_ttm', 'gtt', 'vram', 'engine_rss',
               'frontend_rss', 'host_mem_total', 'host_mem_available')
MODE_ORDER = ('off', 'low', 'medium', 'xhigh')


def quantity(value):
    if value is None:
        return None
    return {'bytes': value, 'GB': value / 1e9, 'GiB': value / 2**30}


class Stats:
    def __init__(self):
        self.count = 0
        self.values = {}
        self.first_ns = None
        self.last_ns = None

    def add(self, sample):
        stamp = sample['received_monotonic_ns']
        self.count += 1
        self.first_ns = stamp if self.first_ns is None else min(self.first_ns, stamp)
        self.last_ns = stamp if self.last_ns is None else max(self.last_ns, stamp)
        for key, value in metrics(sample).items():
            if value is None:
                continue
            if key not in self.values:
                self.values[key] = {'count': 0, 'sum': 0, 'min': value, 'max': value,
                                    'last': value, 'last_ns': stamp}
            row = self.values[key]
            row['count'] += 1
            row['sum'] += value
            row['min'] = min(row['min'], value)
            row['max'] = max(row['max'], value)
            if stamp >= row['last_ns']:
                row['last'], row['last_ns'] = value, stamp

    def export(self):
        return {'samples': self.count, 'first_received_ns': self.first_ns,
                'last_received_ns': self.last_ns,
                'metrics': {key: {'samples': v['count'], **{
                    name: (quantity(value) if key in MEMORY_KEYS else value)
                    for name, value in [('min', v['min']), ('max', v['max']),
                                        ('mean', v['sum']/v['count']), ('last', v['last'])]}}
                            for key, v in self.values.items()}}


def metrics(s):
    kfd = s.get('kfd_memory') or {}
    host = s.get('host_memory') or {}
    def rss(kind):
        values = [v.get('VmRSS_bytes') for v in (s.get(kind) or {}).values()]
        # Missing all processes is unknown, not a measured zero.
        values = [v for v in values if isinstance(v, (int, float))]
        return sum(values) if values else None
    return {'kfd_system': kfd.get('system_used_bytes'),
            'kfd_ttm': kfd.get('ttm_used_bytes'),
            'gtt': s.get('mem_info_gtt_used_bytes'),
            'vram': s.get('mem_info_vram_used_bytes'),
            'engine_rss': rss('engines'), 'frontend_rss': rss('frontends'),
            'host_mem_total': host.get('MemTotal_bytes'),
            'host_mem_available': host.get('MemAvailable_bytes'),
            'gpu_busy_percent': s.get('gpu_busy_percent')}


def delta(peak, idle):
    answer = {}
    for key in MEMORY_KEYS:
        if key in peak.values and key in idle.values:
            p, b = peak.values[key], idle.values[key]
            mean = b['sum'] / b['count']
            answer[key] = {'idle_mean': quantity(mean),
                           'peak_minus_idle_mean': quantity(p['max']-mean)}
            if key == 'host_mem_available':
                answer[key]['idle_mean_minus_minimum_available'] = quantity(mean-p['min'])
    return answer


def read_object(path, warnings):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError) as exc:
        warnings.append(f'{path.name}: {exc}')
        return None


def windows(paths, warnings):
    result = []
    for path in paths:
        if path.suffix == '.jsonl':
            with path.open() as f:
                objects = []
                for line_no, line in enumerate(f, 1):
                    try:
                        objects.append(json.loads(line))
                    except ValueError:
                        warnings.append(f'{path.name}:{line_no}: invalid JSON window')
        else:
            obj = read_object(path, warnings)
            objects = obj if isinstance(obj, list) else [obj]
        for obj in objects:
            if not isinstance(obj, dict):
                continue
            start = obj.get('start_ns', obj.get('start_monotonic_ns'))
            end = obj.get('end_ns', obj.get('end_monotonic_ns'))
            if not isinstance(start, int) or not isinstance(end, int) or end < start:
                warnings.append(f'{path.name}: incomplete idle window ignored')
                continue
            result.append({'source': path.name, 'start_ns': start, 'end_ns': end,
                           'stats': Stats()})
    return sorted(result, key=lambda x: x['start_ns'])


def summarize(folder, expected=68):
    warnings, requests = [], []
    metadata_paths = sorted(folder.glob('*/*-metadata.json'))
    for path in metadata_paths:
        obj = read_object(path, warnings)
        if not isinstance(obj, dict):
            continue
        usage, timings = obj.get('usage') or {}, obj.get('timings') or {}
        completion = usage.get('completion_tokens')
        reasoning = (usage.get('completion_tokens_details') or {}).get('reasoning_tokens')
        # Missing reasoning field is unknown rather than invented zero.
        output = completion-reasoning if completion is not None and reasoning is not None else None
        requests.append({'source': str(path.relative_to(folder)),
                         'capture': obj.get('capture'), 'mode': obj.get('mode', path.parent.name),
                         'physical_page': obj.get('physical_page'),
                         'complete': obj.get('complete', False), 'parsed': obj.get('parsed'),
                         'parse_error': obj.get('parse_error'), 'finish_reason': obj.get('finish_reason'),
                         'wall_seconds': obj.get('elapsed_seconds'),
                         'prompt_tokens': usage.get('prompt_tokens'),
                         'completion_tokens': completion, 'reasoning_tokens': reasoning,
                         'output_tokens': output, 'image_tokens': obj.get('image_tokens'),
                         'cache_n': timings.get('cache_n'), 'timings': timings,
                         'start_ns': obj.get('start_monotonic_ns'),
                         'end_ns': obj.get('end_monotonic_ns'), 'stats': Stats()})
    requests.sort(key=lambda r: (r['start_ns'] or 0, r['source']))
    valid = [r for r in requests if isinstance(r['start_ns'], int)
             and isinstance(r['end_ns'], int) and r['end_ns'] >= r['start_ns']]
    for previous, current in zip(valid, valid[1:]):
        if previous['end_ns'] > current['start_ns']:
            raise ValueError('Request windows overlap; this summarizer expects a serial benchmark')
    starts = [r['start_ns'] for r in valid]
    idle = windows(sorted(set(folder.glob('idle*.json')) | set(folder.glob('idle*.jsonl'))
                          | set(folder.glob('final-idle*.json')) | set(folder.glob('final-idle*.jsonl'))), warnings)
    all_stats, active_stats = Stats(), Stats()
    mode_stats = {m: Stats() for m in {r['mode'] for r in requests}}
    lines, invalid_lines, untimed_lines = 0, 0, 0
    files = sorted(folder.glob('memory*.jsonl'))
    # One streaming pass over samples. Memory use scales with request/window count.
    for path in files:
        with path.open() as f:
            for line in f:
                lines += 1
                try:
                    sample = json.loads(line)
                except ValueError:
                    invalid_lines += 1
                    continue
                stamp = sample.get('received_monotonic_ns') if isinstance(sample, dict) else None
                if not isinstance(stamp, int):
                    untimed_lines += 1
                    continue
                all_stats.add(sample)
                index = bisect_right(starts, stamp) - 1
                if index >= 0 and stamp <= valid[index]['end_ns']:
                    row = valid[index]
                    row['stats'].add(sample)
                    active_stats.add(sample)
                    mode_stats[row['mode']].add(sample)
                for window in idle:
                    if window['start_ns'] <= stamp <= window['end_ns']:
                        window['stats'].add(sample)
    for row in requests:
        candidates = [w for w in idle if row['start_ns'] is not None
                      and w['end_ns'] <= row['start_ns'] and w['stats'].count]
        baseline = max(candidates, key=lambda w: w['end_ns']) if candidates else None
        row['memory'] = row.pop('stats')
        row['idle_reference'] = baseline['source'] if baseline else None
        row['idle_to_peak'] = delta(row['memory'], baseline['stats']) if baseline else None
        row['memory'] = row['memory'].export()
    groups = {}
    for mode in sorted(mode_stats, key=lambda m: MODE_ORDER.index(m) if m in MODE_ORDER else 99):
        rows = [r for r in requests if r['mode'] == mode]
        times = [r['wall_seconds'] for r in rows if r['wall_seconds'] is not None]
        sums = {}
        for key in ['prompt_tokens', 'completion_tokens', 'reasoning_tokens', 'output_tokens', 'cache_n']:
            vals = [r[key] for r in rows if r[key] is not None]
            sums[key] = {'sum': sum(vals), 'known_requests': len(vals)}
        groups[mode] = {'requests': len(rows), 'complete': sum(r['complete'] for r in rows),
                        'parse_failures': sum(r['parsed'] is False for r in rows),
                        'parse_unknown': sum(r['parsed'] is None for r in rows),
                        'finish_reasons': dict(Counter(r['finish_reason'] or 'unknown' for r in rows)),
                        'wall_seconds': {'sum': sum(times), 'mean': sum(times)/len(times) if times else None,
                                         'median': median(times) if times else None,
                                         'min': min(times) if times else None, 'max': max(times) if times else None},
                        'tokens': sums, 'cache_hit_requests': sum((r['cache_n'] or 0) > 0 for r in rows),
                        'memory': mode_stats[mode].export()}
    pending = [str(p.relative_to(folder)) for p in sorted(folder.glob('*/*-request.json'))
               if not p.with_name(p.name.replace('-request.json', '-metadata.json')).exists()]
    last_end = max((r['end_ns'] for r in valid), default=None)
    # A silent tail is not established idle. Require an explicit sampled idle window.
    final_idle = [w for w in idle if last_end is not None and w['start_ns'] >= last_end and w['stats'].count]
    initial_idle = [w for w in idle if starts and w['end_ns'] <= starts[0] and w['stats'].count]
    baseline = initial_idle[0] if initial_idle else None
    result = {'generated_utc': datetime.now(timezone.utc).isoformat(), 'folder': str(folder),
              'expected_requests': expected, 'metadata_requests': len(requests),
              'complete_requests': sum(r['complete'] for r in requests),
              'all_expected_complete': len(requests) == expected and all(r['complete'] for r in requests),
              'pending_request_files': pending, 'warnings': warnings,
              'memory_scan': {'files': [p.name for p in files], 'lines': lines,
                              'invalid_json_lines': invalid_lines, 'missing_time_lines': untimed_lines,
                              'matching_clock': 'received_monotonic_ns on coordinator',
                              'all_observed': all_stats.export(), 'request_windows': active_stats.export(),
                              'initial_idle_reference': baseline['source'] if baseline else None,
                              'initial_idle_to_active_peak': delta(active_stats, baseline['stats']) if baseline else None,
                              'final_idle': [{'source': w['source'], 'stats': w['stats'].export()} for w in final_idle] or None},
              'idle_windows': [{**{k: v for k, v in w.items() if k != 'stats'}, 'stats': w['stats'].export()} for w in idle],
              'modes': groups, 'requests': requests,
              'caveats': ['Memory metrics overlap. Do not add KFD, TTM, GTT, VRAM and process RSS.',
                          'KFD system usage is driver accounting, not host anonymous RAM. MemAvailable includes reclaimable memory and is not a safe GPU allocation budget.',
                          'Engine/frontend RSS sums processes within each category; shared mappings may overlap even within a category.',
                          'Peaks are sampled observations, not continuous maxima. SSH receive time introduces sampling/transport uncertainty.',
                          'Output tokens equal completion minus reasoning tokens; absent fields remain unknown.',
                          'Requests are exploratory single observations with uncontrolled warm cache; latency differences are not pure thinking-level effects.',
                          'No final idle is claimed without an explicit idle measurement window after requests.']}
    return result


def fmt(n, digits=2):
    return '—' if n is None else f'{n:,.{digits}f}'


def memory_value(stats, key, which):
    return stats.get('metrics', {}).get(key, {}).get(which)


def report(s):
    out = ['# Journal OCR runtime and memory', '',
           f"Snapshot: {s['complete_requests']}/{s['expected_requests']} requests complete; "
           f"{len(s['pending_request_files'])} request file(s) awaiting metadata. "
           f"Generated {s['generated_utc']}.", '',
           'One photo per request, serial processing. Partial snapshots are not a balanced mode comparison.', '',
           '| Thinking | Done / saved | Total s | Mean s | Median s | Reasoning tokens | Output tokens | Cache hits | Parse failures | Finish reasons |',
           '|---|---:|---:|---:|---:|---:|---:|---:|---:|---|']
    for mode, row in s['modes'].items():
        totals = row['tokens']
        def total(key):
            x = totals[key]
            return str(x['sum']) if x['known_requests'] == row['requests'] else f"{x['sum']} ({x['known_requests']} known)"
        out.append(f"| {mode} | {row['complete']} / {row['requests']} | {fmt(row['wall_seconds']['sum'])} | {fmt(row['wall_seconds']['mean'])} | {fmt(row['wall_seconds']['median'])} | {total('reasoning_tokens')} | {total('output_tokens')} | {row['cache_hit_requests']} | {row['parse_failures']} | {row['finish_reasons']} |")
    scan = s['memory_scan']
    out += ['', 'Memory units below are **decimal GB / binary GiB**. Each row is a separate, overlapping accounting view; do not sum them.', '',
            '| Metric | Initial idle mean | Active peak | Peak − idle | Active minimum | Last observed sample | Final idle mean |',
            '|---|---:|---:|---:|---:|---:|---:|']
    baseline = next((w['stats'] for w in s['idle_windows'] if w['source'] == scan['initial_idle_reference']), {})
    def units(x):
        return '—' if x is None else f"{x['GB']:.3f} / {x['GiB']:.3f}"
    changes = scan['initial_idle_to_active_peak'] or {}
    final_idle_stats = scan['final_idle'][-1]['stats'] if scan['final_idle'] else {}
    for key in MEMORY_KEYS:
        out.append(f"| {key} | {units(memory_value(baseline,key,'mean'))} | {units(memory_value(scan['request_windows'],key,'max'))} | {units(changes.get(key,{}).get('peak_minus_idle_mean'))} | {units(memory_value(scan['request_windows'],key,'min'))} | {units(memory_value(scan['all_observed'],key,'last'))} | {units(memory_value(final_idle_stats,key,'mean'))} |")
    gpu = scan['request_windows'].get('metrics', {}).get('gpu_busy_percent', {})
    idle_gpu = baseline.get('metrics', {}).get('gpu_busy_percent', {})
    out += ['', f"GPU busy: active mean {fmt(gpu.get('mean'))}%, observed peak {fmt(gpu.get('max'))}%; initial idle mean {fmt(idle_gpu.get('mean'))}%.",
            f"Memory samples: {scan['lines']:,} scanned once; {scan['request_windows']['samples']:,} fall inside completed metadata request windows; {scan['invalid_json_lines']} invalid/unfinished JSON lines skipped.",
            'Final idle: explicit post-request measurement available in JSON.' if scan['final_idle'] else 'Final idle: **not measured**. The last observed sample is not asserted to be idle.', '',
            'KFD system usage is driver accounting. Host MemAvailable includes reclaimable memory and cannot be treated as a safe GPU allocation budget. Peaks are sampled; these columns may reach maxima at different times.', '',
            '| Capture | Mode | Wall s | Prompt | Completion | Thinking | Output | cache_n | Finish | Parsed | Samples |',
            '|---:|---|---:|---:|---:|---:|---:|---:|---|---|---:|']
    for r in sorted(s['requests'], key=lambda r: (r['capture'] or 0, MODE_ORDER.index(r['mode']) if r['mode'] in MODE_ORDER else 99)):
        values = [r['capture'],r['mode'],fmt(r['wall_seconds']),r['prompt_tokens'],r['completion_tokens'],r['reasoning_tokens'],r['output_tokens'],r['cache_n'],r['finish_reason'],r['parsed'],r['memory']['samples']]
        out.append('| '+' | '.join('—' if v is None else str(v) for v in values)+' |')
    out += ['', 'Full per-request memory peaks, idle deltas, cache/timing counters and known-field counts are in `runtime-summary.json`.', '',
            'Cache state was retained and mode order rotated across captures. Single observations include cache effects and do not isolate thinking effort. These measurements establish operational cost, not OCR accuracy.']
    if s['warnings']:
        out += ['', 'Read warnings:', ''] + ['- '+w for w in s['warnings']]
    return '\n'.join(out)+'\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, default=ROOT/'runs/baseline')
    parser.add_argument('--expected', type=int, default=68)
    args = parser.parse_args()
    result = summarize(args.input, args.expected)
    for filename, text in [('runtime-summary.json', json.dumps(result, ensure_ascii=False, indent=2)+'\n'),
                           ('RUNTIME.md', report(result))]:
        target = args.input/filename
        temporary = target.with_suffix(target.suffix+'.tmp')
        temporary.write_text(text)
        temporary.replace(target)
    print(f"{result['complete_requests']}/{result['expected_requests']} complete; scanned {result['memory_scan']['lines']} samples; wrote {args.input/'RUNTIME.md'}")


if __name__ == '__main__':
    main()
