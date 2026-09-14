#!/usr/bin/env python3
"""Disposable OCR disagreement audit. No inference; never edits source evidence."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import unicodedata

ROOT = Path(__file__).resolve().parents[1]
DATE = re.compile(r'(?<!\w)(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})(?!\w)')
WORD = re.compile(r"[^\W_]+(?:['’][^\W_]+)*", re.UNICODE)
METHOD = '''This is normalized word disagreement against a reviewed Codex reading, NOT author-confirmed OCR accuracy. Reference and model both ignore letter case, punctuation, line wraps, legible ~~crossouts~~, and explicit editorial annotations. Meaningful boxed/margin text is retained after removing its editorial label. Cropped-bottom editorial placeholders are omitted. Unicode is NFKC-normalized; apostrophes inside words disappear; punctuation separates words; thousands separators are removed from numeric groups. Standalone x/X immediately after a line-leading item number is ignored only when followed by a word and supported by a neighboring consecutive numbered item; it represents the photographed crossed/star list marker. Attached multiplicative forms (7x Appliances), numeric multiplication (15 x5 or 15 x 5), isolated ambiguous x forms, and in-prose x are retained. Dates of form DD/MM/YY (also dots/hyphens) are extracted and compared separately, with component order retained; their positions do not affect word alignment.

Full disagreement uses the first candidate of each [unclear: a | b] reference annotation. A unit-cost Levenshtein alignment reports substitutions, deletions, insertions, and matches. Ties prefer diagonal, then deletion, then insertion. The known-word measure excludes substitutions/deletions on uncertain reference tokens and insertions anchored immediately beside an uncertain reference token. Its denominator is certain reference tokens. This is a conservative uncertainty exclusion on that same alignment, NOT an independent estimate of accuracy; uncertain regions can affect alignment and insertion attribution. [illegible] is an uncertain reference placeholder. Remaining unflagged reference mistakes can affect every score.

Model uncertainty spans are located as normalized contiguous token sequences in the model output. Only uniquely located sequences count as exact-span flags; repeated/absent/empty spans are reported separately rather than optimistically flagging every occurrence. Substitution/insertion operations with an output token inside such a span count as directly flagged. Deletions have no output token and cannot be directly flagged; adjacent flagged output tokens are reported separately. Self-reported difficulty is not a calibrated probability. Capture01–08 is development;09–17 is held out on disjoint physical pages. These reports do not tune any recipe on held-out pages. Overlapping photographs remain separate captures, so aggregate counts include some repeated notebook text.
'''


def strip_numbered_list_crosses(raw):
    """Ignore handwritten x-shaped list markers only in consecutive numbered lists."""
    cross = re.compile(r'^(?P<prefix>[ \t]*(?P<n>\d{1,3})[ \t]+)[xX][ \t]+(?=[\"“‘\']*[^\W\d_])', re.M)
    candidates = list(cross.finditer(raw))
    # A conventional period/parenthesis/star item can establish list continuity too.
    numbered = {int(m.group(1)) for m in re.finditer(r'^[ \t]*(\d{1,3})(?:[.)][ \t]+|[ \t]+[*×✕✖][ \t]+)',raw,re.M)}
    numbered.update(int(m.group('n')) for m in candidates)
    def replace(m):
        n=int(m.group('n'))
        return m.group('prefix') if n-1 in numbered or n+1 in numbered else m.group(0)
    return cross.sub(replace,raw)


def normalized(raw):
    """Return words, reference-uncertainty mask, dates, and cleaned text."""
    raw = strip_numbered_list_crosses(unicodedata.normalize('NFKC', raw))
    raw = re.sub(r'~~.*?~~', ' ', raw, flags=re.S)
    # Innermost bracket substitution preserves ordinary source brackets around text.
    unknown_markers = []
    def bracket(m):
        value = m.group(1).strip()
        lower = value.casefold()
        if lower.startswith('unclear:'):
            candidate = value.split(':', 1)[1].split('|', 1)[0].strip()
            # Semicolon text in these annotations is an editorial qualification.
            candidate = candidate.split(';', 1)[0].strip()
            key = f'\ue000{len(unknown_markers)}\ue001'
            unknown_markers.append(candidate or 'illegible')
            return key
        if lower in ('illegible', 'unreadable'):
            key = f'\ue000{len(unknown_markers)}\ue001'
            unknown_markers.append('illegible')
            return key
        if (re.match(r'(bottom|top)\b', lower) or
            re.match(r'(crossed[ -]out|corrected from|inserted below|unit corrected|continues beyond|side note[, :])', lower) or
            ('cropped' in lower and lower.startswith('margin'))):
            return ' '
        if re.match(r'(boxed|margin addition|boxed margin note|margin note|side note)\s*:', lower):
            return value.split(':', 1)[1]
        return value
    # Several passes permit a literal outer bracket containing an unclear annotation.
    while re.search(r'\[[^\[\]]*\]', raw):
        raw = re.sub(r'\[([^\[\]]*)\]', bracket, raw)
    dates = []
    def date(m):
        dates.append('/'.join(str(int(x)) for x in m.groups()))
        return ' '
    raw = DATE.sub(date, raw)
    # Number grouping: 144 000 and 3,456,000 each form one number.
    raw = re.sub(r'(?<!\w)\d{1,3}(?:[ ,\u00a0]\d{3})+(?!\d)', lambda m: re.sub(r'[ ,\u00a0]', '', m.group()), raw)
    words, uncertain = [], []
    for part in re.split(r'(\ue000\d+\ue001)', raw):
        marker = re.fullmatch(r'\ue000(\d+)\ue001', part)
        is_unknown = bool(marker)
        value = unknown_markers[int(marker.group(1))] if marker else part
        tokens = [re.sub("['’]", '', x.casefold()) for x in WORD.findall(value)]
        if is_unknown and not tokens:
            tokens = ['illegible']
        words.extend(tokens)
        uncertain.extend([is_unknown] * len(tokens))
    return {'tokens': words, 'uncertain': uncertain, 'dates': dates, 'cleaned_text': raw}


def align(reference, hypothesis):
    """Unit-cost Levenshtein, explicit deterministic operations with zero-based spans."""
    n, m = len(reference), len(hypothesis)
    dp = [list(range(m+1))]
    for i in range(1, n+1):
        row = [i]
        for j in range(1, m+1):
            row.append(min(dp[i-1][j-1] + (reference[i-1] != hypothesis[j-1]), dp[i-1][j]+1, row[-1]+1))
        dp.append(row)
    ops = []
    i, j = n, m
    while i or j:
        if i and j and dp[i][j] == dp[i-1][j-1] + (reference[i-1] != hypothesis[j-1]):
            ops.append({'operation': 'match' if reference[i-1] == hypothesis[j-1] else 'substitute', 'reference_index':i-1, 'output_index':j-1, 'reference':reference[i-1], 'output':hypothesis[j-1]})
            i -= 1; j -= 1
        elif i and dp[i][j] == dp[i-1][j]+1:
            ops.append({'operation':'delete', 'reference_index':i-1, 'output_index':None, 'output_gap':j, 'reference':reference[i-1], 'output':None})
            i -= 1
        else:
            ops.append({'operation':'insert', 'reference_index':None, 'reference_gap':i, 'output_index':j-1, 'reference':None, 'output':hypothesis[j-1]})
            j -= 1
    return list(reversed(ops))


def locate_flags(output_tokens, uncertainties):
    locations, flagged = [], set()
    for item in uncertainties:
        needle = normalized(str(item.get('text','')))['tokens']
        starts = [i for i in range(len(output_tokens)-len(needle)+1) if needle and output_tokens[i:i+len(needle)] == needle]
        row = {'text':item.get('text',''), 'difficulty':item.get('difficulty', item.get('severity','unknown')), 'normalized_tokens':needle, 'candidate_token_spans':[[i,i+len(needle)] for i in starts], 'location_status':'unique' if len(starts)==1 else ('ambiguous_repetition' if starts else 'unmatched')}
        if len(starts)==1:
            flagged.update(range(starts[0], starts[0]+len(needle)))
        locations.append(row)
    return locations, flagged


def score(reference_obj, output_obj):
    ref, hyp = normalized(reference_obj['transcription']), normalized(output_obj['transcription'])
    ops = align(ref['tokens'], hyp['tokens'])
    locations, flagged = locate_flags(hyp['tokens'], output_obj.get('uncertainties',[]))
    counts, known = Counter(), Counter()
    direct = Counter()
    neighboring_deletions = 0
    for op in ops:
        kind, ri, hi = op['operation'], op['reference_index'], op['output_index']
        if ri is not None:
            excluded = ref['uncertain'][ri]
        else:
            gap = op['reference_gap']
            excluded = any(ref['uncertain'][k] for k in (gap-1,gap) if 0 <= k < len(ref['tokens']))
        op['excluded_from_known_word_measure'] = excluded
        op['directly_flagged'] = hi is not None and hi in flagged
        if kind == 'delete':
            gap = op['output_gap']
            op['neighbor_flagged'] = any(k in flagged for k in (gap-1,gap))
            if not excluded and op['neighbor_flagged']:
                neighboring_deletions += 1
        counts[kind] += 1
        if not excluded:
            known[kind] += 1
            if kind != 'match' and op['directly_flagged']:
                direct[kind] += 1
    error = sum(counts[k] for k in ('substitute','delete','insert'))
    known_error = sum(known[k] for k in ('substitute','delete','insert'))
    known_n = sum(not x for x in ref['uncertain'])
    ref_dates = ref['dates']
    visible = reference_obj.get('visible_date')
    if visible and not ref_dates:
        ref_dates = normalized(str(visible))['dates']
    return {'reference_tokens':ref['tokens'], 'reference_uncertain_mask':ref['uncertain'], 'output_tokens':hyp['tokens'], 'operations':ops,
            'differences':[x for x in ops if x['operation'] != 'match'], 'uncertainty_locations':locations,
            'metrics':{'reference_words':len(ref['tokens']), 'output_words':len(hyp['tokens']), 'uncertain_reference_words':sum(ref['uncertain']), 'full_operations':dict(counts), 'full_disagreement_operations':error, 'full_disagreement_rate':error/len(ref['tokens']) if ref['tokens'] else None, 'known_reference_words':known_n, 'known_operations':dict(known), 'known_disagreement_operations':known_error, 'known_disagreement_rate':known_error/known_n if known_n else None, 'known_differences_directly_flagged':sum(direct.values()), 'known_directly_flagged_by_operation':dict(direct), 'known_deletions_with_flagged_neighbor':neighboring_deletions, 'uncertainty_counts':dict(Counter(x['difficulty'] for x in locations)), 'uncertainty_location_counts':dict(Counter(x['location_status'] for x in locations)), 'reference_dates':ref_dates, 'output_dates':hyp['dates'], 'dates_match':sorted(ref_dates)==sorted(hyp['dates'])}}


def aggregate(rows):
    out = {'captures':len(rows)}
    fields = ['reference_words','output_words','uncertain_reference_words','full_disagreement_operations','known_reference_words','known_disagreement_operations','known_differences_directly_flagged','known_deletions_with_flagged_neighbor']
    for key in fields:
        out[key] = sum(x['metrics'][key] for x in rows)
    for key in ['full_operations','known_operations','uncertainty_counts','uncertainty_location_counts']:
        counter = Counter()
        for row in rows: counter.update(row['metrics'][key])
        out[key] = dict(counter)
    for prefix, denominator in [('full','reference_words'),('known','known_reference_words')]:
        out[prefix+'_disagreement_rate'] = out[prefix+'_disagreement_operations']/out[denominator] if out[denominator] else None
    out['date_mismatch_captures'] = [x['capture'] for x in rows if not x['metrics']['dates_match']]
    return out


def save(path, data):
    path.parent.mkdir(parents=True,exist_ok=True)
    temp = path.with_suffix(path.suffix+'.tmp')
    temp.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    temp.replace(path)


def load_completed_output(parsed_path):
    """Refuse stale parsed artifacts when a present metadata record is not successful."""
    metadata_path = Path(str(parsed_path).replace('-parsed.json','-metadata.json'))
    verification = 'unverified_metadata_absent'
    if metadata_path.exists():
        try:
            meta = json.loads(metadata_path.read_text())
        except (ValueError,OSError):
            return None, None, 'malformed_completion_metadata'
        if not isinstance(meta,dict) or meta.get('complete') is not True or meta.get('parsed') is not True or meta.get('finish_reason') != 'stop':
            return None, None, 'incomplete_or_unsuccessful_metadata'
        verification = 'synthetic_candidate_metadata' if meta.get('synthetic_candidate') is True else 'verified_success_metadata'
    try:
        obj = json.loads(parsed_path.read_text())
    except (ValueError,OSError):
        return None, None, 'missing_or_invalid_parsed_output'
    return obj, verification, None


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root', type=Path, default=ROOT)
    ap.add_argument('--reference', default='codex-reviewed')
    ap.add_argument('--runs', default='runs/baseline')
    ap.add_argument('--output', default='runs/baseline/quality')
    ap.add_argument('--modes', default='off,low,medium,xhigh', help='Comma-separated run subdirectories; custom arm names allowed')
    ap.add_argument('--captures', default=','.join(map(str, range(1,18))), help='Comma-separated capture numbers, from 1 through 17')
    args = ap.parse_args()
    modes = [x.strip() for x in args.modes.split(',')]
    if not modes or any(not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', x) for x in modes) or len(set(modes)) != len(modes):
        ap.error('--modes requires unique, nonempty directory names without path separators')
    try:
        captures = [int(x.strip()) for x in args.captures.split(',')]
    except ValueError:
        ap.error('--captures requires comma-separated integers')
    if not captures or any(x < 1 or x > 17 for x in captures) or len(set(captures)) != len(captures):
        ap.error('--captures requires unique capture numbers from 1 through 17')
    expected_cells = len(modes) * len(captures)
    refs, runs, out = args.root/args.reference, args.root/args.runs, args.root/args.output
    out.mkdir(parents=True,exist_ok=True)
    rows, missing = [], []
    for mode in modes:
        for capture in captures:
            rp = refs/f'capture-{capture:02}.json'
            hp = runs/mode/f'capture-{capture:02}-parsed.json'
            if not rp.exists() or not hp.exists():
                missing.append({'mode':mode,'capture':capture,'reason':'missing_reference' if not rp.exists() else 'missing_parsed_output'})
                continue
            output_obj, verification, completion_error = load_completed_output(hp)
            if completion_error:
                missing.append({'mode':mode,'capture':capture,'reason':completion_error})
                continue
            try:
                result = score(json.loads(rp.read_text()),output_obj)
            except (ValueError,KeyError,TypeError) as e:
                missing.append({'mode':mode,'capture':capture,'reason':str(e)})
                continue
            result.update(completion_verification=verification,mode=mode,capture=capture,split='development' if capture<=8 else 'heldout',reference_file=str(rp),output_file=str(hp))
            save(out/mode/f'capture-{capture:02}-alignment.json', result)
            rows.append(result)
    summaries = {mode:{split:aggregate([r for r in rows if r['mode']==mode and (split=='all' or r['split']==split)]) for split in ['development','heldout','all']} for mode in modes}
    summary = {'method':METHOD,'expected_cells':expected_cells,'selected_modes':modes,'selected_captures':captures,'scored_cells':len(rows),'complete':len(rows)==expected_cells,'missing_cells':missing,'completion_verification_counts':dict(Counter(r['completion_verification'] for r in rows)),'summaries':summaries,'captures':[{'mode':r['mode'],'capture':r['capture'],'split':r['split'],'completion_verification':r['completion_verification'],'metrics':r['metrics']} for r in rows]}
    save(out/'quality-summary.json', summary)
    lines = ['# Journal OCR disagreement audit','',f'Scored **{len(rows)}/{expected_cells}** expected cells. '+('Complete.' if len(rows)==expected_cells else 'PARTIAL: absent references, unfinished responses, and parse failures are not scored.'),'',f"Completion provenance: {dict(Counter(r['completion_verification'] for r in rows))}. Present metadata must confirm complete=true, parsed=true, finish_reason=stop. Absent metadata is explicitly unverified; synthetic candidates are separately labeled.",'',METHOD,'| Mode | Split | Captures | Full disagreement | Known-word disagreement | Directly flagged known differences | Neighbor-flagged deletions | Uncertain / hard / unreadable reports |','|---|---|---:|---:|---:|---:|---:|---:|']
    def rate(d,key):
        value=d[key+'_disagreement_rate']
        return '—' if value is None else f'{value:.2%}'
    for mode, splits in summaries.items():
        for split,d in splits.items():
            u=d['uncertainty_counts']
            lines.append(f"| {mode} | {split} | {d['captures']} | {d['full_disagreement_operations']}/{d['reference_words']} ({rate(d,'full')}) | {d['known_disagreement_operations']}/{d['known_reference_words']} ({rate(d,'known')}) | {d['known_differences_directly_flagged']} | {d['known_deletions_with_flagged_neighbor']} | {u.get('uncertain',0)} / {u.get('hard',0)} / {u.get('unreadable',0)} |")
    lines.extend(['','Each mode directory contains per-capture JSON alignments with zero-based reference/output token indices, uncertainty masks, exact normalized output-token flag spans, and all individual differences. `quality-summary.json` includes missing cells, date mismatches, and ambiguity/unmatched-span counts.',''])
    (out/'QUALITY.md').write_text('\n'.join(lines))
    print(f'Scored {len(rows)}/{expected_cells}; {out / "QUALITY.md"}')

if __name__ == '__main__': main()
