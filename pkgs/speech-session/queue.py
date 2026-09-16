#!/usr/bin/env python3
"""One serial sweep of the coordinator's Markdown speech queue."""
import argparse, datetime, fcntl, json, os, shutil, socket, subprocess, time
from pathlib import Path

def quiet(now=None):
    return (now or datetime.datetime.now().astimezone()).hour < 6

def atomic(path, obj):
    temp=path.with_name('.'+path.name+'.tmp');temp.write_text(json.dumps(obj,indent=2)+'\n');temp.replace(path)

def plain(source):
    # Pandoc handles links, Markdown structure and frontmatter deterministically.
    p=subprocess.run(['pandoc','--from=gfm','--to=plain','--wrap=none'],input=source,text=True,capture_output=True,check=True)
    return p.stdout.strip()

def sweep(root, qwen, player, default_seat="coordinator"):
    if default_seat not in ("client", "coordinator"): raise ValueError("Invalid playback seat")
    for name in ['intake','work','outbox','spoken','failed']:(root/name).mkdir(parents=True,exist_ok=True,mode=0o700)
    with (root/'.lock').open('a') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:return
        if quiet():return
        # A crashed playback has an uncertain audible outcome. Never replay blindly.
        for job in (root/'work').iterdir():
            if not job.is_dir():continue
            atomic(job/'failure.json',dict(error='Interrupted job; manual review required, no automatic replay'))
            job.rename(root/'failed'/job.name)
        for path in sorted((root/'intake').glob('*.md')):
            if path.name.startswith('.') or path.is_symlink():continue
            if path.stat().st_size>1024*1024:continue
            job=root/'outbox'/path.stem
            if any((root/d/path.stem).exists() for d in ['outbox','work','spoken','failed']):continue
            job.mkdir(mode=0o700);path.rename(job/'source.md')
        for queued in sorted((root/'outbox').iterdir()):
            if quiet():break
            if not queued.is_dir():continue
            job=root/'work'/queued.name;queued.rename(job)
            try:
                txt=job/'spoken.txt';audio=job/'speech.wav'
                if not txt.exists():txt.write_text(plain((job/'source.md').read_text())+'\n')
                if not txt.read_text().strip():raise ValueError('No spoken text')
                started=time.monotonic()
                if not audio.exists():
                    subprocess.run([qwen,'speak','--remote-command',qwen,'--file',str(txt),'--output',str(audio)],check=True,timeout=1800)
                if quiet():job.rename(queued);break
                seat = job.name.split('--', 1)[0] if job.name.startswith(('client--', 'coordinator--')) else default_seat
                command = [player] if seat == socket.gethostname() else ['ssh','-o','BatchMode=yes','-o','ConnectTimeout=5',seat,player]
                with audio.open('rb') as data:
                    result=subprocess.run(command,stdin=data,timeout=1800)
                if result.returncode==75:
                    job.rename(queued);break
                if result.returncode:raise RuntimeError(f'Playback incomplete or uncertain: exit {result.returncode}; not replayed automatically')
                atomic(job/'receipt.json',dict(status='played',completed=datetime.datetime.now().astimezone().isoformat(),elapsed_seconds=time.monotonic()-started,voice='accepted Qwen Base K2SO',client=seat,playback_evidence='pw-play exited successfully; not a microphone audibility check'))
                job.rename(root/'spoken'/job.name)
            except Exception as exc:
                atomic(job/'failure.json',dict(error=str(exc)));job.rename(root/'failed'/job.name)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=Path.home()/'Speech');p.add_argument('--qwen',default='qwen-speech');p.add_argument('--player',default='speech-play');a=p.parse_args()
    if socket.gethostname()!='coordinator':p.error('Speech queue belongs on coordinator')
    os.umask(0o077);sweep(a.root,a.qwen,a.player)
