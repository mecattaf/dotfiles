#!/usr/bin/env python3
"""Actual Kitty/hc overlay regression; requires runtime-test and a private Xvfb.

No live desktop, terminal input or clipboard is touched. A mock local editor
lets the production NAS launcher prove blocking, origin binding and status.
"""
import argparse
import hashlib
import json
import os
import select
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
assert Path('/proc/1/comm').read_text().strip()=='bwrap','runtime-test required'
assert not Path(f'/run/user/{os.getuid()}/systemd/private').exists()
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--kitty', type=Path, required=True)
parser.add_argument('--hc', type=Path, required=True)
parser.add_argument('--xvfb', type=Path, required=True)
parser.add_argument('--dri-drivers', help='software Mesa drivers, if not found by the GL loader')
parser.add_argument('--source-root', type=Path, default=Path(__file__).resolve().parents[2])
args = parser.parse_args()
root=Path(tempfile.mkdtemp(prefix='hc-kitty-overlay-',dir=os.environ.get('TMPDIR','/tmp')))
print('ROOT='+str(root),flush=True)
kitty=args.kitty.resolve()
kitten=kitty.parent/'kitten'
hc=args.hc.resolve()
xvfb=args.xvfb.resolve()
source=args.source_root/'home/dot_local/bin/nvim-remote'
for n in ['bin','run','config/herdr-core','state','cache','data']:(root/n).mkdir(parents=True,exist_ok=True)
(root/'bin/kitten').symlink_to(kitten)
(root/'config/herdr-core/config.toml').write_text('notes=false\nheadless="120x40"\n')
env={'HOME':str(root),'PATH':str(root/'bin')+':'+os.environ['PATH'],'USER':os.environ.get('USER','tom'),'LANG':'C.UTF-8','XDG_RUNTIME_DIR':str(root/'run'),'XDG_CONFIG_HOME':str(root/'config'),'XDG_STATE_HOME':str(root/'state'),'XDG_CACHE_HOME':str(root/'cache'),'XDG_DATA_HOME':str(root/'data'),'HC_SESSION':'overlaytest','HC_SETTLE_MS':'0','PROBE_ROOT':str(root),'LIBGL_ALWAYS_SOFTWARE':'1'}
if args.dri_drivers:env['LIBGL_DRIVERS_PATH']=args.dri_drivers
ui=r'''import json,os,signal,subprocess,sys,time
from pathlib import Path
r=Path(os.environ['PROBE_ROOT'])
case=(r/'case').read_text()
e=dict(os.environ);e.pop('KITTY_LISTEN_ON',None)
p=subprocess.run(['kitten','@','ls','--match','state:overlay_parent'],env=e,capture_output=True,text=True,timeout=8)
(r/('ui-'+case+'.json')).write_text(json.dumps({'argv':sys.argv[1:],'window_id':os.environ.get('KITTY_WINDOW_ID'),'parent_query_code':p.returncode,'parent_query':p.stdout,'parent_query_err':p.stderr}))
end=time.monotonic()+15
while not (r/('ui-'+case+'-release')).exists() and time.monotonic()<end:time.sleep(.03)
if case=='signal':os.kill(os.getpid(),signal.SIGTERM)
sys.exit(7)
'''
(root/'bin/nvim-remote').write_text('#!'+sys.executable+'\n'+ui);(root/'bin/nvim-remote').chmod(0o755)
worker=r'''import json,os,subprocess,time
from pathlib import Path
r=Path(os.environ['PROBE_ROOT'])
(r/'worker-ready').touch()
end=time.monotonic()+25
while not (r/'worker-go').exists() and time.monotonic()<end:time.sleep(.03)
e=dict(os.environ);e['NVIM_REMOTE_ROLE']='brain';e.pop('KITTY_LISTEN_ON',None)
for case in ('exit7','signal'):
 (r/'case').write_text(case)
 p=subprocess.run([os.environ['PROBE_LAUNCHER'],'--directory',str(r),'--',"a 'quoted' `literal`.md"],env=e)
 (r/('worker-result-'+case+'.json')).write_text(json.dumps({'returncode':p.returncode}))
time.sleep(3)
'''
(root/'worker.py').write_text(worker)
env['PROBE_LAUNCHER']=str(source)
logs={'kitty_binary':str(kitty),'hc_binary':str(hc),'xvfb_binary':str(xvfb),
      'launcher':str(source),'launcher_sha256':hashlib.sha256(source.read_bytes()).hexdigest()}
processes=[]
def wait_file(path,timeout=15):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  if path.exists():return
  time.sleep(.04)
 raise AssertionError('missing '+str(path))
def run(argv,timeout=10):
 p=subprocess.run([str(x) for x in argv],env=env,cwd=root,text=True,capture_output=True,timeout=timeout)
 assert p.returncode==0,(argv,p.returncode,p.stdout,p.stderr)
 return p.stdout
try:
 xf=open(root/'xvfb.log','w')
 xp=subprocess.Popen([str(xvfb),'-displayfd','1','-screen','0','1024x768x24','-nolisten','tcp','-ac','-noreset'],env=env,stdout=subprocess.PIPE,stderr=xf,text=True);processes.append(xp)
 assert select.select([xp.stdout],[],[],8)[0], 'Xvfb display timeout'
 display=xp.stdout.readline().strip();assert display.isdigit(),(display,(root/'xvfb.log').read_text());env['DISPLAY']=':'+display
 start=json.loads(run([hc,'--json','server','start']));logs['core_start']=start
 terminal=json.loads(run([hc,'--json','run','--bg','--no-parent','--no-notify','--name','overlay','--cwd',root,'--',sys.executable,root/'worker.py']));logs['terminal']=terminal
 tid=terminal.get('address') or terminal.get('id') or terminal.get('terminal',{}).get('id');assert tid,terminal
 wait_file(root/'worker-ready')
 sock=root/'kitty.sock'
 kl=open(root/'kitty.log','w')
 kp=subprocess.Popen([str(kitty),'--config','NONE','--override','linux_display_server=x11','--override','allow_remote_control=yes','--override','shell_integration=disabled','--override','confirm_os_window_close=0','--listen-on','unix:'+str(sock),str(hc),'attach',tid],env=env,cwd=root,stdout=kl,stderr=kl);processes.append(kp)
 wait_file(sock)
 def rc(*argv):return run([kitten,'@','--to','unix:'+str(sock),*argv])
 def windows():return [w for o in json.loads(rc('ls')) for t in o['tabs'] for w in t['windows']]
 ws=windows();assert len(ws)==1,ws
 origin=ws[0]['id'];logs['origin']=origin
 other=int(rc('launch','--type=tab','--',shutil.which('sleep'),'30').strip());logs['other']=other
 active_tabs=[t for o in json.loads(rc('ls')) for t in o['tabs'] if t['is_active']]
 assert len(active_tabs)==1 and [w['id'] for w in active_tabs[0]['windows']]==[other], active_tabs
 (root/'worker-go').touch()
 logs['cases']={}
 for case,expected in (('exit7',7),('signal',143)):
  wait_file(root/('ui-'+case+'.json'))
  info=json.loads((root/('ui-'+case+'.json')).read_text())
  assert info['argv']==['--ui','--directory',str(root),'--',"a 'quoted' `literal`.md"], info
  assert not (root/('worker-result-'+case+'.json')).exists(),'NAS vi returned before local UI exited'
  assert info['parent_query_code']==0,info
  parents=[w for o in json.loads(info['parent_query']) for t in o['tabs'] for w in t['windows']]
  assert [w['id'] for w in parents]==[origin],(origin,other,info)
  (root/('ui-'+case+'-release')).touch();wait_file(root/('worker-result-'+case+'.json'))
  result=json.loads((root/('worker-result-'+case+'.json')).read_text())
  assert result['returncode']==expected,result
  logs['cases'][case]={'argv':info['argv'],'overlay_window':int(info['window_id']),'parent_ids':[w['id'] for w in parents],'returncode':result['returncode'],'blocked_until_ui_exit':True}
 logs['passed']=True;logs['scope']='private Xvfb/Kitty0.50/hc0.1.22; real production NAS nvim-remote launcher, mock local UI exits7 or SIGTERM; no live desktop or clipboard'
 logs['binary_versions']={'kitty':run([kitty,'--version']).strip(),'hc':run([hc,'--version']).strip()}
 logs['source_root']=str(args.source_root)
 (root/'results.json').write_text(json.dumps(logs,indent=2)+'\n')
 print('OVERLAY_HC_WAITSTATUS=PASS',flush=True)
except BaseException:
 print('KITTY_LOG='+((root/'kitty.log').read_text() if (root/'kitty.log').exists() else ''),flush=True)
 print('HC_READ='+run([hc,'read','overlay']) if (root/'worker-ready').exists() else 'no worker',flush=True)
 raise
finally:
 for p in reversed(processes):
  if p.poll() is None:
   p.terminate()
   try:p.wait(timeout=4)
   except subprocess.TimeoutExpired:p.kill();p.wait()
 try:run([hc,'server','stop'])
 except Exception:pass
