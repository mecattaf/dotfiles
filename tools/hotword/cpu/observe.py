#!/usr/bin/env python3
"""Shared read-only Linux observer for a bounded fixture process (no mic access)."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time

def number(p):
 try:return int(Path(p).read_text().strip())
 except (OSError,ValueError):return None
def label(p):
 try:return Path(p).read_text().strip()
 except OSError:return None
def sensors():
 out=[]
 for directory in Path('/sys/class/hwmon').glob('hwmon*'):
  name=label(directory/'name')
  for pattern,unit in [('temp*_input','millidegrees_C'),('fan*_input','RPM'),('power*_average','microwatts')]:
   for p in directory.glob(pattern):
    out.append(dict(path=str(p),name=name,label=label(p.with_name(p.name.replace('_input','_label').replace('_average','_label'))),unit=unit))
 return out
def proc(pid):
 try:
  root=Path('/proc')/str(pid);stat=(root/'stat').read_text().rsplit(')',1)[1].split();status={k:v.strip() for k,v in (x.split(':',1) for x in (root/'status').read_text().splitlines())}
  memory={}
  try:memory={k:int(v.split()[0])*1024 for k,v in (x.split(':',1) for x in (root/'smaps_rollup').read_text().splitlines()[1:]) if k in ('Rss','Pss','Private_Clean','Private_Dirty')}
  except (OSError,ValueError):pass
  return dict(cpu_seconds=(int(stat[11])+int(stat[12]))/os.sysconf('SC_CLK_TCK'),
    rss_bytes=int((root/'statm').read_text().split()[1])*os.sysconf('SC_PAGE_SIZE'),memory=memory,
    threads=int(status['Threads']),main_thread_voluntary_context_switches=int(status['voluntary_ctxt_switches']),
    main_thread_involuntary_context_switches=int(status['nonvoluntary_ctxt_switches']))
 except (OSError,ValueError,IndexError,KeyError):return None
def display_state():
 paths=[Path('/sys/class/backlight/intel_backlight/brightness'),Path('/sys/class/backlight/card1-eDP-2-backlight/brightness')]
 dpms=list(Path('/sys/class/drm').glob('card*-eDP-*/dpms'))
 return dict(brightness={str(p):number(p) for p in paths},dpms={str(p):label(p) for p in dpms})
def display_valid(state):
 return len(state['brightness'])==2 and all(v==0 for v in state['brightness'].values()) and len(state['dpms'])==2 and all(v=='On' for v in state['dpms'].values())
def percentile(values,q=.95):
 values=sorted(v for v in values if v is not None)
 return values[min(len(values)-1,max(0,__import__('math').ceil(q*len(values))-1))] if values else None
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);ap.add_argument('--require-brightness-zero',action='store_true');ap.add_argument('--timeout',type=float,default=180);ap.add_argument('command',nargs=argparse.REMAINDER);a=ap.parse_args();command=a.command[1:] if a.command[:1]==['--'] else a.command
 if not command or not 1<=a.timeout<=600:ap.error('command and bounded1..600s timeout required')
 a.output.mkdir(parents=True,exist_ok=False);sensor_list=sensors();rows=[];start=time.monotonic();p=None
 initial_display=display_state() if a.require_brightness_zero else None
 if a.require_brightness_zero and not display_valid(initial_display):raise SystemExit('Display preflight failed; no child started')
 env=dict(os.environ,OMP_NUM_THREADS='1',OPENBLAS_NUM_THREADS='1',MKL_NUM_THREADS='1',NUMEXPR_NUM_THREADS='1')
 with (a.output/'stdout.jsonl').open('w') as stdout,(a.output/'stderr.log').open('w') as stderr:
  try:
   p=subprocess.Popen(command,stdout=stdout,stderr=stderr,env=env)
   deadline=start
   while p.poll() is None:
    now=time.monotonic();rows.append(dict(elapsed=now-start,process=proc(p.pid),sensors={s['path']:number(s['path']) for s in sensor_list},loadavg=Path('/proc/loadavg').read_text().strip(),host_cpu=Path('/proc/stat').read_text().splitlines()[0],display=display_state() if a.require_brightness_zero else None))
    if a.require_brightness_zero and not display_valid(rows[-1]['display']):raise RuntimeError('Brightness/DPMS changed; stopping owned child')
    if now-start>a.timeout:raise TimeoutError('Bounded observer timeout')
    deadline+=1;time.sleep(max(0,deadline-time.monotonic()))
  finally:
   if p and p.poll() is None:
    p.terminate()
    try:p.wait(timeout=10)
    except subprocess.TimeoutExpired:p.kill();p.wait(timeout=5)
   process_windows=[]
   for x,y in zip(rows,rows[1:]):
    if x['process'] and y['process']:process_windows.append((y['process']['cpu_seconds']-x['process']['cpu_seconds'])/(y['elapsed']-x['elapsed']))
   sensor_summary=[]
   for s in sensor_list:
    values=[r['sensors'].get(s['path']) for r in rows];clean=[v for v in values if v is not None]
    sensor_summary.append(dict(**s,readable=bool(clean),first=clean[0] if clean else None,last=clean[-1] if clean else None,peak=max(clean) if clean else None,p95=percentile(clean)))
   final_display=display_state() if a.require_brightness_zero else None
   display_pass=not a.require_brightness_zero or (display_valid(initial_display) and display_valid(final_display) and all(display_valid(r['display']) for r in rows))
   report=dict(display_guard_required=a.require_brightness_zero,display_guard_pass=display_pass,initial_display=initial_display,final_display=final_display,start_monotonic=start,command=command,pid=p.pid if p else None,exit_code=p.returncode if p else None,wall_seconds=time.monotonic()-start,
    observer_scope='External1Hz read-only observer; own CPU cost excluded from child process metrics. Temperature/RPM are not acoustic audibility measurements.',
    process_cpu_one_second_p95=percentile(process_windows),process_cpu_one_second_mean=sum(process_windows)/len(process_windows) if process_windows else None,
    process_rss_peak_bytes=max((r['process']['rss_bytes'] for r in rows if r['process']),default=None),
    process_pss_peak_bytes=max((r['process']['memory'].get('Pss',0) for r in rows if r['process']),default=None),
    process_threads_peak=max((r['process']['threads'] for r in rows if r['process']),default=None),sensors=sensor_summary,rows=rows)
   (a.output/'observer.json').write_text(json.dumps(report,indent=2)+'\n')
 if not display_pass:raise SystemExit('Display guard failed; receipt preserved')
 if p.returncode:raise SystemExit(p.returncode)
 print(json.dumps({k:report[k] for k in ('exit_code','wall_seconds','process_cpu_one_second_p95','process_rss_peak_bytes','process_threads_peak')}))
if __name__=='__main__':main()
