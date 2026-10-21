import json,os,subprocess,time,tempfile
from pathlib import Path
SWAY='/nix/store/04g9x522ddd3hi77v013n97li9ccyrhd-sway-1.12/bin/sway';SWAYMSG=SWAY.replace('/sway','/swaymsg') if False else '/nix/store/04g9x522ddd3hi77v013n97li9ccyrhd-sway-1.12/bin/swaymsg'
GRIM='/nix/store/7scglgqhmxl5gj585y0h2nq699rspg4g-grim-1.5.0/bin/grim';BUN='/home/tom/today/2026-10-14-convergence-soak/build/bun/bin/bun'
P=Path(__file__).resolve().parent
def wait(fn,label):
 for _ in range(200):
  v=fn()
  if v:return v
  time.sleep(.1)
 raise RuntimeError(label)
runtime=Path(os.environ['XDG_RUNTIME_DIR']);assert not (runtime/'bus').exists()
out=Path(tempfile.mkdtemp(prefix='gpuix-rail-probe-'));print('evidence',out,flush=True)
(out/'sway.conf').write_text('output HEADLESS-1 mode 1440x900 bg #202020 solid_color\nxwayland disable\nseat seat0 fallback true\n')
libs=['libxkbcommon','wayland-1','vulkan-loader','fontconfig','freetype','libglvnd','libx11','libxcb','openssl','gcc-15']
dirs=[]
for lib in libs:
 dirs+=[str(p/'lib') for p in Path('/nix/store').glob('*-'+lib+'*') if (p/'lib').is_dir() and not p.name.endswith('.drv')]
os.environ.update(LD_LIBRARY_PATH=':'.join(dirs),WLR_BACKENDS='headless',WLR_HEADLESS_OUTPUTS='1',WLR_RENDERER='gles2',WLR_RENDER_DRM_DEVICE='/dev/dri/renderD128',WLR_LIBINPUT_NO_DEVICES='1',SWAY_DISABLE_SD_NOTIFY='1',DBUS_SESSION_BUS_ADDRESS='unix:path=/nonexistent',DBUS_SYSTEM_BUS_ADDRESS='unix:path=/nonexistent',XDG_CURRENT_DESKTOP='sway',VK_ICD_FILENAMES='/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json')
sl=(out/'sway.log').open('w');sway=subprocess.Popen([SWAY,'--unsupported-gpu','-c',str(out/'sway.conf')],stdout=sl,stderr=subprocess.STDOUT)
app=None
try:
 os.environ['SWAYSOCK']=str(wait(lambda:next(iter(runtime.glob('sway-ipc*.sock')),None),'ipc'))
 os.environ['WAYLAND_DISPLAY']=wait(lambda:next((p.name for p in runtime.glob('wayland-*') if p.is_socket()),None),'wl')
 al=(out/'app.log').open('w');app=subprocess.Popen([BUN,str(P/'rail.tsx')],cwd=P,stdout=al,stderr=subprocess.STDOUT)
 time.sleep(4)
 if app.poll() is not None:raise RuntimeError('app exited '+str(app.returncode)+'\n'+(out/'app.log').read_text())
 subprocess.run([GRIM,'-o','HEADLESS-1',str(out/'shot.png')],check=True)
 from PIL import Image
 im=Image.open(out/'shot.png').convert('RGB');print('size',im.size,'px(10,450)',im.getpixel((10,450)),'px(200,450)',im.getpixel((200,450)),'px(16+6,12+15*2+2)',im.getpixel((28,80)))
 # exclusive zone check: open a kitty-less test: ask sway for workspace rect via get_workspaces
 ws=json.loads(subprocess.run([SWAYMSG,'-r','-t','get_workspaces'],capture_output=True,text=True).stdout);print('workspace rect',ws[0]['rect'])
finally:
 if app and app.poll() is None:app.terminate();app.wait(timeout=5)
 sway.terminate();sway.wait(timeout=5)
print((out/'app.log').read_text()[-800:])
