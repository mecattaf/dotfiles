#!/usr/bin/env python3
"""Private real Kitty/Domicile/Nvim qualification; SSH command is a local fixture.

Run only through runtime-test on compute. No production session or credentials
are used. KITTY_EDITOR_NVIM_TREE points to a staged upstream nvim-tree checkout.
"""
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid


ROOT = Path(__file__).resolve().parents[2]
KITTY = '/nix/store/jvhn8sy84klkfkd4az26m5nkjbma7ni3-kitty-0.48.0/bin/kitty'
KITTEN = str(Path(KITTY).with_name('kitten'))
DOMICILE = os.environ.get('KITTY_EDITOR_DOMICILE', '/nix/store/qvjsa1g98hhwllzhyhflafi9cmh74n4k-domicile/bin/domicile')
HELPER = ROOT / 'home/dot_config/kitty/agency_editor.py'


def main():
    proof = ROOT / ('native-proof-' + time.strftime('%Y%m%d-%H%M%S'))
    proof.mkdir()
    private = proof / 'private'
    private.mkdir()
    for name in ('config', 'cache', 'data', 'state', 'bin'):
        (private / name).mkdir()
    project = proof / 'project'
    project.mkdir()
    original = project / 'notes.md'
    original.write_text('Original saved content\n')
    nvimtree = Path(os.environ['KITTY_EDITOR_NVIM_TREE']).resolve()
    nvimconf = private / 'config/nvim'
    nvimconf.mkdir()
    (nvimconf / 'init.lua').write_text(
        "vim.opt.rtp:append(" + json.dumps(str(nvimtree)) + ")\n"
        "package.path = package.path .. ';' .. vim.env.DSH_EDITOR_LUA .. '/?.lua;" +
        str(ROOT / 'home/dot_config/nvim/lua/?.lua') + "'\n"
        "vim.g.mapleader=' '; require('nvim-tree').setup({view={side='left'}})\n"
        "require('kitty_editor').setup()\n"
        "dofile(" + json.dumps(str(ROOT / 'home/nvim/mappings.lua.in')) + ")\n")
    # Only the SSH command boundary is replaced. Native windows, terminal
    # parsing, keyboard encoding, Nvim TUI, tree and server are all real.
    sshfixture = private / 'bin/kitten'
    sshfixture.write_text(
        '#!/usr/bin/env python3\nimport json,os,shlex,sys\nfrom pathlib import Path\n'
        "if len(sys.argv)>1 and sys.argv[1]=='ssh':\n"
        " command=shlex.split(sys.argv[-1]); command[0]=" + repr(str(ROOT / 'home/dot_local/bin')) + "+'/' + Path(command[0]).name\n"
        " with open(" + repr(str(proof / 'ssh-fixture.jsonl')) + ",'a') as f:f.write(json.dumps(command)+'\\n')\n"
        " os.execvpe(command[0],command,os.environ)\n"
        "os.execv(" + repr(KITTEN) + ", [" + repr(KITTEN) + ",*sys.argv[1:]])\n")
    sshfixture.chmod(0o755)
    bridge = private / 'bin/agency-kitty'
    bridge.write_text(
        '#!/usr/bin/env python3\nimport argparse,base64,json,os,subprocess,sys\n'
        "if len(sys.argv)>1 and sys.argv[1] in ('editor-attach','editor-tree-attach'):\n"
        " command=[" + repr(str(ROOT / 'home/dot_local/bin')) + "+('/dsh-editor-tree' if sys.argv[1]=='editor-tree-attach' else '/dsh-editor'),*sys.argv[2:]]\n"
        " with open(" + repr(str(proof / 'ssh-fixture.jsonl')) + ",'a') as f:f.write(json.dumps(command)+'\\n')\n"
        " os.execvpe(command[0],command,os.environ)\n"
        "p=argparse.ArgumentParser();p.add_argument('action');p.add_argument('--kitty-socket');p.add_argument('--window-id',type=int);p.add_argument('--child-pid',type=int);p.add_argument('--session');p.add_argument('--directory');p.add_argument('files',nargs='*');a=p.parse_args()\n"
        "payload={k:getattr(a,k) for k in ('window_id','child_pid','session','directory','files')}\n"
        "with open(" + repr(str(proof / 'bridge.jsonl')) + ",'a') as f:f.write(json.dumps(payload)+'\\n')\n"
        "token=base64.urlsafe_b64encode(json.dumps(payload).encode()).decode()\n"
        "sys.exit(subprocess.call([" + repr(KITTEN) + ",'@','--to',a.kitty_socket,'kitten','--match','id:'+str(a.window_id)," + repr(str(HELPER)) + ",'open-editor',token]))\n")
    bridge.chmod(0o755)
    session = str(uuid.uuid4())
    parent = proof / 'parent.py'
    parent.write_text(
        "import base64,json,os,sys,time\n"
        "tags=" + repr({'agency_host': 'nas', 'agency_session': session, 'agency_directory': str(project)}) + "\n"
        "for key,val in tags.items(): print('\\033]1337;SetUserVar='+key+'='+base64.b64encode(val.encode()).decode()+'\\033\\\\',end='',flush=True)\n"
        "print('Parent terminal retained',os.getpid(),flush=True)\n"
        "while True:time.sleep(1)\n")
    # Domicile watches the config's directory recursively. Keep mutable proof
    # logs/state out of it or each log write causes a shell reload.
    (proof / 'source').mkdir()
    source = proof / 'source/domicile.tsx'
    source.write_text('import {runManganese} from "@domicile-desktop/manganese"; export const Shell=runManganese({}); export const shell_options={nightLight:{schedule:"off"}};')
    close_watcher = proof / 'closed_windows.py'
    close_watcher.write_text(
        'from pathlib import Path\n'
        'def on_close(boss,window,data):\n'
        ' Path(' + repr(str(proof)) + ", 'closed-window-'+str(window.id)+'.txt').write_text(window.as_text())\n")
    env = dict(os.environ, XDG_CONFIG_HOME=str(private / 'config'),
               XDG_CACHE_HOME=str(private / 'cache'), XDG_DATA_HOME=str(private / 'data'),
               XDG_STATE_HOME=str(private / 'state'), PATH=str(private / 'bin') + ':' + os.environ['PATH'],
               OZONE='headless', DOMICILE_SOFTWARE_COMPOSITING='yes', LIBGL_ALWAYS_SOFTWARE='true',
               GALLIUM_DRIVER='llvmpipe', DOMICILE_ENGINE_ARGS='--no-sandbox --no-first-run')
    for key in ('DOMICILE_SOCK', 'DOMICILE_CONFIG_FILE', 'DOMICILE_CONSOLE_TRIAL_PATH', 'DOMICILE_ENGINE'):
        env.pop(key, None)
    desktoplog = (proof / 'domicile.log').open('w')
    desktop = subprocess.Popen([DOMICILE, '--config', str(source)], env=env, stdout=desktoplog, stderr=subprocess.STDOUT)
    monitor = None
    viewer = None
    receipt = {'sshTransport': 'local command fixture; no SSH credentials used', 'session': session,
               'kitty': KITTY, 'nvimTree': str(nvimtree), 'sourceDirectory': str(project)}
    logs = []

    def wait(callback, label, seconds=30):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if desktop.poll() is not None:
                raise RuntimeError('private Domicile exited: ' + label)
            try:
                value = callback()
                if value:
                    return value
            except (OSError, ValueError, subprocess.SubprocessError):
                pass
            time.sleep(0.1)
        raise TimeoutError(label)

    try:
        def compositor():
            text = (proof / 'domicile.log').read_text()
            ipc = re.search(r'DOMICILE_SOCK=(\S+)', text)
            display = re.search(r'WAYLAND_DISPLAY.*?display="([^"]+)"', text)
            return (ipc.group(1), display.group(1)) if ipc and display else None
        ipc, display = wait(compositor, 'private compositor')
        env.update(DOMICILE_SOCK=ipc, WAYLAND_DISPLAY=display)
        wait(lambda: 'the splash gave way to' in (proof / 'domicile.log').read_text(), 'private shell')
        monlog = (proof / 'monitor.log').open('w'); logs.append(monlog)
        monitor = subprocess.Popen([DOMICILE, 'monitor', 'Native editor proof', '1440x1000', '1'],
                                   env=env, stdin=subprocess.PIPE, stdout=monlog, stderr=desktoplog)
        time.sleep(1)
        control = 'unix:' + str(Path(os.environ['XDG_RUNTIME_DIR']) / 'editor-proof-kitty.sock')
        kittylog = (proof / 'kitty.log').open('w'); logs.append(kittylog)
        viewer = subprocess.Popen([KITTY, '--config', 'NONE', '--listen-on', control,
                                   '--watcher', str(close_watcher),
                                   '--override', 'allow_remote_control=yes', '--override', 'enabled_layouts=splits',
                                   '--override', 'confirm_os_window_close=0', '-e', 'python3', str(parent)],
                                  env=env, stdout=kittylog, stderr=subprocess.STDOUT)

        def remote(*args):
            result = subprocess.run([KITTEN, '@', '--to', control, *args], env=env, text=True,
                                    capture_output=True, timeout=5)
            if result.returncode:
                with (proof / 'remote-errors.log').open('a') as errors:
                    errors.write(repr(args) + '\n' + result.stderr + '\n')
                raise subprocess.CalledProcessError(result.returncode, args, result.stdout, result.stderr)
            return result.stdout

        def windows():
            return [w for oswindow in json.loads(remote('ls')) for tab in oswindow['tabs'] for w in tab['windows']]

        parentwindow = wait(lambda: next((w for w in windows() if w.get('user_vars', {}).get('agency_session') == session), None), 'parent terminal identity')
        parentid = parentwindow['id']
        receipt['parentWindowId'] = parentid
        remote('kitten', '--match', 'id:' + str(parentid), str(HELPER), 'sidebar')
        picker = wait(lambda: next((w for w in windows() if w.get('user_vars', {}).get('agency_editor_picker') == '1'), None), 'left tree opens')
        pickerid = picker['id']
        wait(lambda: 'notes.md' in remote('get-text', '--match', 'id:' + str(pickerid), '--extent=screen'), 'real nvim-tree rows')
        parentwindow = next(w for w in windows() if w['id'] == parentid)
        assert parentid in picker['neighbors'].get('right', []), (picker, parentwindow)
        receipt['leftSidebarLayout'] = {'tree': {'columns': picker['columns'], 'neighbors': picker['neighbors']},
                                       'parent': {'columns': parentwindow['columns'], 'neighbors': parentwindow['neighbors']}}
        remote('send-key', '--match', 'id:' + str(pickerid), 'shift+g', 'enter')
        # G is the last tree row, the only file in this private project.
        editor = wait(lambda: next((w for w in windows() if w.get('user_vars', {}).get('agency_editor_window') == '1'), None), 'pick opens separate editor')
        editorid = editor['id']
        wait(lambda: 'Original saved content' in remote('get-text', '--match', 'id:' + str(editorid), '--extent=screen'), 'native editor buffer')
        assert next(w for w in windows() if w['id'] == parentid)['pid'] == parentwindow['pid']
        remote('send-key', '--match', 'id:' + str(editorid), 'i')
        remote('send-text', '--match', 'id:' + str(editorid), '--', 'UNFINISHED ')
        remote('send-key', '--match', 'id:' + str(editorid), 'escape')
        wait(lambda: 'UNFINISHED Original' in remote('get-text', '--match', 'id:' + str(editorid), '--extent=screen'), 'native key input')
        remote('kitten', '--match', 'id:' + str(editorid), str(HELPER), 'sidebar')
        wait(lambda: 'notes.md' in remote('get-text', '--match', 'id:' + str(editorid), '--extent=screen'), 'single Ctrl+B reaches NvimTreeFocus')
        assert len(windows()) == 2, windows()
        receipt['onePressCtrlB'] = True
        serverlist = subprocess.check_output([str(ROOT / 'home/dot_local/bin/dsh-editor'), '--list', '--json'], env=env, text=True)
        serverpid = json.loads(serverlist)[0]['pid']
        receipt['editorServerPid'] = serverpid
        remote('close-window', '--match', 'id:' + str(editorid))
        wait(lambda: len(windows()) == 1, 'editor UI closes, parent remains')
        payload = {'window_id': parentid, 'child_pid': next(w['pid'] for w in windows() if w['id'] == parentid), 'session': session, 'directory': str(project), 'files': [str(original)]}
        token = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode()
        remote('kitten', '--match', 'id:' + str(parentid), str(HELPER), 'open-editor', token)
        editor = wait(lambda: next((w for w in windows() if w.get('user_vars', {}).get('agency_editor_window') == '1'), None), 'editor UI reopens')
        screen = wait(lambda: remote('get-text', '--match', 'id:' + str(editor['id']), '--extent=screen')
                      if 'UNFINISHED Original' in remote('get-text', '--match', 'id:' + str(editor['id']), '--extent=screen') else None,
                      'unsaved native buffer survives UI close')
        (proof / 'restored-screen.txt').write_text(screen)
        serverlist = subprocess.check_output([str(ROOT / 'home/dot_local/bin/dsh-editor'), '--list', '--json'], env=env, text=True)
        assert json.loads(serverlist)[0]['pid'] == serverpid
        assert original.read_text() == 'Original saved content\n'
        receipt['sameServerAndUnsavedBufferAfterClose'] = True
        receipt['sourceFileUnchanged'] = True
        receipt['parentRetained'] = True
        subprocess.run([DOMICILE, 'screenshot', str(proof / 'native-editor.png')], env=env, check=True, timeout=15)
        receipt['passed'] = True
    finally:
        if viewer and viewer.poll() is None:
            viewer.terminate()
            viewer.wait(timeout=10)
        if monitor:
            monitor.stdin.close()
            try:
                monitor.wait(timeout=5)
            except subprocess.TimeoutExpired:
                monitor.terminate(); monitor.wait(timeout=5)
        desktop.terminate()
        try:
            desktop.wait(timeout=10)
        except subprocess.TimeoutExpired:
            desktop.kill(); desktop.wait()
        receipt['desktopTeardownReturncode'] = desktop.returncode
        (proof / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        for log in logs:
            log.close()
        desktoplog.close()
        print(json.dumps({'proof': str(proof), **receipt}), flush=True)


if __name__ == '__main__':
    main()
