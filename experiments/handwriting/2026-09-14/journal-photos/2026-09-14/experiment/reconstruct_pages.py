#!/usr/bin/env python3
"""Disposable, provenance-preserving physical-page reconstruction; no inference.

Uses only each mode's own output text. Frozen Codex readings are loaded by a
separate reference assembler, and are never arguments to a hypothesis join.
"""
import argparse
from collections import Counter
from difflib import SequenceMatcher
import hashlib
import json
from pathlib import Path
import re

from score_quality import aggregate, load_completed_output, normalized, save, score

ROOT = Path(__file__).resolve().parents[1]
GROUPS = [[1], [2], [3], [4, 5], [6], [7, 8], [9, 10], [11, 12], [13], [14], [15, 16], [17]]
METHOD = """Physical-page disagreement against provisional, independently reviewed Codex readings, NOT writer-confirmed accuracy. Reference pages are assembled from frozen codex-reviewed captures before final notebook contextual name substitutions. Development is physical pages1–6; held-out is pages7–12. Each page is counted once, removing deliberate photographic overlaps. For page8, the frozen reference retains capture11’s item13 while hypothesis assembly retains capture12’s item13; the two frozen source readings differ only by a final period and normalize to identical scorer tokens.

Hypothesis assembly uses only text emitted by its selected mode. It never reads reference wording to resolve a hypothesis join or replace a word. Selection is structural and fixed for this reconstruction (implemented after partial model outputs existed, based on photographed overlap boundaries and applied uniformly): take the later capture from the shared bracket heading (04/05), item37 (07/08), item13 (11/12), or goals heading (15/16). For09/10 retain09 and remove10's prefix through its unique matching suffix anchor. The latter requires at least20 tokens of left suffix, at least20 matching tokens, a token similarity of0.80, an exact five-token tail, and a unique right line-ending boundary near the top. Unrecognized, missing, or ambiguous joins are refused and omitted from scoring, not repaired with reference text. Missing inputs and unsuccessful completion metadata are also omitted. Partial reports show coverage explicitly; compare modes on common completed pages.

The existing score_quality.score normalization, Levenshtein alignment, uncertain-reference exclusion, date comparison, and uncertainty-span attribution are reused. Case, punctuation and ordinary line wrapping are ignored by that scorer; its known-word measure conservatively excludes uncertain reference locations and adjacent insertions. It is disagreement, not calibrated accuracy. Capture uncertainty flags are retained only when their normalized span can be located wholly in one retained source segment; every retained, discarded, ambiguous or unmatched flag is audited. Page-level ambiguity is still handled by the scorer. Every retained/discarded source character range and exact source text is recorded, including rejected joins. Source transcriptions and reference files are never modified.
"""


class JoinRefused(ValueError):
    pass


def lines(raw):
    result, pos = [], 0
    for part in raw.splitlines(keepends=True):
        result.append({'start': pos, 'end': pos + len(part), 'text': part.rstrip('\r\n')})
        pos += len(part)
    return result


def unique_line(raw, predicate, label):
    matches = [row for row in lines(raw) if predicate(row['text'])]
    if len(matches) != 1:
        raise JoinRefused(f'{label}: expected one structural anchor, found {len(matches)}')
    return matches[0]


def number_pattern(number):
    # ~~37~~ is deliberately NOT a live numbered-item anchor.
    return re.compile(r'^\s*(?:\(\s*' + str(number) + r'\s*\)|' + str(number) + r'(?!\d)\s*[.*xX×)]?)\s+')


def numbered_join(left, right, number):
    pattern = number_pattern(number)
    a = unique_line(left, lambda x: bool(pattern.match(x)), f'left item{number}')
    b = unique_line(right, lambda x: bool(pattern.match(x)), f'right item{number}')
    before = unique_line(left, lambda x: bool(number_pattern(number-1).match(x)), f'left item{number-1}')
    after = unique_line(right, lambda x: bool(number_pattern(number+1).match(x)), f'right item{number+1}')
    if before['start'] >= a['start'] or after['start'] <= b['start']:
        raise JoinRefused('numbered anchors are out of sequence')
    if len([x for x in lines(right[:b['start']]) if x['text'].strip()]) > 3:
        raise JoinRefused('shared numbered item is not near the right capture top')
    tokens_a, tokens_b = normalized(a['text'])['tokens'], normalized(b['text'])['tokens']
    similarity = SequenceMatcher(None, tokens_a, tokens_b, autojunk=False).ratio()
    if min(len(tokens_a), len(tokens_b)) < 3 or similarity < 0.45:
        raise JoinRefused('same item label has incompatible emitted text')
    return a['start'], b['start'], {'strategy': 'later_capture_from_shared_number', 'number': number,
                                   'left_anchor': a, 'right_anchor': b, 'anchor_similarity': similarity}


def heading_join(left, right, kind):
    if kind == 'bracket':
        predicate = lambda x: bool(re.match(r'^\s*\[\s*[Pp][.\s]*\d', x))
    else:
        predicate = lambda x: bool(re.match(r'^\s*(?:\[\s*)?(?:The\s+)?goals?\b', x, re.I))
    a = unique_line(left, predicate, f'left {kind} heading')
    b = unique_line(right, predicate, f'right {kind} heading')
    if left[a['end']:].strip():
        raise JoinRefused(f'left {kind} heading is not the final nonblank line')
    # Only structural divider/blank material may precede a complete heading.
    prefix = right[:b['start']].strip()
    if prefix and not re.fullmatch(r'[-_\s]+', prefix):
        raise JoinRefused(f'unexplained material before right {kind} heading')
    return a['start'], b['start'], {'strategy': 'later_capture_from_shared_heading', 'kind': kind,
                                   'left_anchor': a, 'right_anchor': b}


def suffix_join(left, right):
    """Find a unique own-output overlap boundary, allowing changed line wraps."""
    left_lines = [x for x in lines(left) if x['text'].strip()]
    suffix_start = len(left_lines)
    suffix_tokens = []
    while suffix_start and len(suffix_tokens) < 20:
        suffix_start -= 1
        suffix_tokens = normalized(left[left_lines[suffix_start]['start']:])['tokens']
    if len(suffix_tokens) < 20:
        raise JoinRefused('left suffix too short for a robust overlap anchor')
    right_lines = [x for x in lines(right) if x['text'].strip()][:8]
    boundaries = {}
    for start in range(min(5, len(right_lines))):
        for end in range(start, len(right_lines)):
            segment = right[right_lines[start]['start']:right_lines[end]['end']]
            tokens = normalized(segment)['tokens']
            if len(tokens) < 20 or tokens[-5:] != suffix_tokens[-5:]:
                continue
            matcher = SequenceMatcher(None, suffix_tokens, tokens, autojunk=False)
            ratio = matcher.ratio()
            matched = sum(x.size for x in matcher.get_matching_blocks())
            if ratio < 0.80 or matched < 20:
                continue
            row = {'right_match_start': right_lines[start]['start'], 'right_discard_end': right_lines[end]['end'],
                   'similarity': ratio, 'matched_tokens': matched, 'right_tokens': len(tokens)}
            key = row['right_discard_end']
            if key not in boundaries or ratio > boundaries[key]['similarity']:
                boundaries[key] = row
    if len(boundaries) != 1:
        raise JoinRefused(f'common-suffix join: expected one right boundary, found {len(boundaries)}')
    match = next(iter(boundaries.values()))
    return len(left), match['right_discard_end'], {'strategy': 'left_capture_plus_unique_common_suffix',
            'left_suffix_start': left_lines[suffix_start]['start'], 'left_suffix_tokens': len(suffix_tokens), **match}


def segment(capture, raw, start, end, action, reason):
    return {'capture': capture, 'start': start, 'end': end, 'action': action, 'reason': reason, 'text': raw[start:end]}


def retained_flags(objects, spans):
    retained, audit = [], []
    for capture, obj in objects.items():
        for index, flag in enumerate(obj.get('uncertainties', [])):
            needle = normalized(str(flag.get('text', '')))['tokens']
            matches = []
            for span_index, span in enumerate(spans):
                if span['capture'] != capture:
                    continue
                tokens = normalized(span['text'])['tokens']
                starts = [i for i in range(len(tokens)-len(needle)+1)
                          if needle and tokens[i:i+len(needle)] == needle]
                matches.extend({'span_index': span_index, 'token_start': i, 'action': span['action']} for i in starts)
            keep = [x for x in matches if x['action'] == 'retain']
            status = 'retained' if len(keep) == 1 and len(matches) == 1 else ('ambiguous' if keep else ('discarded' if matches else 'unmatched'))
            audit.append({'capture': capture, 'uncertainty_index': index, 'flag': flag, 'status': status, 'matches': matches})
            if status == 'retained':
                retained.append({**flag, 'source_capture': capture, 'source_uncertainty_index': index})
    return retained, audit


def reconstruct(page, objects):
    """Objects must be exactly the selected mode's own capture outputs."""
    group = GROUPS[page-1]
    assert set(objects) == set(group)
    for obj in objects.values():
        if not isinstance(obj.get('transcription'), str):
            raise JoinRefused('non-string transcription')
    if len(group) == 1:
        n = group[0]; raw = objects[n]['transcription']
        spans = [segment(n, raw, 0, len(raw), 'retain', 'single photograph')]
        join = {'strategy': 'single_capture'}
    else:
        a, b = group; left, right = objects[a]['transcription'], objects[b]['transcription']
        if page == 4:
            left_end, right_start, join = heading_join(left, right, 'bracket')
        elif page in (6, 8):
            left_end, right_start, join = numbered_join(left, right, 37 if page == 6 else 13)
        elif page == 7:
            left_end, right_start, join = suffix_join(left, right)
        elif page == 11:
            left_end, right_start, join = heading_join(left, right, 'goals')
        else:
            raise JoinRefused('no declared join policy')
        spans = [segment(a, left, 0, left_end, 'retain', 'before shared anchor, or complete left capture'),
                 segment(a, left, left_end, len(left), 'discard', 'overlap supplied by later capture'),
                 segment(b, right, 0, right_start, 'discard', 'overlap or cropped leading fragment'),
                 segment(b, right, right_start, len(right), 'retain', 'shared anchor onward, or new continuation')]
    for n in group:
        selected = [s for s in spans if s['capture'] == n]
        assert selected[0]['start'] == 0 and selected[-1]['end'] == len(objects[n]['transcription'])
        assert all(x['end'] == y['start'] for x, y in zip(selected, selected[1:]))
        assert ''.join(x['text'] for x in selected) == objects[n]['transcription']
    text = '\n'.join(x['text'].rstrip('\r\n') for x in spans if x['action'] == 'retain' and x['text'])
    flags, flag_audit = retained_flags(objects, spans)
    return {'page': page, 'captures': group, 'status': 'complete', 'transcription': text,
            'uncertainties': flags, 'uncertainty_selection_audit': flag_audit, 'join': join, 'spans': spans,
            'source_character_partition_verified': True, 'word_source': 'selected mode emitted text only'}


def reference_pages(refs):
    """Independent frozen-reference assembly, before final-context substitutions."""
    c = {n: refs[n]['transcription'].strip() for n in range(1, 18)}
    p = {1:c[1], 2:c[2], 3:c[3], 5:c[6], 9:c[13], 10:c[14], 12:c[17]}
    assert '[Bottom line cropped:' in c[4] and '\n37.' in c[7]
    p[4] = c[4].split('\n[Bottom line cropped:')[0].rstrip()+'\n\n'+c[5]
    p[6] = c[7].split('\n37.')[0].rstrip()+'\n'+c[8]
    right = c[10].splitlines()
    assert c[9].endswith(right[0]+'\n'+right[1])
    p[7] = c[9]+'\n'+'\n'.join(right[2:])
    assert c[11].splitlines()[-1].startswith('(13)') and c[12].splitlines()[0].startswith('(13)')
    p[8] = c[11]+'\n'+'\n'.join(c[12].splitlines()[1:])
    assert '[Bottom edge, clipped heading:' in c[15]
    p[11] = c[15].split('\n[Bottom edge, clipped heading:')[0].rstrip()+'\n\n'+c[16]
    return {n: {'page': n, 'captures': GROUPS[n-1], 'transcription': text,
                'reference_status': 'frozen reviewed Codex, not writer-confirmed; no final-context normalization'} for n, text in p.items()}


def summarize(rows):
    result = aggregate([{**r, 'capture':r['page']} for r in rows])
    result['pages'] = result.pop('captures')
    result['date_mismatch_pages'] = result.pop('date_mismatch_captures')
    return result


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root', type=Path, default=ROOT)
    ap.add_argument('--reference', default='codex-reviewed')
    ap.add_argument('--runs', default='runs/baseline')
    ap.add_argument('--output', help='Default: <runs>/reconstructed')
    ap.add_argument('--modes', default='off,low,medium,xhigh')
    args = ap.parse_args()
    modes = args.modes.split(',')
    if not modes or len(set(modes)) != len(modes) or any(not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', x) for x in modes):
        ap.error('--modes must contain unique simple directory names')
    refs_path, runs = args.root/args.reference, args.root/args.runs
    out = args.root/args.output if args.output else runs/'reconstructed'
    locks = json.loads((refs_path/'locked-sha256.json').read_text())
    before = {n: hashlib.sha256((refs_path/f'capture-{n:02}.json').read_bytes()).hexdigest() for n in range(1,18)}
    assert all(before[n] == locks[f'capture-{n:02}.json'] for n in before), 'Frozen reference hash mismatch'
    refs = reference_pages({n:json.loads((refs_path/f'capture-{n:02}.json').read_text()) for n in range(1,18)})
    for page, ref in refs.items():
        save(out/'reference-pages'/f'page{page}.json', ref)
        (out/'reference-pages'/f'page{page}.md').write_text(ref['transcription']+'\n')
    rows, failures, reconstructions = [], [], []
    for mode in modes:
        for page, group in enumerate(GROUPS, 1):
            objects, sources, errors = {}, [], []
            for capture in group:
                source = runs/mode/f'capture-{capture:02}-parsed.json'
                obj, verification, error = load_completed_output(source)
                if error:
                    errors.append({'capture': capture, 'reason': error})
                else:
                    objects[capture] = obj
                    sources.append({'capture':capture, 'path':str(source), 'sha256':hashlib.sha256(source.read_bytes()).hexdigest(), 'completion_verification':verification})
            base = {'mode':mode, 'page':page, 'captures':group, 'split':'development' if page<=6 else 'heldout', 'sources':sources}
            if errors:
                result = {**base, 'status':'incomplete_inputs', 'errors':errors}
            else:
                try:
                    result = {**base, **reconstruct(page, objects)}
                except JoinRefused as exc:
                    result = {**base, 'status':'join_refused', 'reason':str(exc),
                              'unjoined_fragments':[{ 'capture':n, 'transcription':objects[n]['transcription']} for n in group]}
            save(out/mode/f'page{page}.json', result)
            md = out/mode/f'page{page}.md'
            alignment_path = out/mode/f'page{page}-alignment.json'
            if result['status'] == 'complete':
                # Preserve line layout and literal list labels without adding reference words.
                display = re.sub(r'^(\d+)\.', r'\1\\.', result['transcription'], flags=re.M)
                display = '\n'.join(line+'  ' if line.strip() else line for line in display.splitlines())
                md.write_text(display.rstrip()+'\n')
                scored = score(refs[page], result)
                scored.update(mode=mode, page=page, split=base['split'], output_file=str(out/mode/f'page{page}.json'), reference_file=str(out/'reference-pages'/f'page{page}.json'))
                save(alignment_path, scored)
                rows.append(scored)
            else:
                if alignment_path.exists():
                    alignment_path.unlink()
                md.write_text(f"Reconstruction unavailable: {result['status']}. See page{page}.json for source fragments and audit.\n")
                failures.append(result)
            reconstructions.append({k:v for k,v in result.items() if k not in ('transcription','uncertainties','spans','unjoined_fragments')})
    common = sorted(set.intersection(*(set(r['page'] for r in rows if r['mode']==mode) for mode in modes)))
    summaries = {mode:{split:summarize([r for r in rows if r['mode']==mode and (split=='all' or r['split']==split)]) for split in ('development','heldout','all')} for mode in modes}
    common_summaries = {mode:{split:summarize([r for r in rows if r['mode']==mode and r['page'] in common and (split=='all' or r['split']==split)]) for split in ('development','heldout','all')} for mode in modes}
    report = {'method':METHOD, 'expected_cells':12*len(modes), 'scored_cells':len(rows), 'complete':len(rows)==12*len(modes),
              'selected_modes':modes, 'summaries':summaries, 'common_completed_pages':common, 'common_page_summaries':common_summaries,
              'failures':failures, 'reconstructions':reconstructions, 'frozen_reference_sha256':before,
              'pages':[{'mode':r['mode'],'page':r['page'],'split':r['split'],'metrics':r['metrics']} for r in rows]}
    save(out/'page-quality-summary.json', report)
    report_lines = ['# Qwen physical-page reconstruction and disagreement', '',
        f"Scored **{len(rows)}/{12*len(modes)}** expected pages. {'Complete.' if report['complete'] else 'PARTIAL; unavailable/refused pages are not scored.'}", '', METHOD,
        '| Mode | Split | Pages | Full disagreement | Known-word disagreement |', '|---|---|---:|---:|---:|']
    for mode, splits in summaries.items():
        for split, result in splits.items():
            cells=[]
            for prefix, denominator in [('full','reference_words'),('known','known_reference_words')]:
                rate=result[prefix+'_disagreement_rate']
                cells.append(f"{result[prefix+'_disagreement_operations']}/{result[denominator]} ({rate:.2%})" if rate is not None else '—')
            report_lines.append(f"| {mode} | {split} | {result['pages']} | {' | '.join(cells)} |")
    report_lines += ['', f'Common completed physical pages across selected modes: {common}. `page-quality-summary.json` includes separate common-page summaries for comparisons with identical denominators.', '', '## Joins requiring review / pending inputs', '']
    for fail in failures:
        report_lines.append(f"- {fail['mode']} page{fail['page']}: {fail['status']} — {fail.get('reason', str(fail.get('errors')))}")
    if not failures:
        report_lines.append('None. Every declared join passed the structural/own-text checks.')
    report_lines += ['', 'Each mode has pageX.md, pageX.json and successful pageX-alignment.json files. JSON character ranges are zero-based, end-exclusive, and partition the exact raw input strings. No discarded fragment is silently lost from the audit. Reference pages live separately in reference-pages/ and retain the original uncertain identifiers, including the three names later normalized only in the final user notebook.', '']
    (out/'PAGE-QUALITY.md').write_text('\n'.join(report_lines))
    assert all(hashlib.sha256((refs_path/f'capture-{n:02}.json').read_bytes()).hexdigest()==before[n] for n in before)
    print(f"Reconstructed/scored {len(rows)}/{12*len(modes)}; {out/'PAGE-QUALITY.md'}")


if __name__ == '__main__':
    main()
