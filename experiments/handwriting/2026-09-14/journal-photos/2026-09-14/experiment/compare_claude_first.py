#!/usr/bin/env python3
"""Offline audit of supplied Claude first-pass artifacts; never runs inference."""
from collections import Counter
from difflib import SequenceMatcher
import hashlib
import html
import json
from pathlib import Path
import re

from reconstruct_pages import GROUPS, JoinRefused, lines, number_pattern, reconstruct, reference_pages, retained_flags, segment, summarize, unique_line
from score_quality import WORD, aggregate, normalized, save, score

ROOT = Path(__file__).resolve().parents[1]
METHOD = '''The supplied artifacts self-report model claude-opus-5 and four reader identities. This script does not independently verify the generating model. This is Claude FIRST PASS versus independently cross-reviewed Codex, with unequal review budgets, not writer-confirmed truth or a controlled model ranking. No Claude review or inference occurs here.

JSON $.transcription is the explicit primary text. Markdown transcription sections are independently hashed and compared, not silently substituted. They sometimes include margin/crossout information omitted or represented differently in JSON; those source-representation differences are reported. In particular, a date recorded outside JSON transcription is distinguished from an unread date. Marginal facts are not invented or silently inserted into main text.

The scoring adapter removes only three recognized standalone descriptions of clipped non-readable marks, unwraps [partial: ...] around actual supplied words, and removes the literal [warning triangle] drawing label. Every removed character interval and retained mapping to the original JSON text is recorded. It does not choose alternatives or correct words. Reconstitution uses the existing own-output structural helpers. Item37 is unique in both relevant Claude outputs; the extra item38 is retained as emitted rather than allowing a validation check on the following number to hide or correct it. Unknown or ambiguous actual join anchors are refused. Every selected/discarded source span remains auditable.

Frozen Codex reference pages come from codex-reviewed before the three final-notebook canonical-name substitutions. score_quality.score supplies normalized word disagreements and uncertain-reference exclusions. Such differences are review candidates, not proof Claude is wrong. Physical pages are counted once; capture metrics additionally include overlapping photographs. Meaningful queue entries arise from changed normalized words or dates. Formatting entries are limited to spans with equal normalized words/dates, or an explicitly corroborated date moved to metadata. Unverified source-supplied bounding boxes are copied only when a matching uncertainty span provides one; no new image coordinates are inferred.
'''


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def markdown_body(text):
    if '## Transcription\n' not in text:
        raise ValueError('missing Markdown Transcription section')
    return text.split('## Transcription\n',1)[1].split('\n## ',1)[0].strip()


def adapt(raw):
    removals=[]
    for row in lines(raw):
        value=row['text'];match=re.match(r'^\s*\[partial:\s*(.*?)\]\s*$',value)
        if match:
            content=match.group(1)
            if re.match(r'(top line cut off|drawing strokes cut|ascenders of next line only)',content):
                removals.append({'start':row['start'],'end':row['end'],'reason':'supplied editorial description of unreadable clipped marks'})
            else:
                removals += [{'start':row['start'],'end':row['start']+match.start(1),'reason':'unwrap supplied partial-text label; retain its words'},
                             {'start':row['start']+match.end(1),'end':row['start']+len(value),'reason':'remove outer partial-text closing bracket'}]
        for mark in re.finditer(r'\[warning triangle\]',value):
            removals.append({'start':row['start']+mark.start(),'end':row['start']+mark.end(),'reason':'supplied drawing label; not written words'})
    removals.sort(key=lambda x:x['start'])
    cursor=0;output='';mapping=[]
    for rem in removals+[{'start':len(raw),'end':len(raw)}]:
        assert rem['start']>=cursor
        if rem['start']>cursor:
            piece=raw[cursor:rem['start']]
            mapping.append({'adapted_start':len(output),'adapted_end':len(output)+len(piece),'source_start':cursor,'source_end':rem['start']})
            output+=piece
        cursor=rem['end']
    return output, {'removals':[{**x,'text':raw[x['start']:x['end']]} for x in removals], 'retained_source_map':mapping}


def source_ranges(adapter,start,end):
    result=[]
    for row in adapter['retained_source_map']:
        a=max(start,row['adapted_start']);b=min(end,row['adapted_end'])
        if a<b:
            result.append({'source_start':row['source_start']+a-row['adapted_start'],
                           'source_end':row['source_start']+b-row['adapted_start']})
    return result


def claude_reconstruct(page,objects):
    if page!=6:
        return reconstruct(page,objects)
    # The shared item37 is unique. Repeated38 downstream is model text, not a
    # second candidate for the actual cut boundary; keep both occurrences.
    left,right=objects[7]['transcription'],objects[8]['transcription']
    a=unique_line(left,lambda x:bool(number_pattern(37).match(x)),'left item37')
    b=unique_line(right,lambda x:bool(number_pattern(37).match(x)),'right item37')
    previous=unique_line(left,lambda x:bool(number_pattern(36).match(x)),'left item36')
    following=[x for x in lines(right) if number_pattern(38).match(x['text']) and x['start']>b['start']]
    sim=SequenceMatcher(None,normalized(a['text'])['tokens'],normalized(b['text'])['tokens'],autojunk=False).ratio()
    if previous['start']>=a['start'] or not following or sim<0.45 or len(lines(right[:b['start']]))>3:
        raise JoinRefused('Claude item37 boundary failed sequence/text validation')
    spans=[segment(7,left,0,a['start'],'retain','before shared item37'),segment(7,left,a['start'],len(left),'discard','later capture supplies complete item37'),
           segment(8,right,0,b['start'],'discard','repeated earlier item36'),segment(8,right,b['start'],len(right),'retain','item37 onward, including emitted repeated38')]
    flags,audit=retained_flags(objects,spans)
    return {'page':6,'captures':[7,8],'status':'complete','transcription':'\n'.join(x['text'].rstrip('\r\n') for x in spans if x['action']=='retain'),
            'uncertainties':flags,'spans':spans,'uncertainty_selection_audit':audit,'join':{'strategy':'unique shared item37; retain later duplicate38 as emitted','anchor_similarity':sim},
            'source_character_partition_verified':all(''.join(s['text'] for s in spans if s['capture']==n)==objects[n]['transcription'] for n in (7,8))}


def source_info(capture,manifest):
    return {'capture':capture,'page':next(i for i,g in enumerate(GROUPS,1) if capture in g),
            'claude_json':{'path':str(ROOT/f'claude-first/capture-{capture:02}.json'),'sha256':manifest[f'capture-{capture:02}.json'],'field':'$.transcription'},
            'claude_markdown':{'path':str(ROOT/f'claude-first/capture-{capture:02}.md'),'sha256':manifest[f'capture-{capture:02}.md'],'section':'Transcription'},
            'codex_json':{'path':str(ROOT/f'codex-reviewed/capture-{capture:02}.json'),'sha256':sha(ROOT/f'codex-reviewed/capture-{capture:02}.json'),'field':'$.transcription'}}


def token_groups(result):
    groups=[];current=[]
    for operation in result['operations']:
        if operation['operation']=='match':
            if current:groups.append(current);current=[]
        else:current.append(operation)
    if current:groups.append(current)
    return groups


def queue_entries(capture,result,obj,provenance):
    rows=[]
    for index,ops in enumerate(token_groups(result),1):
        ri=[x['reference_index'] for x in ops if x['reference_index'] is not None]
        hi=[x['output_index'] for x in ops if x['output_index'] is not None]
        rg=[min(ri),max(ri)+1] if ri else [ops[0]['reference_gap']]*2
        hg=[min(hi),max(hi)+1] if hi else [ops[0]['output_gap']]*2
        locations=[]
        for flag,located in zip(obj['uncertainties'],result['uncertainty_locations']):
            if located['location_status']!='unique':continue
            start,end=located['candidate_token_spans'][0]
            if max(start,hg[0])<min(end,hg[1]) or (hg[0]==hg[1] and start<=hg[0]<=end):
                locations.append({'provenance':'Claude source-supplied; not independently verified','coordinate_frame':'unspecified by supplied artifact; do not assume original unrotated image',
                                  'uncertainty_span':flag['text'],'location':flag.get('location'), 'alternatives':flag.get('alternatives',[])})
        rows.append({'id':f'claude-c{capture:02}-word-{index:03}','classification':'meaningful','kind':'normalized_word_disagreement','status':'needs_human_review',**provenance,
                     'codex_reading':' '.join(x['reference'] for x in ops if x['reference'] is not None),
                     'claude_reading':' '.join(x['output'] for x in ops if x['output'] is not None),
                     'reading_representation':'normalized scorer tokens; exact raw text stays in source files',
                     'codex_context':' '.join(result['reference_tokens'][max(0,rg[0]-8):rg[1]+8]),
                     'claude_context':' '.join(result['output_tokens'][max(0,hg[0]-8):hg[1]+8]),
                     'codex_normalized_token_range':rg,'claude_normalized_token_range':hg,
                     'reference_uncertain_or_adjacent':any(x['excluded_from_known_word_measure'] for x in ops),
                     'source_locations':locations,'operations':ops})
    return rows


def human_review_queue(out,refs,adapted,manifest,queue):
    """Review prompts only: no answers, labels, automatic corrections or boxes."""
    from PIL import Image
    final_unknowns=json.loads(Path('/home/tom/sept14-notepad/uncertainties.json').read_text())
    selected={
        'claude-c02-word-001':'Technical project name differs.',
        'claude-c03-word-002':'The noun after bugs/problems differs.',
        'claude-c04-word-001':'Node versus mode changes the technical meaning.',
        'claude-c04-word-002':'Technical platform name differs.',
        'claude-c05-word-003':'Academic ties versus tpes may name different work.',
        'claude-c05-word-005':'Alphanumeric time shorthand differs.',
        'claude-c05-word-006':'Triaged versus trigged may describe a different action.',
        'claude-c06-word-001':'Technical project identifier differs.',
        'claude-c06-word-004':'Technical project suffix differs.',
        'claude-c06-word-005':'The entire phrase differs, beyond spelling.',
        'claude-c06-word-006':'Docs/files versus disciplines changes the scope.',
        'claude-c07-word-001':'Who versus what changes the intended object.',
        'claude-c07-word-002':'Technical project suffix differs.',
        'claude-c08-word-002':'Technical project name differs; use the complete later photograph.',
        'claude-c08-word-006':'Worker node versus mode changes the technical meaning.',
        'claude-c10-word-002':'Additional conjunction may affect the relationship between devices.',
        'claude-c10-word-004':'Technical project name differs.',
    }
    deferred={
        'claude-c04-word-005':'cropped heading recovered from later overlapping photo',
        'claude-c07-word-004':'same physical text is queued from complete later capture08',
        'claude-c07-word-005':'crossed-out item number is a presentation/strikeout issue',
        'claude-c07-word-006':'cropped margin fragment recovered in later photo',
        'claude-c08-word-001':'overlap fragment intentionally excluded in physical-page assembly',
        'claude-c08-word-003':'crossed-out item number is a presentation/strikeout issue',
        'claude-c08-word-004':'boxed margin wording moved, not missing',
        'claude-c08-word-005':'boxed margin wording moved, not missing',
        'claude-c10-word-001':'overlap fragment intentionally excluded in physical-page assembly',
        'claude-c12-word-001':'overlap fragment intentionally excluded in physical-page assembly',
        'claude-c15-word-001':'goals heading recovered from later overlapping photo',
        'claude-c16-word-001':'same margin wording appears later in Claude text',
        'claude-c16-word-003':'same margin wording appears earlier in Codex text',
        'claude-c07-word-003':'canonical nick-iconiq referent already documented in final RESOLVED.md; not writer-confirmed literal spelling',
        'claude-c10-word-003':'canonical Enoki referent already documented in final RESOLVED.md; not writer-confirmed literal spelling',
        'claude-c05-word-001':'covered by unresolved Codex campaign dec/doc prompt',
        'claude-c13-word-001':'covered by unresolved Codex shell/skill prompt',
    }
    items=[];audit=[]
    def context_for(text,needle,around):
        ls=text.splitlines();exact=[i for i,line in enumerate(ls) if needle and needle in line]
        if len(exact)==1:index=exact[0]
        else:
            target=normalized(around)['tokens']
            needle_tokens=normalized(needle)['tokens']
            candidates=exact or [i for i,line in enumerate(ls) if needle_tokens and any(normalized(line)['tokens'][j:j+len(needle_tokens)]==needle_tokens for j in range(len(normalized(line)['tokens'])-len(needle_tokens)+1))] or list(range(len(ls)))
            index=max(candidates,key=lambda i:SequenceMatcher(None,target,normalized(' '.join(ls[max(0,i-1):i+2]))['tokens'],autojunk=False).ratio())
        return {'previous':ls[index-1] if index else '', 'current':ls[index], 'next':ls[index+1] if index+1<len(ls) else '', 'source_line_number':index+1}
    def base(capture,raw,around,source_path):
        image=ROOT/f'inputs/capture-{capture:02}.png'
        assert image.is_file()
        text=refs[capture]['transcription'];ctx=context_for(text,raw,around)
        page=next(i for i,g in enumerate(GROUPS,1) if capture in g)
        return {'capture':capture,'page':page,'page_key':f'2026-09-14/page{page}','raw':raw,'reported_raw':raw,
                'line':ctx['current'],'context':ctx,'transcription':text,'image_path':str(image),'image_sha256':sha(image),
                'image_size':list(Image.open(image).size),'source':str(source_path),'source_sha256':sha(source_path),
                'difficulty':'hard','selection_required':True,'bbox':None,'bbox_status':'not supplied; writer must select text on upright full photograph',
                'resolution_status':'unanswered','writer_confirmed':False}
    def exact_span(text,needle,around):
        """Map normalized differing words back to a contiguous raw source span."""
        import unicodedata
        words=list(WORD.finditer(text));tokens=[re.sub("['’]",'',unicodedata.normalize('NFKC',w.group()).casefold()) for w in words]
        sought=normalized(needle)['tokens']
        hits=[i for i in range(len(tokens)-len(sought)+1) if sought and tokens[i:i+len(sought)]==sought]
        if not hits:return None
        if len(hits)>1:
            ctx=context_for(text,needle,around);line_number=ctx['source_line_number']
            offsets=[0]
            for line in text.splitlines(keepends=True):offsets.append(offsets[-1]+len(line))
            hits=[i for i in hits if offsets[line_number-1]<=words[i].start()<offsets[line_number]]
        if len(hits)!=1:return None
        start=words[hits[0]].start();end=words[hits[0]+len(sought)-1].end()
        return {'text':text[start:end],'start':start,'end':end,'field':'$.transcription'}
    for index,unknown in enumerate(final_unknowns,1):
        marker='[unclear: '+unknown['candidates']+']'
        matches=[n for n in GROUPS[unknown['page']-1] if marker in refs[n]['transcription']]
        assert len(matches)==1,(unknown,matches)
        capture=matches[0];candidates=[x.strip() for x in unknown['candidates'].split('|')]
        raw=candidates[0].split(';',1)[0].strip()
        source=ROOT/f'codex-reviewed/capture-{capture:02}.json'
        item=base(capture,raw,unknown['context'],source)
        clause_context=context_for(adapted[capture]['transcription'],raw,unknown['context'])
        matching=[f for f in adapted[capture]['uncertainties'] if normalized(f['text'])['tokens'] in [normalized(c.split(';',1)[0])['tokens'] for c in candidates]]
        claude_format='reported_uncertainty_span'
        claude=matching[0]['text'] if len(matching)==1 else None
        if claude is None:
            spans=[exact_span(adapted[capture]['transcription'],c.split(';',1)[0],unknown['context']) for c in candidates]
            spans=[s for s in spans if s]
            if spans:
                claude=spans[0]['text'];claude_format='exact_source_span'
                clause_context=context_for(adapted[capture]['transcription'],claude,unknown['context'])
            else:
                claude='[specific Claude reading unavailable]';claude_format='unavailable'
        item.update(id=f'codex-unknown-p{unknown["page"]}-{hashlib.sha256(marker.encode()).hexdigest()[:12]}',origin='codex_unresolved',
                    reason='Still unresolved after independent Codex visual review; the writer should confirm the intended reading.',
                    reported_raw=marker,readings={'codex':' | '.join(candidates),'claude':claude},
                    reading_scopes={'codex':'unresolved candidates','claude':claude_format},
                    readings_format='unresolved_candidates',reading_formats={'codex':'candidate_list','claude':claude_format},
                    readings_note='Codex lists alternatives, not one confirmed reading. Claude is an exact supplied span or is explicitly unavailable; neither is writer-confirmed.',
                    claude_context={**clause_context,'line_number_basis':'adapted Claude transcription; raw source remains in evidence JSON'},
                    provisional_candidates=candidates,source_json_field='$.transcription',
                    evidence_sources=[source_info(capture,manifest)],existing_supplied_claude_locations=[f.get('location') for f in matching],
                    supplied_locations_used_for_crop=False)
        # Exact marker gives a better line anchor than a short ambiguous word.
        item['context']=context_for(refs[capture]['transcription'],marker,unknown['context']);item['line']=item['context']['current']
        items.append(item)
    for row in queue:
        if row['classification']!='meaningful':continue
        reason=selected.get(row['id'])
        if not reason:
            audit.append({'source_id':row['id'],'decision':'deferred','reason':deferred.get(row['id'],'orthographic, abbreviation, word-joining, inflection or minor function-word variation; raw disagreement remains available'),'codex':row['codex_reading'],'claude':row['claude_reading']})
            continue
        capture=row['capture'];source=Path(row['codex_json']['path'])
        item=base(capture,row['codex_reading'] or row['claude_reading'],row['codex_context'],source)
        item.update(id=row['id'],origin='claude_codex_disagreement',reason=reason,
                    readings={'codex':row['codex_reading'],'claude':row['claude_reading']},
                    reading_scopes={'codex':'normalized differing words','claude':'normalized differing words'},
                    source_disagreement_id=row['id'],source_json_field='$.transcription',
                    evidence_sources=[{k:row[k] for k in ('claude_json','claude_markdown','codex_json')}],
                    existing_supplied_claude_locations=row['source_locations'],supplied_locations_used_for_crop=False,
                    normalized_token_locations={'codex':row['codex_normalized_token_range'],'claude':row['claude_normalized_token_range']})
        exact={side:exact_span(refs[capture]['transcription'] if side=='codex' else adapted[capture]['transcription'],row[side+'_reading'],row[side+'_context']) for side in ('codex','claude')}
        if exact['claude']:
            original=json.loads((ROOT/f'claude-first/capture-{capture:02}.json').read_text())['transcription']
            _,adapter=adapt(original)
            ranges=source_ranges(adapter,exact['claude']['start'],exact['claude']['end'])
            assert len(ranges)==1
            exact['claude']['start']=ranges[0]['source_start'];exact['claude']['end']=ranges[0]['source_end']
            assert original[exact['claude']['start']:exact['claude']['end']]==exact['claude']['text']
        formats={side:('absent_at_position' if not row[side+'_reading'] else ('exact_source_span' if exact[side] else 'normalized_words')) for side in ('codex','claude')}
        for side in ('codex','claude'):
            item['readings'][side]=exact[side]['text'] if exact[side] else (row[side+'_reading'] or '[no word at this position]')
        item['reading_formats']=formats
        item['readings_format']='normalized_words' if 'normalized_words' in formats.values() else ('source_spans_with_omission' if 'absent_at_position' in formats.values() else 'exact_source_spans')
        item['readings_note']='Exact punctuation/case copied from source where mapped. Normalized-word fallbacks are not literal quotations. A no-word marker explains an insertion/deletion; it is not handwritten text.'
        item['exact_reading_source_spans']=exact
        item['reading_scopes']=formats
        if exact['codex'] or exact['claude']:
            item['raw']=(exact['codex'] or exact['claude'])['text']
            item['reported_raw']=item['raw']
        items.append(item);audit.append({'source_id':row['id'],'decision':'queued','reason':reason})
    assert len([x for x in items if x['origin']=='codex_unresolved'])==len(final_unknowns)==9
    assert len([x for x in items if x['origin']=='claude_codex_disagreement'])==len(selected)==17
    save(out/'human-review-items.json',{'version':1,'collection':str(ROOT),'items':items,
        'policy':'Human prompts only: nine remaining Codex unknowns plus17 substantive Codex/Claude disagreements. No automatic labels, no notebook edits. Known overlap and relocation artifacts, canonical names with documented context, and harmless spelling/abbreviation variants remain in the separate audit.',
        'source_disagreements':str(out/'disagreements.json'),'source_disagreements_sha256':sha(out/'disagreements.json'),
        'bbox_policy':'All26 prompts use upright full photos and require selection. Unverified Claude boxes are evidence only and are not used for crops.'})
    save(out/'human-review-filter-audit.json',{'decisions':audit,'queued':len(selected),'unresolved_codex_prompts':len(final_unknowns),
                                            'deferred_entries_are_not_confirmed_correct':True,'writer_labels_created':0})


def main():
    source=ROOT/'claude-first';out=ROOT/'claude-comparison';refs_path=ROOT/'codex-reviewed'
    names=[f'capture-{n:02}.{suffix}' for n in range(1,18) for suffix in ('json','md')]
    assert all((source/n).is_file() for n in names),'Expected17 JSON and17 Markdown files'
    initial={name:sha(source/name) for name in names}
    models=Counter();readers=Counter();validation=[];raw_objects={};adapted={};adapters={}
    locks=json.loads((refs_path/'locked-sha256.json').read_text())
    assert all(sha(refs_path/name)==value for name,value in locks.items())
    for n in range(1,18):
        obj=json.loads((source/f'capture-{n:02}.json').read_text());raw_objects[n]=obj
        expected_page=next(i for i,g in enumerate(GROUPS,1) if n in g)
        assert obj['capture']==n and obj['physical_page']==expected_page
        assert isinstance(obj['transcription'],str) and obj['transcription'].strip()
        assert isinstance(obj['uncertainties'],list) and isinstance(obj['source_images'],list)
        assert isinstance(obj['model'],str) and isinstance(obj['reader'],str)
        for flag in obj['uncertainties']:
            assert isinstance(flag['span'],str) and isinstance(flag['alternatives'],list)
            assert flag['difficulty'] in ('uncertain','hard','unreadable')
            box=flag.get('location',{}).get('bbox_fraction')
            if box is not None:
                assert len(box)==4 and all(isinstance(v,(float,int)) and 0<=v<=1 for v in box) and box[0]<=box[2] and box[1]<=box[3]
        models[obj['model']]+=1;readers[obj['reader']]+=1
        text,adapter=adapt(obj['transcription']);adapters[n]=adapter
        adapted[n]={**obj,'transcription':text,'uncertainties':[{**f,'text':f['span']} for f in obj['uncertainties']]}
        body=markdown_body((source/f'capture-{n:02}.md').read_text())
        mdnorm=normalized(html.unescape(body));jsnorm=normalized(text)
        validation.append({'capture':n,'physical_page':expected_page,'json_markdown_transcription_exact':body==obj['transcription'].strip(),
                           'json_markdown_normalized_words_equal':mdnorm['tokens']==jsnorm['tokens'],
                           'json_transcription_dates':jsnorm['dates'],'markdown_transcription_dates':mdnorm['dates'],
                           'metadata_dates':normalized(json.dumps(obj.get('margins_and_marks',[]),ensure_ascii=False))['dates'],
                           'uncertainty_count':len(obj['uncertainties']),'source_supplied_bboxes':sum('bbox_fraction' in f.get('location',{}) for f in obj['uncertainties'])})
        save(out/'adapted-captures'/f'capture-{n:02}.json',{'source':source_info(n,initial),'transcription':text,'adaptation_audit':adapter,'uncertainties':adapted[n]['uncertainties']})
    manifest={'description':'SHA-256 audit of supplied Claude first-pass source readings; source files not edited or chmodded.',
              'model_identity_verification':'self-reported artifact metadata only','models':dict(models),'readers':dict(readers),'source_files':initial,
              'files':[{ 'name':name,'sha256':initial[name],'bytes':(source/name).stat().st_size} for name in names],
              'validation':validation,'complete_17_captures_34_files':True}
    save(source/'sha256-manifest.json',manifest)
    refs={n:json.loads((refs_path/f'capture-{n:02}.json').read_text()) for n in range(1,18)}
    refpages=reference_pages(refs)
    capture_scores=[];queue=[];formatting=[]
    for n in range(1,18):
        result=score(refs[n],adapted[n]);result.update(capture=n,page=source_info(n,initial)['page'])
        save(out/'capture-alignments'/f'capture-{n:02}.json',result);capture_scores.append(result)
        provenance=source_info(n,initial);queue+=queue_entries(n,result,adapted[n],provenance)
        if not result['metrics']['dates_match']:
            meta_dates=validation[n-1]['metadata_dates'];only_field_placement=sorted(meta_dates)==sorted(result['metrics']['reference_dates'])
            queue.append({'id':f'claude-c{n:02}-date','classification':'formatting' if only_field_placement else 'meaningful','kind':'date_field_placement' if only_field_placement else 'date_disagreement',
                          'status':'needs_human_review',**provenance,'codex_reading':result['metrics']['reference_dates'],'claude_reading':result['metrics']['output_dates'],
                          'claude_dates_in_margin_metadata':meta_dates,'source_locations':[]})
        # Only claim formatting equivalence where a raw differing span normalizes
        # to the same words and dates; never relabel a changed word as punctuation.
        ra=re.findall(r'\S+',refs[n]['transcription']);ha=re.findall(r'\S+',adapted[n]['transcription'])
        for tag,a,b,c,d in SequenceMatcher(None,ra,ha,autojunk=False).get_opcodes():
            if tag=='equal':continue
            left,right=' '.join(ra[a:b]),' '.join(ha[c:d]);ln,rn=normalized(left),normalized(right)
            if ln['tokens']==rn['tokens'] and ln['dates']==rn['dates']:
                formatting.append({'id':f'claude-c{n:02}-format-{len(formatting)+1:03}','classification':'formatting','kind':'normalization_equivalent_raw_span',
                                   **provenance,'codex_reading':left,'claude_reading':right,'source_locations':[],
                                   'raw_whitespace_token_ranges':{'codex':[a,b],'claude_adapted':[c,d]},'normalization_caveat':'May include editorial/crossout conventions ignored by scorer, not only typography.'})
    page_scores=[];failures=[]
    for page,group in enumerate(GROUPS,1):
        save(out/'reference-pages'/f'page{page}.json',refpages[page])
        try:
            result=claude_reconstruct(page,{n:adapted[n] for n in group})
            for span in result['spans']:
                span['original_json_character_ranges']=source_ranges(adapters[span['capture']],span['start'],span['end'])
            result.update(model_identity='self-reported claude-opus-5',review_status='first pass; no Claude cross-review',sources=[source_info(n,initial) for n in group])
            scored=score(refpages[page],result);scored.update(page=page,split='development' if page<=6 else 'heldout')
            save(out/'reconstructed'/f'page{page}-alignment.json',scored);page_scores.append(scored)
            display=re.sub(r'^(\d+)\.',r'\1\\.',result['transcription'],flags=re.M)
            display='\n'.join(line+'  ' if line.strip() else line for line in display.splitlines()).rstrip()
            save(out/'reconstructed'/f'page{page}.json',result)
            (out/'reconstructed'/f'page{page}.md').write_text(display+'\n')
        except JoinRefused as exc:
            result={'page':page,'captures':group,'status':'join_refused','reason':str(exc),'unjoined_fragments':[{'capture':n,'transcription':adapted[n]['transcription']} for n in group]}
            save(out/'reconstructed'/f'page{page}.json',result);failures.append(result)
            (out/'reconstructed'/f'page{page}.md').write_text('Reconstruction refused; inspect source fragments and join audit in JSON.\n')
            alignment=out/'reconstructed'/f'page{page}-alignment.json'
            if alignment.exists():alignment.unlink()
    all_queue=queue+formatting
    save(out/'disagreements.json',{'schema_version':1,'method':METHOD,'entries':all_queue,'entry_counts':dict(Counter(x['classification'] for x in all_queue)),
                                  'scope':'capture-level disagreements include photograph overlaps; physical page/capture keys permit queue grouping and later deduplication',
                                  'bbox_policy':'Only existing Claude-supplied uncertainty locations are carried, with source hashes. Boxes and frame are unverified; no coordinates invented.'})
    human_review_queue(out,refs,adapted,initial,queue)
    summary={'method':METHOD,'source_manifest':str(source/'sha256-manifest.json'),'source_models_self_reported':dict(models),'source_readers_self_reported':dict(readers),
             'validated_captures':17,'validated_source_files':34,'physical_pages_completed':len(page_scores),'physical_pages_expected':12,'join_refusals':failures,
             'capture_aggregate':aggregate(capture_scores), 'page_summaries':{split:summarize([r for r in page_scores if split=='all' or r['split']==split]) for split in ('development','heldout','all')},
             'queue_counts':dict(Counter(x['classification'] for x in all_queue)),'source_representation_validation':validation,'frozen_reference_hashes':locks}
    save(out/'comparison-summary.json',summary)
    report=['# Supplied Claude first-pass comparison','',f'Validated17 captures /34 source files. Reconstructed **{len(page_scores)}/12 physical pages**. Models self-reported: {dict(models)}.','',METHOD,
            '| Scope | Units | Known-word disagreement | Full disagreement |','|---|---:|---:|---:|']
    for label,metric,count in [('Captures, overlaps included',summary['capture_aggregate'],17)]+[(f'Pages: {s}',v,v['pages']) for s,v in summary['page_summaries'].items()]:
        vals=[]
        for prefix in ('known','full'):
            den=metric['known_reference_words' if prefix=='known' else 'reference_words'];rate=metric[prefix+'_disagreement_rate']
            vals.append(f'{metric[prefix+"_disagreement_operations"]}/{den} ({rate:.2%})' if rate is not None else '—')
        report.append(f'| {label} | {count} | '+ ' | '.join(vals)+' |')
    report+=['',f'Queue entries: {summary["queue_counts"]}. `disagreements.json` supplies both readings, contexts, physical page/capture, source hashes, normalized token locations, and existing uncertainty boxes where available. Entries are candidates for human review, not adjudicated errors.','',
             '`human-review-items.json` is the focused app import: all9 remaining Codex unknowns plus17 substantive disagreements, with upright full photos and mandatory selection. `human-review-filter-audit.json` records deferred overlap/relocation artifacts and harmless variants. Exact reading punctuation is retained where character spans can be verified; the remaining normalized and omission markers are explicitly labeled and must not be copied as literal confirmed text. No writer labels are created.', '',
             'The Markdown/JSON source discrepancies and dates in non-transcription fields are listed in comparison-summary.json and the source manifest. Both originals are preserved. JSON is the primary first-pass text used here; this does not mean it contains everything Claude recorded elsewhere.','',
             '## Refused joins','']
    report += [f'- Page{x["page"]}: {x["reason"]}' for x in failures] or ['None. All own-output structural joins passed.']
    report+=['','No source readings, frozen references, final notebook pages, or annotation UI files were modified. No Claude-reviewed directory was created.','']
    (out/'COMPARISON.md').write_text('\n'.join(report))
    assert initial=={name:sha(source/name) for name in names},'Claude source changed during comparison'
    assert all(sha(refs_path/name)==value for name,value in locks.items()),'Frozen reference changed'
    print(f'Validated34 source files; reconstructed{len(page_scores)}/12; {out/"COMPARISON.md"}')


if __name__=='__main__':main()
