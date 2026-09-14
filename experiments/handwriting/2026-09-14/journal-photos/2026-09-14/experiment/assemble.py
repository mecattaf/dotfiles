#!/usr/bin/env python3
"""Assemble the reviewed 12 notebook pages, retaining every source and uncertainty.

This explicitly maps deliberate overlaps; it does not guess page matches or run AI.
"""
import hashlib
import json
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
DEST=Path('/home/tom/sept14-notepad')
GROUPS=[[1],[2],[3],[4,5],[6],[7,8],[9,10],[11,12],[13],[14],[15,16],[17]]

def main():
    out=ROOT/'codex-reviewed';out.mkdir(exist_ok=True)
    reviews={n:[] for n in range(1,18)}
    for f in sorted((ROOT/'codex-review').glob('*-review*.json')):
        for row in json.loads(f.read_text()):reviews[row['capture']].append({**row,'review_file':str(f.relative_to(ROOT))})
    captures={}
    for n in range(1,18):
        first=ROOT/f'codex-first/capture-{n:02}.json'
        obj=json.loads(first.read_text());text=obj['transcription']
        assert reviews[n],f'Missing independent review for {n}'
        applied=[]
        for review in reviews[n]:
            for change in review['changes']:
                assert change['old'] in text, (n,change)
                text=text.replace(change['old'],change['new'])
                applied.append({**change,'review_file':review['review_file']})
        obj.update(transcription=text,first_pass_sha256=hashlib.sha256(first.read_bytes()).hexdigest(),review_changes=applied,independent_reviews=reviews[n],
                   reference_status='Codex first-pass plus independent visual cross-review; NOT writer-confirmed ground truth',
                   uncertainties=[{'text':m.group(0),'candidates':m.group(1).split(' | ')} for m in re.finditer(r'\[unclear: ([^\]]+)\]',text)])
        target=out/f'capture-{n:02}.json'
        target.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n')
        (out/f'capture-{n:02}.md').write_text(text.strip()+'\n')
        captures[n]=text.strip()
    assembled={1:captures[1],2:captures[2],3:captures[3]}
    assembled[4]=captures[4].split('\n[Bottom line cropped:')[0].rstrip()+'\n\n'+captures[5]
    assembled[5]=captures[6]
    # Capture08 repeats item37 and supplies its clipped continuation and margin.
    assembled[6]=captures[7].split('\n37.')[0].rstrip()+'\n'+captures[8]
    lines10=captures[10].splitlines()
    assert lines10[0].startswith('Kb charger,') and lines10[1].startswith('With laptop,')
    assert captures[9].endswith(lines10[1])
    assembled[7]=captures[9]+'\n'+'\n'.join(lines10[2:])
    lines12=captures[12].splitlines()
    assert lines12[0].startswith('(13)') and captures[11].splitlines()[-1].startswith('(13)')
    assembled[8]=captures[11]+'\n'+'\n'.join(lines12[1:])
    assembled[9]=captures[13];assembled[10]=captures[14]
    assembled[11]=captures[15].split('\n[Bottom edge, clipped heading:')[0].rstrip()+'\n\n'+captures[16]
    assembled[12]=captures[17]
    # Context can establish intended entity names without changing blind OCR labels.
    contextfile=ROOT/'context-adjudication.json'
    resolved=[]
    if contextfile.exists():
        context=json.loads(contextfile.read_text())
        for row in context['rows']:
            patch=row.get('proposed_page_patch')
            if row['decision']!='semantic_referent_resolved' or not patch:continue
            page=row['page'];assert patch['old'] in assembled[page]
            assembled[page]=assembled[page].replace(patch['old'],patch['new'])
            resolved.append(row)
    meta=json.loads((ROOT/'photo-metadata.json').read_text())
    DEST.mkdir(exist_ok=True)
    uncertain=[]
    for page,text in assembled.items():
        group=GROUPS[page-1]
        footer='Sources: '+', '.join(f'[photo {n:02}]({ROOT}/originals/{meta[n-1]["file"]})' for n in group)+'.'
        names=[row['normalized_candidate'] for row in resolved if row['page']==page]
        if names:footer+=' Context-resolved names: '+', '.join(names)+'; see [reading provenance](RESOLVED.md).'
        prefix=f'# Page {page}\n\n'
        if page==1:prefix+='> Earlier writing above this photograph is cropped and unavailable. The dated entry below is preserved.\n\n'
        # Literal numbered labels prevent CommonMark from renumbering item3 as2
        # when handwritten item2 was intentionally inline with item1.
        displayed=re.sub(r'^(\d+)\.',r'\1\\.',text,flags=re.M)
        # Keep literal numbered and arrow items on separate rendered lines.
        # Only presentation whitespace changes; source references stay untouched.
        display_lines=displayed.splitlines()
        item_line=re.compile(r'^\s*(?:\d+\\\. |\(\d+\) |→ )')
        for i,line in enumerate(display_lines[:-1]):
            following=display_lines[i+1]
            if line.strip() and following.strip() and (item_line.match(line) or item_line.match(following)):
                display_lines[i]=line+'  '
        displayed='\n'.join(display_lines)
        (DEST/f'page{page}.md').write_text(prefix+displayed+'\n\n---\n\n'+footer+'\n')
        for m in re.finditer(r'\[unclear: ([^\]]+)\]',text):
            uncertain.append({'page':page,'candidates':m.group(1),'context':text[max(0,m.start()-60):m.end()+60].replace('\n',' ')})
    (DEST/'uncertainties.json').write_text(json.dumps(uncertain,ensure_ascii=False,indent=2)+'\n')
    lines=['# Remaining uncertain readings','','The pages were read by four Codex subagents and independently cross-reviewed from the photographs. These are the unresolved readings, not words silently filled in from context. Spelling and shorthand are otherwise preserved. None of the transcription has yet been confirmed by the writer.','']
    for u in uncertain:lines.append(f'- [Page {u["page"]}](page{u["page"]}.md): **{u["candidates"]}** — {u["context"]}')
    lines+=['','Crossed-out unreadable material is marked separately in the pages. The initial sliver above page1 falls outside the supplied readable photograph. Overlaps are included once; no missing text has been invented.']
    (DEST/'UNKNOWNS.md').write_text('\n'.join(lines)+'\n')
    resolved_lines=['# Readings resolved from local context','','These canonical names are used in the notebook pages. The original uncertain visual readings remain in the frozen benchmark references. Context established the intended referent; it did not make every handwritten stroke unambiguous.','']
    for row in resolved:
        resolved_lines += [f'## Page {row["page"]}: {row["normalized_candidate"]}','',row['semantic_assessment'],'',f'Initial visual reading: `{row["raw_uncertainty"]}`.','']
        for source in row['sources']:
            resolved_lines.append(f'- [{Path(source["file"]).name}](<{source["file"]}:{source["line"]}>) — {source["excerpt"]}')
        resolved_lines.append('')
    (DEST/'RESOLVED.md').write_text('\n'.join(resolved_lines)+'\n')
    index=['# September 14 notebook collection','','12 physical notebook pages reconstructed from 17 phone photographs. Page numbers follow photographed notebook order, not a claim about dates of writing.','', 'The text preserves the handwriting, including unusual spellings and historical plans. It does not execute the instructions written in the notebook. Unresolved readings are marked inline and collected in [UNKNOWNS.md](UNKNOWNS.md).','']
    for page,group in enumerate(GROUPS,1):index.append(f'- [Page {page}](page{page}.md) — photos '+', '.join(f'{n:02}' for n in group))
    index+=['','Three ambiguous names are normalized from matching local notes; see [RESOLVED.md](RESOLVED.md). The remaining uncertain spans are unchanged.',f'[Photo sequence and provenance]({ROOT}/SEQUENCE.md). Original photographs and separate model runs remain in `{ROOT}`.']
    (DEST/'README.md').write_text('\n'.join(index)+'\n')
    hashes={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(out.glob('capture-*.json'))}
    (out/'locked-sha256.json').write_text(json.dumps(hashes,indent=2)+'\n')
    print(f'Assembled12 pages; {len(uncertain)} unresolved spans. Sources and cross-review provenance preserved.')

if __name__=='__main__':main()
