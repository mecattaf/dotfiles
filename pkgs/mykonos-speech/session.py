#!/usr/bin/env python3
"""Create exactly one dedicated persistent Claude/Herdr speech session per intake."""
import argparse, hashlib, json, os, re, socket, subprocess, sys, uuid
from pathlib import Path

def call(args):
    p=subprocess.run(args,capture_output=True,text=True,timeout=90)
    if p.returncode:raise RuntimeError((p.stderr or p.stdout).strip())
    result=json.loads(p.stdout)
    if result.get('error'):raise RuntimeError(str(result['error']))
    return result['result']

def main():
    p=argparse.ArgumentParser();p.add_argument('--stdin',action='store_true',required=True)
    p.add_argument('--cwd',type=Path,default=Path.home());p.add_argument('--no-window',action='store_true')
    p.add_argument('--projector',default='mykonos-projector');a=p.parse_args()
    if socket.gethostname()!='coordinator':p.error('Session launcher belongs on coordinator')
    text=sys.stdin.read(32769).strip()
    if not text or len(text)>32768 or '\0' in text:raise ValueError('Empty or oversized transcript')
    ident=str(uuid.uuid4()); name='speech-'+ident[:8]
    root=Path.home()/'.local/state/mykonos-sessions'/ident;root.mkdir(parents=True,mode=0o700)
    (root/'transcript.txt').write_text(text+'\n');os.chmod(root/'transcript.txt',0o600)
    system_file=Path(__file__).with_name('system.md')
    system_prompt=' '.join(system_file.read_text().split())
    (root/'system-prompt.txt').write_text(system_prompt+'\n')
    receipt=dict(session_id=ident,status='creating',cwd=str(a.cwd),transcript=str(root/'transcript.txt'),system_prompt_source=str(system_file),system_prompt_sha256=hashlib.sha256(system_prompt.encode()).hexdigest())
    def save(): (root/'session.json').write_text(json.dumps(receipt,indent=2)+'\n')
    save()
    try:
        created=call(['herdr','workspace','create','--cwd',str(a.cwd),'--label',name,'--no-focus'])
        pane=created['root_pane']['pane_id'];receipt.update(workspace=created['workspace'],pane=pane,terminal=created['root_pane']['terminal_id']);save()
        call(['herdr','agent','start',name,'--kind','claude','--pane',pane,'--timeout','60000','--','--dangerously-skip-permissions','--model','opus','--session-id',ident,'--append-system-prompt',system_prompt])
        receipt['status']='agent-ready';save()
        # Target the pane returned by creation, never the global focused terminal.
        if not a.no_window:
            subprocess.run(['ssh','-o','BatchMode=yes','client',a.projector,receipt['pane']],check=True,timeout=20)
        receipt['status']='submitting';save()
        call(['herdr','agent','prompt',name,text])
        receipt['status']='submitted';save();print(json.dumps(receipt))
    except Exception as exc:
        receipt.update(status='needs-review',error=str(exc));save()
        # Do not close the user's session or retry a potentially submitted turn.
        raise
if __name__=='__main__':main()
