#!/usr/bin/env python3
"""Native SSH lifecycle regression, using the real launcher and an in-process SSH fixture.

Run: runtime-test -- python3 tests/native-nvim/native_ssh.py --nvim /path/to/nvim
The fixture runs upstream remote_ssh.sh and Unix forwarding, never a network SSH
or a live terminal. All input below belongs to its private pseudo-terminals.
"""
import argparse
import fcntl
import json
import os
import pty
import select
import shlex
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path
assert Path('/proc/1/comm').read_text().strip()=='bwrap', 'run this test through runtime-test'
assert not Path(f'/run/user/{os.getuid()}/systemd/private').exists()
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--nvim', required=True, help='qualified Neovim 0.13 executable')
parser.add_argument('--source-root', type=Path, default=Path(__file__).resolve().parents[2])
args = parser.parse_args()
BIN = Path(args.nvim).resolve()
SHELL = shutil.which('sh')
assert SHELL, 'POSIX sh is required'
ROOT = Path(tempfile.mkdtemp(prefix='nvim-native-route-', dir=os.environ.get('TMPDIR', '/tmp')))
for n in ['bin','local-home','local-config/nvim','local-data','local-state','local-cache','remote-home','remote-config','remote-data','remote-state','remote-cache','seat1/run','seat2/run','seat3/run','remote-seat/run','remote-cwd','other-cwd']:(ROOT/n).mkdir(parents=True,exist_ok=True)
(ROOT/'local-config/nvim/lua').mkdir()
module=(args.source_root/'home/dot_local/bin/nvim-lua/native_remote.lua').read_text()
(ROOT/'local-config/nvim/lua/native_remote.lua').write_text(module)
INIT=r"""
vim.g.native_config_copied=true
local native=require('native_remote')
local original=native.open
native.open=function(data)
 local root,round=vim.env.PROBE_ROOT,vim.env.PROBE_ROUND
 local before={pid=vim.fn.getpid(),config=vim.g.native_config_copied,vim_did_enter=vim.v.vim_did_enter}
 vim.fn.writefile({vim.json.encode(before)},root..'/callback-before-'..round..'.json')
 original(data)
 local proof={cwd=vim.fn.getcwd(),name=vim.api.nvim_buf_get_name(0),lines=vim.api.nvim_buf_get_lines(0,0,-1,true),pid=vim.fn.getpid(),server=vim.v.servername,ui_count=#vim.api.nvim_list_uis(),copied_config=vim.g.native_config_copied,vim_did_enter=vim.v.vim_did_enter,marker=vim.g.native_nvim_directory}
 vim.fn.writefile({vim.json.encode(proof)},root..'/remote-'..round..'.json')
end
"""
(ROOT/'local-config/nvim/init.lua').write_text(INIT)
(ROOT/'remote-cwd/file with spaces.txt').write_text('REMOTE ORIGINAL\n')
(ROOT/'other-cwd/file with spaces.txt').write_text('OTHER DIRECTORY\n')
(ROOT/'bin/nvim').write_text('#!'+SHELL+'\nexec '+shlex.join([str(BIN)])+' "$@"\n');(ROOT/'bin/nvim').chmod(0o755)
FAKE=r'''import os,sys,json,socket,threading,select,time,subprocess,signal
from pathlib import Path
root=Path(os.environ['PROBE_ROOT']);args=sys.argv[1:]
with open(root/'ssh-calls.jsonl','a') as f:f.write(json.dumps(args)+'\n')
if '-G' in args:
 print('hostname nas\nstricthostkeychecking yes\nserveraliveinterval 15');sys.exit(0)
# Parse only the options emitted by native Neovim.
i=0;forward=None;operation=None
while i<len(args):
 a=args[i]
 if a in ['-o','-p','-L','-O']:
  if a=='-L':forward=args[i+1]
  if a=='-O':operation=args[i+1]
  i+=2
 elif a in ['-T','-N']:i+=1
 elif a=='--':i+=1;break
 else:break
assert args[i]=='nas',args
i+=1;cmd=args[i:]
if os.environ.get('PROBE_BAD_VERSION')=='1' and cmd==['nvim --version']:
 print('NVIM v0.12.4');sys.exit(0)
if operation:
 if operation=='cancel' and forward:
  local=forward.split(':',1)[0]
  try:os.unlink(local)
  except FileNotFoundError:pass
 sys.exit(0)
if forward:
 local,remote=forward.split(':',1)
 listener=socket.socket(socket.AF_UNIX);listener.bind(local);listener.listen()
 def relay(peer):
  target=socket.socket(socket.AF_UNIX)
  end=time.monotonic()+8
  while True:
   try:target.connect(remote);break
   except (FileNotFoundError,ConnectionRefusedError):
    if time.monotonic()>end:peer.close();target.close();return
    time.sleep(.02)
  try:
   while True:
    ready=select.select([peer,target],[],[],1)[0]
    for src in ready:
     data=src.recv(65536)
     if not data:return
     (target if src is peer else peer).sendall(data)
  finally:peer.close();target.close()
 def accept():
  while True:
   try:peer,_=listener.accept()
   except OSError:return
   threading.Thread(target=relay,args=(peer,),daemon=True).start()
 threading.Thread(target=accept,daemon=True).start()
remote_env=dict(os.environ,HOME=str(root/'remote-home'),XDG_CONFIG_HOME=str(root/'remote-config'),XDG_DATA_HOME=str(root/'remote-data'),XDG_STATE_HOME=str(root/'remote-state'),XDG_CACHE_HOME=str(root/'remote-cache'),XDG_RUNTIME_DIR=str(root/'remote-seat/run'))
child=subprocess.Popen([os.environ['PROBE_SHELL'],'-c',' '.join(cmd)],env=remote_env)
signal.signal(signal.SIGTERM,lambda *_:child.terminate())
sys.exit(child.wait())
'''
(ROOT/'bin/ssh').write_text('#!'+sys.executable+'\n'+FAKE);(ROOT/'bin/ssh').chmod(0o755)
(ROOT/'bin/curl').write_text('#!'+SHELL+'\nexit 7\n');(ROOT/'bin/curl').chmod(0o755)
LOCAL=r'''
local directory=vim.env.PROBE_ROOT..'/'..(vim.env.PROBE_DIRECTORY or 'remote-cwd')
vim.env.NVIM_REMOTE_REQUEST=vim.json.encode({directory=directory,files={directory..'/file with spaces.txt'},commands={}})
require('native_remote').start()
'''
(ROOT/'connect.lua').write_text(LOCAL)
ENV={'HOME':str(ROOT/'local-home'),'PATH':str(ROOT/'bin')+':'+os.environ.get('PATH',''),'LANG':'C.UTF-8','TERM':'xterm-kitty','XDG_RUNTIME_DIR':str(ROOT/'seat1/run'),'XDG_CONFIG_HOME':str(ROOT/'local-config'),'XDG_DATA_HOME':str(ROOT/'local-data'),'XDG_STATE_HOME':str(ROOT/'local-state'),'XDG_CACHE_HOME':str(ROOT/'local-cache'),'PROBE_ROOT':str(ROOT),'PROBE_SHELL':SHELL}

STATE_LUA="return {pid=vim.fn.getpid(),cwd=vim.fn.getcwd(),name=vim.api.nvim_buf_get_name(0),lines=vim.api.nvim_buf_get_lines(0,0,-1,true),modified=vim.bo.modified,active=vim.v.useractive,ui_count=#vim.api.nvim_list_uis(),server=vim.v.servername}"
def rpc(sock,code):
 expr="json_encode(luaeval('(function() "+code.replace("'","''")+" end)()'))"
 r=subprocess.run([str(BIN),'--server',sock,'--remote-expr',expr],env=ENV,cwd=ROOT,text=True,capture_output=True,timeout=8)
 assert r.returncode==0,(r.returncode,r.stdout,r.stderr)
 return json.loads(r.stdout)
def start_ui(round,newrun=False,badversion=False,directory='remote-cwd'):
 master,slave=pty.openpty();fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',40,120,800,600))
 env=dict(ENV,PROBE_ROUND=str(round),PROBE_DIRECTORY=directory)
 if newrun:env['XDG_RUNTIME_DIR']=str(ROOT/'seat2/run')
 if badversion:env['PROBE_BAD_VERSION']='1';env['XDG_RUNTIME_DIR']=str(ROOT/'seat3/run')
 p=subprocess.Popen([str(ROOT/'bin/nvim'),'-u','NONE','-i','NONE','-c','luafile '+str(ROOT/'connect.lua')],env=env,cwd=ROOT,stdin=slave,stdout=slave,stderr=slave,start_new_session=True);os.close(slave)
 return {'p':p,'fd':master,'out':bytearray(),'confirmed':False,'round':round}
def pump(ui,dt=.1):
 fd=ui['fd']
 if not select.select([fd],[],[],dt)[0]:return
 try:c=os.read(fd,65536)
 except OSError:return
 ui['out'].extend(c)
 if b'\x1b[c' in c:os.write(fd,b'\x1b[?62;1;2;6;9;15;18;22c')
 if b'\x1b[6n' in c:os.write(fd,b'\x1b[1;1R')
 if b'\x1b]11;?' in c:os.write(fd,b'\x1b]11;rgb:0000/0000/0000\x1b\\')
 if b'Connect to ssh://nas' in ui['out'] and not ui['confirmed']:
  os.write(fd,b'y');ui['confirmed']=True
def wait_file(ui,name,seconds=30):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  pump(ui)
  if (ROOT/name).exists():return json.loads((ROOT/name).read_text())
  if ui['p'].poll() is not None:break
 raise AssertionError(('timeout',name,bytes(ui['out'][-2500:])))
def wait_exit(ui,seconds=5):
 end=time.monotonic()+seconds
 while time.monotonic()<end and ui['p'].poll() is None:pump(ui)
 assert ui['p'].poll() is not None,'UI did not detach'
def save(ui):(ROOT/('terminal-'+str(ui['round'])+'.bin')).write_bytes(ui['out'])
print('ROOT='+str(ROOT),flush=True)
uis=[]
try:
 ui=start_ui(1);uis.append(ui)
 fresh=wait_file(ui,'remote-1.json');print('FRESH='+json.dumps(fresh),flush=True)
 assert fresh['copied_config'] and fresh['vim_did_enter']==1
 assert fresh['cwd']==str(ROOT/'remote-cwd') and fresh['name']==str(ROOT/'remote-cwd/file with spaces.txt')
 oldsock=fresh['server'];oldpid=fresh['pid']
 os.write(ui['fd'],b'iUNSAVED-\x1b')
 for _ in range(8):pump(ui)
 dirty=rpc(oldsock,STATE_LUA);print('DIRTY='+json.dumps(dirty),flush=True)
 assert dirty['modified'] and dirty['active']>0 and dirty['lines']==['UNSAVED-REMOTE ORIGINAL']
 os.write(ui['fd'],b':detach\r');wait_exit(ui)
 detached=rpc(oldsock,STATE_LUA);print('DETACHED='+json.dumps(detached),flush=True)
 assert detached['ui_count']==0 and detached['pid']==oldpid and detached['modified']
 def install_reconnect(name):
  code="vim.api.nvim_create_autocmd('UIEnter',{once=true,callback=function() vim.schedule(function() local x=(function() "+STATE_LUA+" end)(); vim.fn.writefile({vim.json.encode(x)},vim.env.PROBE_ROOT..'/"+name+"') end) end}); return true"
  assert rpc(oldsock,code)
 install_reconnect('reconnected-local.json')
 ui2=start_ui(2);uis.append(ui2)
 local_reused=wait_file(ui2,'reconnected-local.json');print('LOCAL_REUSED='+json.dumps(local_reused),flush=True)
 assert local_reused['pid']==oldpid and local_reused['modified'] and local_reused['lines']==dirty['lines'] and local_reused['ui_count']==1
 assert not (ROOT/'callback-before-2.json').exists(),'local tunnel reuse unexpectedly bootstrapped another remote'
 os.write(ui2['fd'],b':detach\r');wait_exit(ui2)
 install_reconnect('reconnected.json')
 ui3=start_ui(3,newrun=True);uis.append(ui3)
 reattached=wait_file(ui3,'reconnected.json');print('REATTACHED='+json.dumps(reattached),flush=True)
 bootstrap=json.loads((ROOT/'callback-before-3.json').read_text());print('BOOTSTRAP='+json.dumps(bootstrap),flush=True)
 assert reattached['pid']==oldpid and reattached['modified'] and reattached['lines']==dirty['lines'] and reattached['ui_count']==1
 end=time.monotonic()+4
 while time.monotonic()<end and Path('/proc/'+str(bootstrap['pid'])).exists():pump(ui3)
 bootstrap_proc=Path('/proc/'+str(bootstrap['pid']))
 bootstrap_status=(bootstrap_proc/'status').read_text() if bootstrap_proc.exists() else 'gone'
 print('BOOTSTRAP_STATUS='+bootstrap_status,flush=True)
 bootstrap_gone=not bootstrap_proc.exists() or '\nState:\tZ' in bootstrap_status
 assert bootstrap_gone, 'empty native bootstrap survived relink'
 final=rpc(oldsock,STATE_LUA)
 assert final['pid']==oldpid and final['modified'] and final['lines']==dirty['lines']
 assert (ROOT/'remote-cwd/file with spaces.txt').read_text()=='REMOTE ORIGINAL\n'
 calls_before=(ROOT/'ssh-calls.jsonl').read_text().splitlines()
 ui4=start_ui(4,badversion=True);uis.append(ui4);wait_exit(ui4)
 assert ui4['p'].returncode==2, 'old remote version preflight did not fail'
 calls_after=(ROOT/'ssh-calls.jsonl').read_text().splitlines()
 rejected_calls=[json.loads(line) for line in calls_after[len(calls_before):]]
 assert len(rejected_calls)==1 and rejected_calls[0][-1]=='nvim --version', rejected_calls
 print('PREFLIGHT_GUARD=PASS',flush=True)
 ui5=start_ui(5,directory='other-cwd');uis.append(ui5)
 other=wait_file(ui5,'remote-5.json')
 assert other['pid']!=oldpid and other['cwd']==str(ROOT/'other-cwd')
 assert other['lines']==['OTHER DIRECTORY']
 assert rpc(oldsock,STATE_LUA)['lines']==dirty['lines'], 'another directory changed the retained buffer'
 print('DIRECTORIES_DISTINCT=PASS',flush=True)
 receipt={'binary':str(BIN),'version':subprocess.check_output([str(BIN),'--version'],env=ENV,text=True).splitlines()[0],'fresh':fresh,'dirty':dirty,'detached':detached,'local_tunnel_reused':local_reused,'reattached':reattached,'bootstrap':bootstrap,'bootstrap_exited':bootstrap_gone,'disk_unchanged':True,'older_remote_rejected_before_native_connect':True,'other_directory':other,'isolated':True,'network':'private namespace, no network transport; native ssh command runner fixture only'}
 (ROOT/'results.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print('NATIVE_LIFECYCLE_PROOF=PASS',flush=True)
finally:
 for ui in uis:
  save(ui)
  if ui['p'].poll() is None:
   ui['p'].terminate()
   try:ui['p'].wait(timeout=3)
   except subprocess.TimeoutExpired:ui['p'].kill();ui['p'].wait()
  os.close(ui['fd'])
