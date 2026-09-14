#!/usr/bin/env python3
"""Offline, disposable uncertainty-routing audit; never edits evidence or inference policy."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

from score_quality import ROOT, load_completed_output, score, save

MODES = ('off', 'low', 'medium', 'xhigh')
POLICIES = ('hard_only', 'hard_or_unreadable', 'all_reported')


def selected(location, policy):
    difficulty = str(location['difficulty']).lower()
    return (policy == 'all_reported' or difficulty == 'hard' or
            policy == 'hard_or_unreadable' and difficulty == 'unreadable')


def audited_artifacts(result, capture, mode):
    """Annotate already visually audited artifacts; preserve raw scorer operations."""
    annotations = {}
    ops = result['operations']
    if capture == 10:
        indices = [i for i, op in enumerate(ops) if op['operation'] == 'insert'
                   and op.get('reference_gap') == 0 and op['output_index'] < 6]
        if len(indices) == 6:
            annotations.update({i: 'audited_capture10_clipped_top_line_boundary_scope' for i in indices})
    if capture == 9 and mode == 'xhigh':
        indices = [i for i, op in enumerate(ops) if op['operation'] == 'substitute'
                   and (op['reference_index'], op['reference'], op['output']) in
                   ((57, 'fr', '10'), (58, '10', 'fr'))]
        if len(indices) == 2:
            annotations.update({i: 'audited_capture09_recognized_replacement_layout_order' for i in indices})
    return annotations


def policy_audit(result, policy, artifacts):
    ops = result['operations']
    known = [(i, op) for i, op in enumerate(ops) if not op['excluded_from_known_word_measure']
             and op['operation'] != 'match']
    flags = [dict(x) for x in result['uncertainty_locations'] if selected(x, policy)]
    unique_tokens, possible_tokens = set(), set()
    flags_counts = Counter()
    for flag in flags:
        spans = flag['candidate_token_spans']
        possible = {i for a, b in spans for i in range(a, b)}
        possible_tokens.update(possible)
        if flag['location_status'] == 'unique':
            unique_tokens.update(possible)
            covered = [op for op in ops if op['output_index'] in possible]
            if any(not op['excluded_from_known_word_measure'] and op['operation'] != 'match' for op in covered):
                category = 'overlaps_known_difference'
            elif any(op['excluded_from_known_word_measure'] for op in covered):
                category = 'reference_uncertain_region'
            elif covered and all(op['operation'] == 'match' for op in covered):
                category = 'reference_matching_alert'
            else:
                category = 'unclassified'
        else:
            category = flag['location_status']
        flag['audit_category'] = category
        flags_counts[category] += 1
        # Diagnostic only: an absent output span may describe omitted source text.
        needle = flag['normalized_tokens']
        refs = result['reference_tokens']
        if flag['location_status'] == 'unmatched' and needle:
            starts = [i for i in range(len(refs)-len(needle)+1) if refs[i:i+len(needle)] == needle]
            deleted = {op['reference_index'] for _, op in known if op['operation'] == 'delete'}
            flag['possible_omitted_reference_spans'] = [[i, i+len(needle)] for i in starts
                if any(j in deleted for j in range(i, i+len(needle)))]
    counts = Counter({'reported_flags': len(flags), 'known_operations': len(known),
                      'audited_artifact_operations': sum(i in artifacts for i, _ in known)})
    for key in ('direct_known_operations', 'possible_located_known_operations',
                'nonartifact_known_operations', 'direct_nonartifact_known_operations',
                'deletions', 'deletions_with_exact_flagged_neighbor', 'repeated_report_operations',
                'unreported_substitution_insertion_operations',
                'nonartifact_unreported_substitution_insertion_operations'):
        counts[key] = 0
    differences = []
    for i, op in known:
        row = dict(op)
        hi = op['output_index']
        direct = hi is not None and hi in unique_tokens
        possible = hi is not None and hi in possible_tokens
        counts['direct_known_operations'] += direct
        counts['possible_located_known_operations'] += possible
        if i not in artifacts:
            counts['nonartifact_known_operations'] += 1
            counts['direct_nonartifact_known_operations'] += direct
        if op['operation'] == 'delete':
            counts['deletions'] += 1
            gap = op['output_gap']
            counts['deletions_with_exact_flagged_neighbor'] += bool({gap-1, gap} & unique_tokens)
            state = 'omission_no_output_token'
        elif direct:
            state = 'exactly_flagged'
        elif possible:
            counts['repeated_report_operations'] += 1
            state = 'reported_but_repeated_span'
        else:
            counts['unreported_substitution_insertion_operations'] += 1
            if i not in artifacts:
                counts['nonartifact_unreported_substitution_insertion_operations'] += 1
            state = 'no_matching_reported_span'
        row.update(flag_state=state, audited_artifact=artifacts.get(i))
        differences.append(row)
    counts.update({'flag_' + k: v for k, v in flags_counts.items()})
    return {'counts': dict(counts), 'flags': flags, 'known_differences': differences}


def aggregate(rows, policy):
    counts = Counter()
    for row in rows:
        counts.update(row['policies'][policy]['counts'])
    return {'captures': len(rows), **dict(counts)}


def pct(n, d):
    return f'{n}/{d} ({n/d:.1%})' if d else '0/0'


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root', type=Path, default=ROOT)
    ap.add_argument('--reference', default='codex-reviewed')
    ap.add_argument('--runs', default='runs/baseline')
    ap.add_argument('--output', default='runs/baseline/certainty')
    args = ap.parse_args()
    root = args.root
    rows, missing = [], []
    for mode in MODES:
        for capture in range(1, 18):
            rp = root / args.reference / f'capture-{capture:02}.json'
            hp = root / args.runs / mode / f'capture-{capture:02}-parsed.json'
            if not rp.exists() or not hp.exists():
                missing.append({'capture': capture, 'mode': mode, 'reason': 'missing_reference_or_output'})
                continue
            obj, verification, error = load_completed_output(hp)
            if error:
                missing.append({'capture': capture, 'mode': mode, 'reason': error})
                continue
            result = score(json.loads(rp.read_text()), obj)
            artifacts = audited_artifacts(result, capture, mode)
            rows.append({'capture': capture, 'mode': mode,
                         'split': 'development' if capture <= 8 else 'heldout',
                         'completion_verification': verification,
                         'reference_sha256': hashlib.sha256(rp.read_bytes()).hexdigest(),
                         'output_sha256': hashlib.sha256(hp.read_bytes()).hexdigest(),
                         'policies': {policy: policy_audit(result, policy, artifacts) for policy in POLICIES}})
    summaries = {mode: {split: {policy: aggregate([r for r in rows if r['mode'] == mode and r['split'] == split], policy)
                               for policy in POLICIES} for split in ('development', 'heldout')} for mode in MODES}
    out = root / args.output
    save(out / 'certainty-summary.json', {'complete': len(rows) == 68, 'scored_cells': len(rows),
         'expected_cells': 68, 'missing_cells': missing, 'summaries': summaries, 'captures': rows,
         'scorer_sha256': hashlib.sha256((Path(__file__).parent/'score_quality.py').read_bytes()).hexdigest(),
         'audit_note': 'Raw known-word operations are provisional reference disagreements, not independently adjudicated factual mistakes. Audit-only exclusions annotate known09/10boundary/layout cases; no source or scorer changes.'})
    lines = ['# Self-reported uncertainty audit', '',
             f'**{len(rows)}/68 cells scored.** ' + ('Complete.' if len(rows) == 68 else 'Partial; unfinished/missing cells are excluded. Rerun after the baseline completes.'), '',
             'Check cell counts before comparing modes: partial held-out groups may contain different captures and cannot support a mode ranking.', '',
             'This measures flag coverage of normalized disagreement with the reviewed Codex reference. It is not calibrated confidence, author-confirmed accuracy, or a count of independent factual mistakes. It reuses `score_quality.py` unchanged. Captures01–08 are development;09–17 are held out; repeated photo overlaps remain counted.', '',
             'A flag gets direct coverage credit only when its normalized span occurs once in the output. Repeated spans are reported separately. An absent span cannot be safely replaced. Deletions have no output token and never count as directly flagged; a nearby flag is only an adjacency diagnostic. “Hard only” means difficulty=hard exactly; JSON also includes hard-or-unreadable. “All” includes every self-reported uncertainty.', '',
             '| Mode | Split | Cells | Route | Direct coverage of raw known ops | Known ops without known09/10artifacts | Reported flags | Reference-matching alerts | Repeated / unmatched flags |',
             '|---|---|---:|---|---:|---:|---:|---:|---:|']
    for mode in MODES:
        for split in ('development', 'heldout'):
            for policy in ('hard_only', 'all_reported'):
                s = summaries[mode][split][policy]
                lines.append(f"| {mode} | {split} | {s['captures']} | {policy} | {pct(s.get('direct_known_operations',0),s.get('known_operations',0))} | {pct(s.get('direct_nonartifact_known_operations',0),s.get('nonartifact_known_operations',0))} | {s.get('reported_flags',0)} | {s.get('flag_reference_matching_alert',0)} | {s.get('flag_ambiguous_repetition',0)} / {s.get('flag_unmatched',0)} |")
    lines += ['', 'Reference-matching alerts are apparent false alarms relative to this reference, not proven false alarms: the reference can also be wrong. Flags touching unresolved reference words are a separate JSON category. Repeated reports can describe real mistakes despite receiving no exact-span credit. Thus raw uncovered operations are not all silent mistakes.', '',
              '| Mode | Split | Unreported S/I ops (raw / minus audited artifacts) | S/I ops with repeated report | Deletion ops | Deletions next to exact flag |',
              '|---|---|---:|---:|---:|---:|']
    for mode in MODES:
        for split in ('development', 'heldout'):
            s = summaries[mode][split]['all_reported']
            lines.append(f"| {mode} | {split} | {s.get('unreported_substitution_insertion_operations',0)} / {s.get('nonartifact_unreported_substitution_insertion_operations',0)} | {s.get('repeated_report_operations',0)} | {s.get('deletions',0)} | {s.get('deletions_with_exact_flagged_neighbor',0)} |")
    lines += ['', 'S/I means substitution/insertion alignment operations. Even the artifact-subtracted columns are not fully adjudicated errors: spelling normalization, shorthand expansion, token segmentation and other layout differences remain. Deletions can be omitted words or tokenization effects, not necessarily whole omitted lines.', '',
              '## Audit examples and limitations', '',
              '- Development capture02: the corrupted herdr-kitten identifier is reported as uncertain in every mode, never hard; Tally.nix→Tally.mix attracts no report. Capture03 off reports the triaged→tried disagreement as uncertain. Hard-only routing misses these useful correction candidates.',
              '- Development capture01: avenues matches the reference yet attracts an uncertain report. Bankrupcy→Bankruptcy is an unreported spelling normalization rather than a meaningful content failure. The unresolved aperature/operature source is masked from known-word counts.',
              '- Held-out capture09: repeated Imzone reports describe both Inzone substitutions but have ambiguous output locations; they are reported doubts, not truly silent mistakes. Tb3 matches the reference and is an apparent false alarm.',
              '- Held-out capture10: low/medium uncertainty metadata mentions zenbook although the transcript omits it. JSON records possible matches to deleted reference text, but grants no direct coverage. This requires a separate missing-content check rather than ordinary string replacement.',
              '- Known09/10artifacts: capture09 xhigh places recognized replacement10 above FR08, creating two order substitutions. Every capture10 mode includes six tokens from a clipped top line omitted by the reference. These are annotated separately using the existing [visual audit](../ERROR-AUDIT-HELDOUT09-10.md), not reclassified as numeral-recognition failure or six invented words. No reference, selector or normalization was changed.', '',
              '## Routing implication', '',
              'Use self-reported difficulty to order a review queue, not as a calibrated acceptance score or sole error detector. Restricting correction to hard flags drops useful uncertain identifier and ordinary-word cases. All flags improve coverage but include correct words, unresolved source readings, repeated spans and cancelled text. Validate a target’s image location and handle repeated/absent spans explicitly before correction. Keep a separate coverage check for missing lines, margins, insertions and numbering; flags alone cannot certify completeness. The crop/lookup experiment must determine correction benefit and regression risk; this audit does not select a winner from held-out data.', '',
              'Rerun: `python experiment/certainty_audit.py` from any directory. `certainty-summary.json` contains every flag, policy, known operation, diagnostic classification, input hashes, completion provenance and missing cell. The examples above come from completed captures01–03 and09–10; the tables update as additional cells finish.', '']
    out.mkdir(parents=True, exist_ok=True)
    (out/'CERTAINTY.md').write_text('\n'.join(lines))
    print(f'Scored {len(rows)}/68; {out / "CERTAINTY.md"}')


if __name__ == '__main__':
    main()
