#!/usr/bin/env python3
"""Run ONLY through runtime-test: isolated two-output Sway + actual Fuzzel."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from PIL import Image,ImageChops
ROOT=Path(__file__).resolve().parents[2]
SWAY='/nix/store/04g9x522ddd3hi77v013n97li9ccyrhd-sway-1.12/bin/sway'
FUZZEL='/nix/store/32iwmf6ipnxnnzcvmlrnxdbk1x1cq3qc-fuzzel-1.14.1/bin'
WTYPE='/nix/store/bx230ccz3klvqr2fxgjz10w1r3m45grq-wtype-0.4/bin/wtype'
GRIM='/nix/store/7scglgqhmxl5gj585y0h2nq699rspg4g-grim-1.5.0/bin/grim'
HELPER=ROOT/'home/dot_local/bin/sway-workspace-switcher'

def run(*args):return subprocess.run([str(a) for a in args],capture_output=True,text=True,check=True,timeout=10)
def wait(fn,label):
    for _ in range(100):
        result=fn()
        if result:return result
        time.sleep(.1)
    raise AssertionError(label)
def main():
    runtime=Path(os.environ['XDG_RUNTIME_DIR']);assert not (runtime/'bus').exists();assert not Path('/dev/input').exists()
    evidence=Path(tempfile.mkdtemp(prefix='sway-switcher-smoke-'));(evidence/'bin').mkdir();(evidence/'config/theme').mkdir(parents=True)
    print(f'Evidence: {evidence}',flush=True)
    (evidence/'bin/herdr').write_text('#!/bin/sh\nprintf \'{"workspaces":[],"agents":[]}\\n\'\n');(evidence/'bin/herdr').chmod(0o755)
    palettes=json.loads((ROOT/'design/claude-primer/src/palettes.json').read_text());(evidence/'config/theme/desktop-shell.json').write_text(json.dumps(palettes['claude-light']))
    config=evidence/'sway.conf';config.write_text(f'''output HEADLESS-1 mode 1280x720 position 0 0 bg #D2D1C7 solid_color
output HEADLESS-2 mode 1280x720 position 0 720 bg #52514E solid_color
workspace 10 output HEADLESS-1
workspace 4 output HEADLESS-2
xwayland disable
seat seat0 fallback true
bindsym Mod4+i exec {sys.executable} {HELPER} --output HEADLESS-1
''')
    os.environ.update(WLR_BACKENDS='headless',WLR_HEADLESS_OUTPUTS='2',WLR_RENDERER='pixman',WLR_LIBINPUT_NO_DEVICES='1',SWAY_DISABLE_SD_NOTIFY='1',DBUS_SESSION_BUS_ADDRESS='unix:path=/nonexistent-test-bus',DBUS_SYSTEM_BUS_ADDRESS='unix:path=/nonexistent-system-bus',HERDR_SWAY_LOCAL='1',XDG_CURRENT_DESKTOP='sway',XDG_CONFIG_HOME=str(evidence/'config'),PATH=str(evidence/'bin')+':'+FUZZEL+':'+str(Path(SWAY).parent)+':'+os.environ['PATH'])
    log=(evidence/'sway.log').open('w');sway=subprocess.Popen([SWAY,'--unsupported-gpu','-c',str(config)],stdout=log,stderr=subprocess.STDOUT)
    def query(name):return json.loads(run('swaymsg','-r','-t',name).stdout)
    def command(value):run('swaymsg','-r','--',value)
    def toggles():return list((runtime/'sway-workspace-switcher').glob('*.sock'))
    keyboard=None
    try:
        sock=wait(lambda:next(iter(runtime.glob('sway-ipc*.sock')),None),'Sway IPC');os.environ['SWAYSOCK']=str(sock)
        wayland=wait(lambda:next((p for p in runtime.glob('wayland-*') if p.is_socket()),None),'Wayland');os.environ['WAYLAND_DISPLAY']=wayland.name
        keyboard=subprocess.Popen([WTYPE,'-s','120000'],stdout=log,stderr=subprocess.STDOUT)
        time.sleep(.2)
        command('workspace number 10');command('workspace number 4')
        before=query('get_workspaces');(evidence/'before.json').write_text(json.dumps(before,indent=2))
        assert next(w for w in before if w['num']==10)['output']=='HEADLESS-1'
        assert next(w for w in before if w['num']==4)['output']=='HEADLESS-2'
        rows=json.loads(run(sys.executable,HELPER,'--output','HEADLESS-1','--json').stdout)
        assert 10 in [r['slot'] for r in rows['workspaces']];assert 4 not in [r['slot'] for r in rows['workspaces']]
        (evidence/'rows.json').write_text(json.dumps(rows,indent=2))
        run(GRIM,'-o','HEADLESS-2',evidence/'bottom-before.png')
        run(WTYPE,'-M','logo','-k','i','-m','logo');wait(toggles,'Mod+i launches own socket');time.sleep(.5)
        run(GRIM,'-o','HEADLESS-1',evidence/'top-menu.png');run(GRIM,'-o','HEADLESS-2',evidence/'bottom-during.png')
        assert ImageChops.difference(Image.open(evidence/'bottom-before.png'),Image.open(evidence/'bottom-during.png')).getbbox() is None,'Lower output changed'
        run(WTYPE,'-M','logo','-k','i','-m','logo');wait(lambda:not toggles(),'Second Mod+i closes menu')
        run(WTYPE,'-M','logo','-k','i','-m','logo');wait(toggles,'Menu reopens');time.sleep(.4)
        run(WTYPE,'10');run(WTYPE,'-k','Return');wait(lambda:not toggles(),'Selection closes')
        after=query('get_workspaces');(evidence/'after.json').write_text(json.dumps(after,indent=2))
        assert next(w for w in after if w['num']==10)['focused']
        assert next(w for w in after if w['num']==4)['output']=='HEADLESS-2'
        run(WTYPE,'-M','logo','-k','i','-m','logo');wait(toggles,'Menu reopens for Escape');time.sleep(.4);run(WTYPE,'-k','Escape');wait(lambda:not toggles(),'Escape closes')
        result={'ok':True,'checks':['actual Mod+i opens and toggles','explicit top output while lower focused','lower output pixels unchanged','actual output10 included/lower4 excluded','keyboard selection focuses10 without moving4','Escape cancellation'],'scope':'Private headless Sway/Fuzzel; mocked read-only Herdr snapshot, real Sway IPC and native rendering.'}
        (evidence/'results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True)
    finally:
        if keyboard:
            keyboard.terminate();keyboard.wait(timeout=3)
        sway.terminate()
        try:sway.wait(timeout=5)
        except subprocess.TimeoutExpired:sway.kill();sway.wait();print('Sway needed SIGKILL',file=sys.stderr)
        log.close()
if __name__=='__main__':main()
