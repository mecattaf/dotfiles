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
import shutil
import struct
import subprocess
import sys
import time
import uuid
import zlib


ROOT = Path(__file__).resolve().parents[2]
KITTY = os.environ.get('KITTY_EDITOR_KITTY', '/nix/store/jvhn8sy84klkfkd4az26m5nkjbma7ni3-kitty-0.48.0/bin/kitty')
KITTEN = str(Path(KITTY).with_name('kitten'))
DOMICILE = os.environ.get('KITTY_EDITOR_DOMICILE', '/nix/store/qvjsa1g98hhwllzhyhflafi9cmh74n4k-domicile/bin/domicile')
HELPER = ROOT / 'home/dot_config/kitty/agency_editor.py'


def main():
    assert b'--tmpfs\0/run/user\0' in Path('/proc/1/cmdline').read_bytes(), 'use runtime-test'
    full_config = os.environ.get('KITTY_EDITOR_FULL_CONFIG') == '1'
    if full_config and os.environ.get('KITTY_EDITOR_HOME_MASKED') != str(ROOT):
        masked = ROOT / ('full-config-home-' + time.strftime('%Y%m%d-%H%M%S'))
        masked.mkdir(mode=0o700)
        env = dict(os.environ, KITTY_EDITOR_HOME_MASKED=str(ROOT))
        # Keep passwd home/HOME unchanged, expose only this non-secret staged
        # checkout there, and block external network/provider/credential access.
        command = ['bwrap', '--bind', '/', '/', '--dev-bind', '/dev', '/dev', '--unshare-net',
                   '--bind', str(masked), str(Path.home()), '--bind', str(ROOT), str(ROOT),
                   '--', sys.executable, str(Path(__file__).resolve())]
        os.execvpe(command[0], command, env)
    proof = ROOT / ('native-proof-' + time.strftime('%Y%m%d-%H%M%S'))
    proof.mkdir()
    private = proof / 'private'
    private.mkdir()
    for name in ('config', 'cache', 'data', 'state', 'bin'):
        (private / name).mkdir()
    project = proof / 'project'
    project.mkdir()
    original = project / 'notes.md'
    original_contents = 'Original saved content\n'
    if full_config:
        original_contents += '\n# Native editor\n\n- [x] Full native colors\n- [ ] Unsaved work\n\n```yaml\ntransport: kitty\neditor: neovim\n```\n\n![Native image](image.png)\n'
        def png_chunk(kind, data):
            return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
        (project / 'image.png').write_bytes(b'\x89PNG\r\n\x1a\n' +
            png_chunk(b'IHDR', struct.pack('>IIBBBBB', 64, 32, 8, 2, 0, 0, 0)) +
            png_chunk(b'IDAT', zlib.compress((b'\0' + b'\x30\x80\xd0' * 64) * 32)) + png_chunk(b'IEND', b''))
    original.write_text(original_contents)
    nvimtree = Path(os.environ['KITTY_EDITOR_NVIM_TREE']).resolve()
    nvimconf = private / 'config/nvim'
    nvimconf.mkdir()
    if full_config:
        assert not (Path.home() / '.ssh').exists() and not (Path.home() / '.codex').exists()
        shutil.copytree(ROOT / 'home/dot_config/nvim', nvimconf, dirs_exist_ok=True)
        localbin = Path.home() / '.local/bin'; localbin.mkdir(parents=True)
        (localbin / 'nvim-lua').symlink_to(ROOT / 'home/dot_local/bin/nvim-lua')
        generated = Path(os.environ['KITTY_EDITOR_PLUGIN_TABLE']).read_text()
        table = re.search(r'local plugins = \{\n(.*?)\n\}', generated, re.S)
        helper = re.search(r'local lazy_nix_helper_path = "([^"]+)"', generated)
        assert table and helper
        for path in re.findall(r'"(/nix/store/[^"\n]+)"', table.group(1)) + [helper.group(1)]:
            assert Path(path).is_dir(), 'full plugin closure must exist; no runtime fetch: ' + path
        template = (ROOT / 'home/nvim/plugins.lua.in').read_text()
        plugins = template.replace('@pluginTable@', table.group(1)).replace('@lazyNixHelperPath@', helper.group(1))
        (nvimconf / 'lua/plugins.lua').write_text(plugins)
        mappings = (ROOT / 'home/nvim/mappings.lua.in').read_text()
        generated_mappings = Path(os.environ['KITTY_EDITOR_MAPPINGS_TABLE']).read_text()
        lazygit = re.search(r'(/nix/store/[^\s"\']+/bin/lazygit)', generated_mappings)
        assert lazygit and Path(lazygit.group(1)).is_file()
        mappings = mappings.replace('@lazygit@', lazygit.group(1)).replace('@nvim@', str(Path(shutil.which('nvim')).resolve()))
        (nvimconf / 'lua/mappings.lua').write_text(mappings)
    else:
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
        " tail=sys.argv[2:];tail=tail[:-1] if sys.argv[1]=='editor-tree-attach' and tail[-1:]==['--'] else tail\n"
        " command=[" + repr(str(ROOT / 'home/dot_local/bin')) + "+('/dsh-editor-tree' if sys.argv[1]=='editor-tree-attach' else '/dsh-editor'),*tail]\n"
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
    image_probe = proof / 'image_probe.py'
    image_probe.write_text('def main(args):pass\ndef handle_result(args,answer,target_window_id,boss):\n'
                            ' w=boss.window_id_map[target_window_id]\n'
                            ' w.set_user_var("agency_proof_image_count",str(w.screen.grman.image_count))\n'
                            'handle_result.no_ui=True\n')
    env = {key: value for key, value in os.environ.items()
           if not any(marker in key.upper() for marker in ('TOKEN', 'PASSWORD', 'SECRET', 'API_KEY', 'AUTH'))}
    env.update(XDG_CONFIG_HOME=str(private / 'config'),
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
               'kitty': KITTY, 'nvimTree': str(nvimtree), 'sourceDirectory': str(project),
               'fullUserConfig': full_config, 'externalNetworkBlocked': full_config,
               'realHomeMasked': full_config}
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
                                   *(['--override', 'watcher=' + os.environ['KITTY_EDITOR_AGENCY_WATCHER']] if full_config else []),
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

        def has_image(window_id):
            remote('kitten', '--match', f'id:{window_id}', str(image_probe))
            return int(next(w for w in windows() if w['id'] == window_id)['user_vars'].get('agency_proof_image_count', '0')) > 0

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
        if full_config:
            records = json.loads(subprocess.check_output([str(ROOT / 'home/dot_local/bin/dsh-editor'), '--list', '--json'], env=env, text=True))
            address = records[0]['socket']
            lua = "(function() local b=vim.fn.bufnr(" + json.dumps(str(original)) + "); local p=vim.treesitter.get_parser(b,'markdown'); local clients={}; for _,c in ipairs(vim.lsp.get_clients({bufnr=b})) do clients[#clients+1]=c.name end; return vim.json.encode({colors=vim.g.colors_name,palette=require('theme').palette().name,plugins=vim.tbl_count(require('lazy.core.config').plugins),treesitter=p:parse()[1]:root():type(),lsp=clients,errmsg=vim.v.errmsg,heading=vim.api.nvim_get_hl(0,{name='RenderMarkdownH1',link=false}),image=require('kitty_image_remote').status()}) end)()"
            expression = 'luaeval(' + json.dumps(lua) + ')'
            def inspect_features():
                result = subprocess.run(['nvim', '--headless', '-u', 'NONE', '--server', address, '--remote-expr', expression],
                                        env=env, capture_output=True, text=True, check=True, timeout=5)
                value = json.loads(result.stdout)
                (proof / 'full-config-features.json').write_text(json.dumps(value, indent=2))
                return value
            features = wait(lambda: result if 'marksman' in (result := inspect_features())['lsp'] else None,
                            'full config Markdown LSP and tree-sitter')
            assert features['plugins'] >= 30 and features['colors'].startswith('catppuccin')
            assert features['treesitter'] == 'document' and features['heading'].get('fg')
            assert features['errmsg'] in ('', 'E31: No such mapping'), features
            features = wait(lambda: result if (result := inspect_features())['image'].get('cell_width') and
                            result['image'].get('bytes_sent', 0) > 0 else None, 'actual Kitty image geometry and bytes')
            log = private / 'state/dsh/editor' / Path(address).stem / 'server.log'
            assert not re.search(r'Failed to run|Error executing|E5113|failed to open stdout', log.read_text()), log.read_text()
            wait(lambda: has_image(editorid), 'real Kitty graphics manager received the rendered PNG')
            receipt['fullConfigFeatures'] = features
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
        if full_config:
            refreshed = wait(lambda: result if (result := inspect_features())['image'].get('retransmissions', 0) >
                             features['image'].get('retransmissions', 0) else None, 'image cache invalidated after fresh native UI')
            wait(lambda: has_image(editor['id']), 'fresh Kitty window received the retained buffer image again')
            receipt['imageAfterFreshUi'] = refreshed['image']
        assert original.read_text() == original_contents
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
