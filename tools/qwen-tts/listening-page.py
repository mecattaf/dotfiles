"""Create a portable, self-contained listening comparison from measured WAVs."""
import argparse
import base64
import html
import json
from pathlib import Path
import wave


def duration(path):
    try:
        with wave.open(str(path), 'rb') as audio:
            return audio.getnframes() / audio.getframerate()
    except wave.Error:
        return None


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, default=Path.home() / 'tts-audition-20260914')
    args = p.parse_args()
    root = args.root
    rows = []
    paths = [path for path in sorted((root / 'samples').glob('*.wav'))
             if path.with_suffix('.json').exists()
             and ('-take-' not in path.stem or path.stem.endswith('-take-01'))]
    paths += sorted((root / 'vibevoice-cpp/outputs').glob('*.wav'))
    paths += sorted((root / 'benchmarks').glob('*long*/run-1.wav'))
    # Additional engines can register output paths without changing this renderer.
    registry = root / 'listening-extra.json'
    extra = json.loads(registry.read_text()) if registry.exists() else []
    paths += [root / item['path'] for item in extra]
    labels = {str(root / item['path']): item for item in extra}
    for path in dict.fromkeys(paths):
        if not path.is_file():
            continue
        receipt = path.with_suffix('.json')
        info = json.loads(receipt.read_text()) if receipt.exists() else {}
        if path.name == 'run-1.wav' and (path.parent / 'benchmark.json').exists():
            benchmark = json.loads((path.parent / 'benchmark.json').read_text())
            if benchmark.get('runs') and 'wall_seconds' in benchmark['runs'][0]:
                run = benchmark['runs'][0]
                info.update(audio_seconds=run['audio_seconds'], generation_seconds=run['wall_seconds'],
                            rtf_generation_only=run['rtf'])
        custom = labels.get(str(path), {})
        name = custom.get('label', path.stem.replace('_', ' ').replace('-', ' '))
        if path.name == 'qwen-serveurperso-intro_9s_raw.wav':
            name = 'Liked voice baseline · Qwen / original intro'
        if path.name == 'run-1.wav':
            name = path.parent.name.replace('-', ' ') + ' · first reading'
        group = custom.get('group', 'Long reading' if 'long' in path.stem or 'long' in path.parent.name else
                           'Generic voices' if 'generic' in path.name or 'carter' in path.name or 'realtime' in path.name else 'K-2SO references')
        seconds = info.get('audio_seconds', duration(path))
        elapsed = info.get('generation_seconds', info.get('engine_synthesis_seconds', info.get('wall_seconds_including_load', info.get('elapsed_seconds'))))
        rtf = info.get('rtf_generation_only', info.get('rtf_generation', info.get('engine_rtf', info.get('wall_rtf'))))
        if rtf is None and elapsed is not None and seconds:
            rtf = elapsed / seconds
        timing = info.get('timing_label', 'Generation' if 'generation_seconds' in info or 'engine_synthesis_seconds' in info else 'Process incl. loading')
        transcript = path.with_suffix('.txt')
        asr = path.with_suffix('.asr.txt')
        rows.append({'name': name, 'group': group, 'file': str(path.relative_to(root)),
                     'seconds': seconds, 'elapsed': elapsed, 'rtf': rtf, 'timing': timing,
                     'text': transcript.read_text().strip() if transcript.exists() else custom.get('text', ''),
                     'asr': asr.read_text().strip() if asr.exists() else '',
                     'note': custom.get('note', ''),
                     'audio': base64.b64encode(path.read_bytes()).decode()})
    payload = json.dumps(rows).replace('<', '\\u003c')
    report = root / 'REPORT.md'
    report_text = report.read_text() if report.exists() else 'Measured report is being assembled.'
    try:
        import markdown
        report_html = markdown.markdown(report_text, extensions=['tables', 'fenced_code'])
    except ImportError:
        report_html = '<pre>' + html.escape(report_text) + '</pre>'
    output = '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Local speech — listening comparison</title>
<script>try{document.documentElement.dataset.theme=localStorage.getItem('speech-theme')||(matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light')}catch(e){}</script>
<style>
:root{color-scheme:light;--bg:#f5f3ed;--fg:#29313a;--muted:#657079;--line:#c8ccc5;--accent:#53643c}
:root[data-theme=dark]{color-scheme:dark;--bg:#20252b;--fg:#e9e8df;--muted:#b2b9bb;--line:#49514f;--accent:#b0bd94}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.55 'SF Pro Text',system-ui,sans-serif}
main{max-width:1180px;margin:auto;padding:40px 28px 80px}header{border-bottom:1px solid var(--line);padding-bottom:24px}
h1{font-size:clamp(30px,5vw,46px);font-weight:600;letter-spacing:-.035em;line-height:1.12;margin:14px 0}
h2{font-size:24px;font-weight:550;margin:38px 0 14px}p{max-width:850px}.eyebrow,.muted{color:var(--muted)}
.eyebrow{font-size:13px;letter-spacing:.04em}button,select{background:transparent;border:1px solid var(--line);color:var(--fg);padding:8px 12px;font:inherit;border-radius:3px;cursor:pointer}
button:hover,button:focus-visible{border-color:var(--accent)}a{color:var(--accent)}.toolbar{display:flex;gap:12px;flex-wrap:wrap;align-items:center;margin-top:22px}
.table-wrap{overflow-x:auto}table{width:100%;border-collapse:collapse;text-align:left}th{font-size:12px;font-weight:600;color:var(--muted)}th,td{padding:13px 12px 13px 0;border-bottom:1px solid var(--line);vertical-align:top}
td:first-child{min-width:220px;width:40%}audio{max-width:310px;width:100%;min-width:240px;height:38px}small{display:block;color:var(--muted);font-size:12px}details{margin-top:8px}summary{cursor:pointer;color:var(--accent);font-size:13px}
.words{font-size:13px;max-width:520px;margin:6px 0}.number{font-variant-numeric:tabular-nums;white-space:nowrap}pre{white-space:pre-wrap;overflow-wrap:anywhere;font:14px/1.6 'SF Pro Text',system-ui,sans-serif;max-width:100%}
.report{overflow-x:auto}.report h1{font-size:28px;margin-top:30px}.report table{font-size:14px}.report td:first-child{width:auto;min-width:0}.report code{font-size:.88em;overflow-wrap:anywhere}
footer{margin-top:38px;color:var(--muted);font-size:13px}#status{font-size:13px;color:var(--muted)}
@media(max-width:600px){main{padding:26px 18px}th,td{padding-right:10px}td:first-child{min-width:190px}}
</style></head><body><main>
<header><div class="eyebrow">COORDINATOR → ZENBOOK · 14 SEPTEMBER 2026</div>
<h1>Local speech, side by side.</h1>
<p>The liked baseline uses Qwen 1.7B Base Q8 with the original nine-second K-2SO introduction. Qwen through qwentts.cpp leads the TTS tests. Compare the cleaned references, other runtimes and three original male voices before settling the voice and precision.</p>
<p class="muted">All inference ran on the coordinator. These recordings play on this device. Original output levels are preserved; loudness can influence preference. Transcript checks test words, not resemblance or listening comfort.</p>
<div class="toolbar"><button id="theme" type="button">Toggle appearance</button><button id="blind" type="button">Hide names & shuffle</button><button id="stop" type="button">Stop playback</button><a href="#findings">Read the findings</a><span id="status" role="status"></span></div></header>
<div id="groups"></div><h2 id="findings">Measurements and interpretation</h2>
<div class="report">REPORT</div>
<footer>RTF = generation seconds ÷ audio seconds; below 1 is faster than real time. Rows explicitly distinguish synthesis from process time including loading. First PCM is not acoustically measured laptop latency. This file embeds its recordings and makes no network requests.</footer>
</main><script>
const rows=PAYLOAD;let blind=false;const el=document.getElementById('groups');
function add(parent,tag,text,cls){const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;parent.append(n);return n}
function render(){el.replaceChildren();const list=[...rows];if(blind){for(let i=list.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[list[i],list[j]]=[list[j],list[i]]}}
const order=['K-2SO references','Generic voices','Long reading','Reference clips'];
const groups=blind?['Blind comparison']:[...new Set(list.map(r=>r.group))].sort((a,b)=>order.indexOf(a)-order.indexOf(b));if(!blind)list.sort((a,b)=>Number(b.name.startsWith('Liked voice'))-Number(a.name.startsWith('Liked voice')));let count=0;
for(const group of groups){add(el,'h2',group);const wrap=add(el,'div',undefined,'table-wrap');const table=add(wrap,'table');const tr=add(add(table,'thead'),'tr');['Recording','Listen','Audio','Time / RTF'].forEach(t=>add(tr,'th',t));const body=add(table,'tbody');
for(const r of list.filter(r=>blind||r.group===group)){const row=add(body,'tr');const title=add(row,'td');add(title,'span',blind?`Sample ${++count}`:r.name);if(!blind){add(title,'small',r.file);if(r.note)add(title,'p',r.note,'words');const d=add(title,'details');add(d,'summary','Text and transcript check');add(d,'p',r.text||'See the measured report.','words');add(d,'p',r.asr?`Independent ASR: ${r.asr}`:'No paired CPU transcript displayed for this take.','words')}
const cell=add(row,'td'),audio=add(cell,'audio');audio.controls=true;audio.preload='none';audio.src='data:audio/wav;base64,'+r.audio;audio.setAttribute('aria-label',blind?'Play comparison sample':'Play '+r.name);audio.addEventListener('play',()=>{document.querySelectorAll('audio').forEach(a=>{if(a!==audio)a.pause()})});
add(row,'td',r.seconds==null?'—':r.seconds.toFixed(2)+' s','number');const metric=add(row,'td',undefined,'number');if(!blind&&r.elapsed!=null){add(metric,'span',r.elapsed.toFixed(2)+' s');add(metric,'small',r.timing);if(r.rtf!=null)add(metric,'small','RTF '+r.rtf.toFixed(3))}else add(metric,'span','—');}}
document.getElementById('status').textContent=rows.length+' recordings';}
document.getElementById('theme').onclick=()=>{const t=document.documentElement.dataset.theme==='dark'?'light':'dark';document.documentElement.dataset.theme=t;try{localStorage.setItem('speech-theme',t)}catch(e){}};
document.getElementById('blind').onclick=()=>{blind=!blind;document.getElementById('blind').textContent=blind?'Show names':'Hide names & shuffle';render()};
document.getElementById('stop').onclick=()=>document.querySelectorAll('audio').forEach(a=>{a.pause();a.currentTime=0});render();
</script></body></html>'''.replace('PAYLOAD', payload).replace('REPORT', report_html)
    destination = root / 'listening.html'
    destination.write_text(output)
    print(f'{destination}: {len(rows)} recordings, {destination.stat().st_size:,} bytes')


if __name__ == '__main__':
    main()
