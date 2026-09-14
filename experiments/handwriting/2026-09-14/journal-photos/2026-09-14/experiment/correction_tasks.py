#!/usr/bin/env python3
"""Freeze development vocabulary and select one self-reported hard span per photo.

Selection never reads held-out references. Crops are proposals requiring visual
location checks; a failed location check must not be treated as an OCR result.
"""
import difflib
import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
WORD=re.compile(r"[\w]+(?:[./-][\w]+)*",re.UNICODE)

def vocabulary():
    terms=defaultdict(set)
    # Physical pages1–6 only. Held-out photos09–17 never feed this vocabulary.
    for n in range(1,9):
        text=json.loads((ROOT/f'codex-reviewed/capture-{n:02}.json').read_text())['transcription']
        text=re.sub(r'\[unclear:[^\]]*\]',' ',text)
        text=re.sub(r'~~.*?~~',' ',text,flags=re.S)
        text=re.sub(r'\[[^\]]*\]',' ',text)
        for word in WORD.findall(text):
            if 2<=len(word)<=40 and not word.isdigit():terms[word].add(n)
    return [{'term':word,'captures':sorted(sources),'status':'provisional Codex visual reference; not writer-confirmed'} for word,sources in sorted(terms.items())]

def candidates(text, lexicon):
    scored=[]
    for item in lexicon:
        similarity=difflib.SequenceMatcher(None,text.casefold(),item['term'].casefold()).ratio()
        if similarity>=.65:
            scored.append({**item,'similarity':round(similarity,4)})
    scored.sort(key=lambda item:(-item['similarity'],-len(item['captures']),item['term']))
    return scored[:3]

def select(answer,lexicon):
    ranked=[]
    for u in answer['uncertainties']:
        text=u['text'].strip()
        if len(text)<2 or answer['transcription'].count(text)!=1:continue
        position=answer['transcription'].index(text)
        if any(m.start()<=position and position+len(text)<=m.end()
               for m in re.finditer(r'~~.*?~~',answer['transcription'],re.S)):
            continue
        # A missing dot can split one filename into two OCR words. Enlarge only
        # across the same line, with independently similar stem and short suffix.
        expansion=None
        following=re.match(r'[ \t]+([A-Za-z]{2,5})\b',answer['transcription'][position+len(text):])
        if following:
            for entry in lexicon:
                if '.' not in entry['term']:continue
                stem,suffix=entry['term'].rsplit('.',1)
                similarity=lambda a,b:difflib.SequenceMatcher(None,a.casefold(),b.casefold()).ratio()
                if similarity(text,stem)>=.75 and similarity(following.group(1),suffix)>=.5:
                    expanded=text+following.group(0)
                    if similarity(expanded,entry['term'])>similarity(text,entry['term'])+.05:
                        expansion={'original_reported_span':text,'expanded_span':expanded,'candidate':entry['term'],'reason':'Possible dotted identifier split across two OCR words'}
                        text=expanded
                        break
        hints=candidates(text,lexicon)
        difficulty={'unreadable':40,'hard':30,'uncertain':10}[u['difficulty']]
        identifier=bool(re.search(r'\w[./-]\w',text))
        exact=any(x['term'].casefold()==text.casefold() for x in hints)
        if exact and u['difficulty']=='uncertain':continue
        candidate_identifier=any(re.search(r'\w[./-]\w',x['term']) for x in hints)
        rank=difficulty+4*(identifier or candidate_identifier)+(hints[0]['similarity'] if hints else 0)
        ranked.append({'text':text,'reported':u,'hints':hints,'rank':round(rank,4),'span_expansion':expansion})
    ranked.sort(key=lambda u:(-u['rank'],u['text']))
    return ranked[:1]

def main():
    out=ROOT/'correction';out.mkdir(exist_ok=True)
    lexicon=vocabulary()
    lexfile=out/'development-vocabulary.json'
    obj={'development_captures':list(range(1,9)),'heldout_captures':list(range(9,18)),
         'terms':lexicon,'selection':'Only model-reported uncertainty; one highest-ranked unique span per photo. Rank: unreadable40/hard30/uncertain10; identifier punctuation+4; best vocabulary similarity; exact known term−2. Lexical similarity>=0.65; at most3 candidates. No reference error locations used.'}
    if lexfile.exists():assert json.loads(lexfile.read_text())==obj,'Frozen vocabulary changed'
    else:lexfile.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n')
    policy={'version':4,'scope':'Chosen using development captures01–08 only; no held-out model errors consulted',
            'rule':'One unique model-reported span per photo. Rank unreadable40/hard30/uncertain10; internal identifier punctuation in span OR retrieved candidate+4; best vocabulary similarity. Skip ordinary uncertain spans already exactly in vocabulary. Internal punctuation requires word characters on both sides; trailing sentence periods are not identifier evidence. Similarity>=0.65; max3 hints.',
            'additional_exclusion':'Do not spend the correction budget on spans entirely inside explicit ~~crossouts~~.',
            'span_expansion':'A uniquely located uncertainty may include its next same-line word (2–5 letters) when matching the stem and suffix of a dotted vocabulary identifier: stem similarity>=.75, suffix>=.5, full candidate similarity improves>.05. This prevents replacing workord alone with workerd.nix and leaving the spurious mix suffix behind.',
            'reason':'Development01–03 hard reports concerned cancelled text. Development06 reported30 ordinary uncertainties, often on correctly spelled known terms, and trailing dr. punctuation attracted the earlier heuristic. Prioritize useful identifier candidates instead.',
            'history':'development-vocabulary.json selection describes the initial heuristic. selection-policy-v4.json is authoritative; v2 and v3 remain saved. All adjustments use development errors only.'}
    policyfile=out/'selection-policy-v4.json'
    if policyfile.exists():assert json.loads(policyfile.read_text())==policy
    else:policyfile.write_text(json.dumps(policy,indent=2)+'\n')
    bounds={row['capture']:row for row in json.loads((ROOT/'experiment/text-bounds.json').read_text())['captures']}
    overridefile=out/'crop-overrides.json'
    overrides=json.loads(overridefile.read_text()) if overridefile.exists() else {}
    manifest=json.loads((ROOT/'input-manifest.json').read_text())['captures']
    tasks=[];coverage=[]
    for row in manifest:
        n=row['capture_order'];source=ROOT/f'runs/baseline/off/capture-{n:02}-parsed.json'
        if not source.exists():
            coverage.append({'capture':n,'status':'no_parsed_off_result'});continue
        answer=json.loads(source.read_text())
        selected=select(answer,lexicon)
        if not selected:
            coverage.append({'capture':n,'status':'no_eligible_self_reported_span','uncertainty_count':len(answer['uncertainties'])});continue
        item=selected[0];text=answer['transcription'];lines=[line for line in text.splitlines() if line.strip()]
        targetline=next((i for i,line in enumerate(lines) if item['text'] in line),None)
        if targetline is None:
            coverage.append({'capture':n,'status':'selected_span_crosses_lines_or_missing','text':item['text']});continue
        im=Image.open(ROOT/'originals'/row['file']).convert('RGB')
        if row['rotation_ccw']:im=im.transpose(Image.Transpose.ROTATE_90)
        w,h=im.size;l,t,r,b=bounds[n]['bbox']
        centre=(t+(targetline+.5)/len(lines)*(b-t))*h
        top=max(0,min(h-900,round(centre-450)))
        box=[max(0,round(l*w)-40),top,min(w,round(r*w)+40),top+900]
        override=overrides.get(str(n))
        if override:
            assert override['text']==item['text'],'Crop override refers to another target'
            box=override['box']
            assert 0<=box[0]<box[2]<=w and 0<=box[1]<box[3]<=h
        crop=im.crop(box)
        # Align dimensions to server stride; keep native pixels as nearly as possible.
        size=tuple(max(32,round(s/32)*32) for s in crop.size)
        if size[0]*size[1]>3686400:
            factor=(size[0]*size[1]/3686400)**.5
            size=tuple(int(s/factor/32)*32 for s in size)
        crop=crop.resize(size,Image.Resampling.BICUBIC)
        image=out/f'capture-{n:02}-crop.png';crop.save(image)
        tasks.append({'capture':n,'partition':'development' if n<=8 else 'heldout','baseline':str(source.relative_to(ROOT)),
                      'baseline_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),**item,
                      'transcribed_line':lines[targetline],'line_index':targetline,'line_count':len(lines),
                      'crop':str(image.relative_to(ROOT)),'crop_box_upright_original':box,'crop_dimensions':size,
                      'crop_sha256':hashlib.sha256(image.read_bytes()).hexdigest(),
                      'location_check':'pending visual inspection; approximate line-to-image mapping'})
        coverage.append({'capture':n,'status':'crop_proposed','text':item['text'],'difficulty':item['reported']['difficulty']})
    (out/'tasks-proposed.json').write_text(json.dumps({'vocabulary_sha256':hashlib.sha256(lexfile.read_bytes()).hexdigest(),'selection_policy_sha256':hashlib.sha256(policyfile.read_bytes()).hexdigest(),'selection_policy':'selection-policy-v4.json','tasks':tasks,'coverage':coverage},ensure_ascii=False,indent=2)+'\n')
    print(f'{len(lexicon)} frozen development terms; {len(tasks)} proposed crops from available off-mode results.')

if __name__=='__main__':main()
