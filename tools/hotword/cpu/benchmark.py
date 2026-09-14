#!/usr/bin/env python3
"""Six serialized CPU fixture windows and one paced positive check; never opens a microphone."""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ('runner','model-dir','negative-pcm','positive-pcm','keywords','output'):
        ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--seconds',type=int,default=60)
    args=ap.parse_args()
    if not 10<=args.seconds<=120:ap.error('window length must be10..120 seconds')
    if args.output.exists():ap.error('output directory already exists; choose a fresh one')
    args.output.mkdir(parents=True)
    protocol=[('01-disabled','disabled'),('02-replay','replay'),('03-kws','kws'),('04-disabled','disabled'),('05-kws','kws'),('06-replay','replay')]
    report=dict(scope='Saved16kHz monoS16LE PCM at80ms cadence; no microphone capture/playback/daemon activation',
        threads=1,seconds_per_window=args.seconds,protocol=protocol,
        fixture_sha256=hashlib.sha256(args.negative_pcm.read_bytes()).hexdigest(),
        baseline_limits='Disabled is an instrumented sleeping native process with libraries mapped. Replay reads/transforms saved PCM, not a capture device.',windows=[])
    for name,mode in protocol+[('07-positive-functional','kws')]:
        positive=name.startswith('07-');fixture=args.positive_pcm if positive else args.negative_pcm
        duration=round(fixture.stat().st_size/32000/.08)*.08 if positive else args.seconds
        if not 1<=duration<=300:raise ValueError('Positive fixture duration must be1..300seconds')
        command=[str(args.runner),'--mode',mode,'--model-dir',str(args.model_dir),'--input',str(fixture),'--keywords',str(args.keywords),'--seconds',str(duration)]
        output=args.output/name
        subprocess.run([sys.executable,str(Path(__file__).with_name('observe.py')),'--output',str(output),'--timeout',str(duration+30),'--',*command],check=True)
        events=[json.loads(x) for x in (output/'stdout.jsonl').read_text().splitlines()]
        summary=next(x for x in reversed(events) if x.get('type')=='summary')
        ready=next(x for x in events if x.get('type')=='ready')
        observer=json.loads((output/'observer.json').read_text())
        report['windows'].append(dict(id=name,mode=mode,positive=positive,summary=summary,ready=ready,
            observer=str(output/'observer.json'),process_threads_peak=observer['process_threads_peak'],
            process_rss_peak_bytes=observer['process_rss_peak_bytes'],process_pss_peak_bytes=observer['process_pss_peak_bytes'],sensors=observer['sensors']))
        (args.output/'benchmark.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(dict(completed=name,cpu_core_percent=summary['cpu_one_core_fraction']*100,events=len(summary['events']))),flush=True)
    report['status']='complete';(args.output/'benchmark.json').write_text(json.dumps(report,indent=2)+'\n')

if __name__=='__main__':main()
