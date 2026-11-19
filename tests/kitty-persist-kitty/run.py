#!/usr/bin/env python3
"""The client's Kitty configuration with kitty-persist's lines, in a real Kitty (O1, O6).

It takes a built Home Manager `home-files` tree (the client's), lays it out as a private home,
and runs a real Kitty 0.50 in a private headless sway. Never on a desktop in use: it refuses to
run unless it has its own runtime directory and no session bus (run it under the runtime
wrapper).

Rows:

- static: the include chain kitty.conf -> agency include -> kitty-persist lines -> the personal
  lines, read the way Kitty reads it: every map of the product's keys and of the personal
  same-directory key is conditional, none replaces an unconditional map of the owner's, the
  persist lines come after the agency include (Kitty: the last applicable map wins), and the
  options the product's routes need (clipboard_control, listen_on with the Kitty pid,
  allow_remote_control, scrollback_lines, the program-status tab title).
- load: what Kitty logs with the configuration as generated, against the same configuration
  with the kitty-persist parts removed; the same with the module off (the include line present,
  its file absent); a control with two bad lines proves the comparison sees what Kitty reports.
- keys: with a virtual keyboard, the product's keys and the personal same-directory key in an
  ordinary window reach the program and start nothing; in the persistent window the history,
  prompt-editor and same-directory keys start `kitty-persist history|compose|new ...` with the
  pressed window's id (the program on Kitty's PATH is a stub that records its words), and ctrl+v
  sends the product's paste marker.
- dictation call (O6): no dictation tool exists; a stand-in for it runs the call a dictation
  tool makes, `PROGRAM paste-text --focused --to unix:@kitty-<pid>`, from outside Kitty with no
  KITTY_ variable, against a window that carries the attached client's user variables: the
  exact text arrives unsent, no --to gives 78, an ordinary focused window gives 11.

usage: run.py --kitty KITTY --home-files HOME_FILES --paste-text PROGRAM [--out FILE.json]
PROGRAM is `kitty-persist` once the program has the paste-text command, or the product's
stand-in program built from the same library code.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
WINDOW = os.path.join(HERE, 'window.py')
PERSIST_KEYS = ['ctrl+v', 'kitty_mod+alt+h', 'kitty_mod+i', 'kitty_mod+alt+n']
ROWS: list[dict] = []


def record(area: str, what: str, expected: str, got, ok: bool) -> None:
    ROWS.append({'area': area, 'what': what, 'expected': expected, 'got': got, 'result': 'pass' if ok else 'FAIL'})
    print(f"[{'pass' if ok else 'FAIL'}] {area}: {what}: {json.dumps(got, ensure_ascii=False)[:300]}", flush=True)


def norm_key(k: str) -> str:
    parts = k.lower().replace('kitty_mod', 'ctrl+shift').split('+')
    mods, key = parts[:-1], parts[-1]
    return '+'.join(sorted(set(mods)) + [key])


# ---- the configuration as Kitty reads it ----

def read_chain(path: str, home: str, out: list, seen: set) -> None:
    """Every line of path and of the files it includes, in Kitty's order: (file, number, line)."""
    real = os.path.realpath(path)
    if real in seen or not os.path.exists(path):
        return
    seen.add(real)
    base = os.path.dirname(path)
    for n, raw in enumerate(open(path, errors='replace').read().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        word, _, rest = line.partition(' ')
        if word == 'include':
            inc = rest.strip().replace('${HOME}', home).replace('$HOME', home)
            if not os.path.isabs(inc):
                inc = os.path.join(base, inc)
            out.append((path, n, line))
            read_chain(inc, home, out, seen)
        else:
            out.append((path, n, line))


def parse_map(line: str) -> tuple[bool, str, str]:
    """(conditional, normalised key, action) of a `map` line."""
    words = line.split()[1:]
    cond = False
    i = 0
    while i < len(words) and words[i].startswith('--'):
        w = words[i]
        if w.startswith('--when-focus-on'):
            cond = True
            if '=' not in w:
                # the condition is the next word, possibly quoted over several words
                i += 1
                if words[i].startswith('"'):
                    while not words[i].endswith('"'):
                        i += 1
        elif '=' not in w:
            i += 1
        i += 1
    key = words[i] if i < len(words) else ''
    return cond, norm_key(key), ' '.join(words[i + 1:])


def static_rows(home: str) -> None:
    conf = os.path.join(home, '.config/kitty/kitty.conf')
    chain: list = []
    read_chain(conf, home, chain, set())
    short = lambda p: os.path.relpath(p, home) if p.startswith(home) else os.path.basename(p)
    incs = [(short(f), n, l) for f, n, l in chain if l.startswith('include ')]
    agency = next((i for i, (f, n, l) in enumerate(chain) if l.startswith('include') and 'agency-kitty' in l), None)
    persist = next((i for i, (f, n, l) in enumerate(chain) if l.startswith('include') and 'kitty-persist/kitty.conf' in l), None)
    lines_file = os.path.join(home, '.config/kitty-persist/kitty.conf')
    record('static', 'the product lines file is present and is the package text',
           'a link into the kitty-persist package, mappings and comments only',
           {'target': os.path.realpath(lines_file) if os.path.exists(lines_file) else None},
           os.path.exists(lines_file) and '-kitty-persist-' in os.path.realpath(lines_file)
           and all((not l.strip()) or l.startswith('#') or l.startswith('map ') for l in open(lines_file).read().splitlines()))
    record('static', 'include order', 'kitty-persist lines included after the agency include',
           {'includes': incs}, agency is not None and persist is not None and persist > agency)
    maps = [(short(f), n, l) for f, n, l in chain if l.startswith('map ')]
    for key in PERSIST_KEYS:
        nk = norm_key(key)
        # (file, line number, conditional, action, limited to persistent windows)
        hits = [(f, n, parse_map(l)[0], parse_map(l)[2], 'var:^persist_id$' in l) for f, n, l in maps if parse_map(l)[1] == nk]
        uncond = [h for h in hits if not h[2]]
        persist_hits = [h for h in hits if h[2] and h[4]]
        last_persist = bool(hits) and hits[-1][2] and hits[-1][4]
        record('static', f'key {key}', 'no unconditional map of it; the persist map is conditional and last',
               {'maps': [(f, n, c, act[:70]) for f, n, c, act, _ in hits]}, not uncond and len(persist_hits) >= 1 and last_persist)
    opts: dict[str, str] = {}
    for f, n, l in chain:
        w, _, rest = l.partition(' ')
        if w not in ('map', 'mouse_map', 'include', 'env', 'watcher'):
            opts[w] = rest.strip()
    cc = opts.get('clipboard_control', '')
    record('static', 'clipboard_control', 'read-clipboard or read-clipboard-ask (the image paste route)',
           cc, 'read-clipboard-ask' in cc.split() or 'read-clipboard' in cc.split())
    record('static', 'listen_on', 'one socket per Kitty instance, named by its pid (the dictation call\'s --to)',
           opts.get('listen_on'), '{kitty_pid}' in opts.get('listen_on', ''))
    record('static', 'allow_remote_control', 'socket-only or yes (paste-text reaches Kitty through the socket)',
           opts.get('allow_remote_control'), opts.get('allow_remote_control') in ('socket-only', 'yes'))
    record('static', 'scrollback_lines', 'equal to what the holder keeps (100000)',
           opts.get('scrollback_lines'), opts.get('scrollback_lines') == '100000'
           and '# scrollback_lines 100000' in open(lines_file).read())
    record('static', 'tab_title_template', 'program status in front of Kitty\'s default template',
           opts.get('tab_title_template'), (opts.get('tab_title_template') or '').startswith('"{tab.program_status}'))


# ---- a real Kitty ----

class Sway:
    def __init__(self, root: str):
        self.root = root
        cfg = os.path.join(root, 'sway.conf')
        with open(cfg, 'w') as f:
            f.write('output HEADLESS-1 resolution 1280x800\nxwayland disable\n')
        env = dict(os.environ, WLR_BACKENDS='headless', WLR_LIBINPUT_NO_DEVICES='1', WLR_RENDERER='pixman')
        self.log = open(os.path.join(root, 'sway.log'), 'w')
        self.p = subprocess.Popen(['sway', '-c', cfg], env=env, stdout=self.log, stderr=subprocess.STDOUT)
        rt = os.environ['XDG_RUNTIME_DIR']
        for _ in range(200):
            names = os.listdir(rt)
            way = [n for n in names if re.fullmatch(r'wayland-\d+', n)]
            ipc = [n for n in names if n.startswith('sway-ipc.') and n.endswith('.sock')]
            if way and ipc:
                self.wayland, self.swaysock = way[0], os.path.join(rt, ipc[0])
                break
            time.sleep(0.1)
        else:
            raise SystemExit('sway did not start; see ' + os.path.join(root, 'sway.log'))
        # The headless seat has no keyboard. Each wtype run adds a virtual keyboard and removes it
        # on exit, and Kitty then reads every window as unfocused; one long-lived virtual keyboard
        # keeps the seat's keyboard (the product battery's driver does the same).
        self.env = dict(os.environ, WAYLAND_DISPLAY=self.wayland, SWAYSOCK=self.swaysock)
        self.hold = subprocess.Popen(['wtype', '-k', 'Shift_L', '-s', '3600000'], env=self.env,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.5)

    def press(self, *keys: str) -> None:
        *mods, key = keys
        args = ['-k', 'Shift_L', '-s', '150']   # the first event after the keymap upload can be lost
        for m in mods:
            args += ['-M', m]
        args += ['-k', key]
        for m in reversed(mods):
            args += ['-m', m]
        subprocess.run(['wtype', *args], env=self.env, capture_output=True, timeout=10)
        time.sleep(0.6)

    def stop(self) -> None:
        if self.hold.poll() is None:
            self.hold.terminate()
            self.hold.wait(timeout=5)
        # Ask over its own socket first; a signalled headless sway has dumped core before.
        subprocess.run(['swaymsg', '-s', self.swaysock, 'exit'], capture_output=True, timeout=20)
        try:
            self.p.wait(timeout=15)
        except subprocess.TimeoutExpired:
            self.p.terminate()
            self.p.wait(timeout=10)


def make_home(root: str, hf: str, variant: str, theme: str) -> str:
    home = os.path.join(root, variant, 'home')
    cfg = os.path.join(home, '.config')
    os.makedirs(cfg)
    for name in os.listdir(os.path.join(hf, '.config')):
        src = os.path.join(hf, '.config', name)
        if name == 'kitty':
            shutil.copytree(src, os.path.join(cfg, 'kitty'), symlinks=False)
            for dp, dns, fns in os.walk(os.path.join(cfg, 'kitty')):
                os.chmod(dp, 0o755)
                for fn in fns:
                    os.chmod(os.path.join(dp, fn), 0o644)
        elif name == 'kitty-persist' and variant in ('without', 'module-off'):
            continue
        else:
            os.symlink(src, os.path.join(cfg, name))
    # ~/.config/theme is the link the theme script keeps (missing means noir).
    if os.path.isdir(os.path.join(hf, '.config/themes', theme)):
        os.symlink(os.path.join(hf, '.config/themes', theme), os.path.join(cfg, 'theme'))
    conf = os.path.join(cfg, 'kitty/kitty.conf')
    text = open(conf).read()
    if variant == 'without':
        keep = []
        for line in text.splitlines():
            s = line.strip()
            if not s.startswith('#') and ('kitty-persist' in s or 'persist_id' in s or s.startswith('tab_title_template')):
                continue
            keep.append(line)
        text = '\n'.join(keep) + '\n'
    if variant == 'control':
        with open(os.path.join(cfg, 'kitty/bad-kp-control.conf'), 'w') as f:
            # Two kinds of line Kitty reports. (Kitty does not check a map's action name at load.)
            f.write('no_such_option_kp_control yes\ninclude no-such-file-kp-control.conf\n')
        text += 'include bad-kp-control.conf\n'
    with open(conf, 'w') as f:
        f.write(text)
    for d in ('cache', 'state', 'data'):
        os.makedirs(os.path.join(root, variant, d))
    return home


def clean_env(extra: dict) -> dict:
    env = {k: v for k, v in os.environ.items() if not k.startswith('KITTY_') and k not in ('TERM', 'TERMINFO')}
    env.update(extra)
    return env


def wait_for(fn, timeout: float):
    end = time.time() + timeout
    while time.time() < end:
        r = fn()
        if r:
            return r
        time.sleep(0.1)
    return None


def got_text(d: str, name: str) -> str:
    try:
        return b''.join(bytes.fromhex(json.loads(x)['hex']) for x in open(os.path.join(d, f'{name}.in.jsonl'))).decode('utf-8', 'replace')
    except OSError:
        return ''


def log_lines(path: str) -> list[str]:
    try:
        lines = open(path, errors='replace').read().splitlines()
    except OSError:
        return ['(no kitty.log)']
    # Kitty's time stamps ("[0.042] ") and store hashes vary between runs.
    out = []
    for x in lines:
        if x.startswith('[') and '] ' in x:
            x = x.split('] ', 1)[1]
        out.append(re.sub(r'/nix/store/[a-z0-9]{32}-', '/nix/store/H-', x))
    return out


def stub_dir(root: str) -> str:
    """A `kitty-persist` that only records its words: what Kitty's mappings start."""
    d = os.path.join(root, 'stub')
    if not os.path.isdir(d):
        os.makedirs(d)
        p = os.path.join(d, 'kitty-persist')
        with open(p, 'w') as f:
            f.write('#!/bin/sh\nprintf \'%s\\n\' "$*" >> "$KP_STUB_LOG"\n')
        os.chmod(p, 0o755)
    return d


def stub_calls(root: str) -> list[str]:
    try:
        return open(os.path.join(root, 'stub.log')).read().splitlines()
    except OSError:
        return []


def run_kitty(root: str, sway: Sway, kitty: str, variant: str, home: str, persist: str | None, during=None) -> dict:
    d = os.path.join(root, variant)
    env = clean_env({
        'PATH': stub_dir(root) + os.pathsep + os.environ.get('PATH', ''), 'KP_STUB_LOG': os.path.join(root, 'stub.log'),
        'HOME': home, 'XDG_CONFIG_HOME': os.path.join(home, '.config'), 'XDG_CACHE_HOME': os.path.join(d, 'cache'),
        'XDG_STATE_HOME': os.path.join(d, 'state'), 'XDG_DATA_HOME': os.path.join(d, 'data'),
        'WAYLAND_DISPLAY': sway.wayland, 'SWAYSOCK': sway.swaysock,
    })
    argv = [kitty, '--config', os.path.join(home, '.config/kitty/kitty.conf'), '-o', 'linux_display_server=wayland',
            '--class', f'kp-test-{variant}', sys.executable, WINDOW, '--dir', d, '--name', 'P']
    if persist:
        argv += ['--persist', persist, '--status', 'working']
    logf = open(os.path.join(d, 'kitty.log'), 'w')
    k = subprocess.Popen(argv, env=env, stdout=logf, stderr=subprocess.STDOUT)
    res = {'variant': variant, 'pid': k.pid}
    ready = wait_for(lambda: os.path.exists(os.path.join(d, 'P.ready.json')), 40)
    res['ready'] = bool(ready)
    addr = f'unix:@kitty-{k.pid}'
    res['socket'] = bool(wait_for(lambda: f'@kitty-{k.pid}\n' in open('/proc/net/unix').read(), 10))
    if ready and during:
        try:
            during(d, addr, env)
        except Exception as e:  # a failed step is a failed row, never a hang
            record('o6', 'dictation call steps', 'no exception', repr(e), False)
    time.sleep(1.0)
    open(os.path.join(d, 'stop'), 'w').close()
    try:
        k.wait(timeout=20)
    except subprocess.TimeoutExpired:
        subprocess.run([kitty, '@', '--to', addr, 'close-window', '--match', 'all'], env=env, capture_output=True, timeout=10)
        try:
            k.wait(timeout=10)
        except subprocess.TimeoutExpired:
            k.terminate()
            k.wait(timeout=10)
    res['exit'] = k.returncode
    res['log'] = log_lines(os.path.join(d, 'kitty.log'))
    return res


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--kitty', required=True)
    ap.add_argument('--home-files', required=True)
    ap.add_argument('--paste-text', required=True, help='program whose `paste-text` command is the dictation call')
    ap.add_argument('--theme', default='noir')
    ap.add_argument('--out')
    ap.add_argument('--keep', action='store_true')
    a = ap.parse_args()
    if not os.environ.get('XDG_RUNTIME_DIR', '').startswith('/run/user/') or os.environ.get('DBUS_SESSION_BUS_ADDRESS'):
        print('run.py: needs a private runtime directory and no session bus (run it under the runtime wrapper)', file=sys.stderr)
        return 64
    version = subprocess.run([a.kitty, '--version'], capture_output=True, text=True).stdout.strip()
    root = tempfile.mkdtemp(prefix='kitty-persist-kitty.')
    print(f'{version}; raw logs in {root}', flush=True)
    homes = {v: make_home(root, a.home_files, v, a.theme) for v in ('without', 'module-off', 'full', 'control')}
    static_rows(homes['full'])
    sway = Sway(root)
    try:
        sid = str(uuid.uuid4())
        base = run_kitty(root, sway, a.kitty, 'without', homes['without'], None)
        off = run_kitty(root, sway, a.kitty, 'module-off', homes['module-off'], None)

        def o6(d: str, addr: str, kenv: dict) -> None:
            def persist_windows() -> list:
                ls = json.loads(subprocess.run([a.kitty, '@', '--to', addr, 'ls'], env=kenv, capture_output=True,
                                               timeout=20).stdout or '[]')
                wins = [w for ow in ls for t in ow['tabs'] for w in t['windows']]
                return [w for w in wins if w.get('user_vars', {}).get('persist_state') == 'attached'
                        and w.get('user_vars', {}).get('persist_id') == sid]
            # Kitty applies the window's escape codes on its own schedule: wait until it shows them.
            p = wait_for(persist_windows, 10) or []
            record('o6', 'the persistent window as Kitty sees it', 'user variables persist_id/epoch/state set, focused',
                   [{k: w.get(k) for k in ('id', 'is_focused')} | {'vars': sorted(w.get('user_vars', {}))} for w in p],
                   len(p) == 1 and p[0].get('is_focused') and p[0]['user_vars'].get('persist_state') == 'attached')
            env = clean_env({})
            text = 'dictated: héllo wörld — two words'
            cp = subprocess.run([a.paste_text, 'paste-text', '--focused', '--to', addr], input=text.encode(), env=env,
                                capture_output=True, timeout=30)
            got = wait_for(lambda: got_text(d, 'P') if got_text(d, 'P') == text else None, 5) or got_text(d, 'P')
            record('o6', 'stand-in dictation | paste-text --focused --to unix:@kitty-<pid>',
                   'exit 0; exactly the text in the focused persistent window; no Enter',
                   {'exit': cp.returncode, 'stderr': cp.stderr.decode(errors='replace').strip(), 'typed': got},
                   cp.returncode == 0 and got == text and '\r' not in got)
            before = got_text(d, 'P')
            cp = subprocess.run([a.paste_text, 'paste-text', '--focused'], input=b'x', env=env, capture_output=True, timeout=30)
            err = cp.stderr.decode(errors='replace').strip()
            time.sleep(0.5)
            record('o6', 'the same call without --to (no KITTY_LISTEN_ON outside Kitty)', 'exit 78; one line naming listen_on; nothing typed',
                   {'exit': cp.returncode, 'stderr': err}, cp.returncode == 78 and 'listen_on' in err and got_text(d, 'P') == before)
            subprocess.run([a.kitty, '@', '--to', addr, 'launch', '--type=window', sys.executable, WINDOW, '--dir', d, '--name', 'O'],
                           env=kenv, capture_output=True, timeout=20)
            wait_for(lambda: os.path.exists(os.path.join(d, 'O.ready.json')), 20)
            cp = subprocess.run([a.paste_text, 'paste-text', '--focused', '--to', addr], input=b'not here', env=env,
                                capture_output=True, timeout=30)
            time.sleep(0.5)
            record('o6', 'an ordinary window has focus', 'exit 11; nothing typed anywhere',
                   {'exit': cp.returncode, 'stderr': cp.stderr.decode(errors='replace').strip(), 'O': got_text(d, 'O')},
                   cp.returncode == 11 and got_text(d, 'P') == before and got_text(d, 'O') == '')
            # The keys, pressed with a virtual keyboard: first in the ordinary window O (focused now),
            # then in the persistent window P. The program the mappings start is a stub that records
            # its words.
            wins = {w['id']: w for ow in json.loads(subprocess.run([a.kitty, '@', '--to', addr, 'ls'], env=kenv, capture_output=True,
                    timeout=20).stdout or '[]') for t in ow['tabs'] for w in t['windows']}
            pid_ = next(i for i, w in wins.items() if w.get('user_vars', {}).get('persist_id') == sid)
            keys = {'ctrl+v': ('ctrl', 'v'), 'kitty_mod+alt+h': ('ctrl', 'shift', 'alt', 'h'),
                    'kitty_mod+i': ('ctrl', 'shift', 'i'), 'kitty_mod+alt+n': ('ctrl', 'shift', 'alt', 'n')}
            for name, k in keys.items():
                n0, o0 = len(stub_calls(root)), got_text(d, 'O')
                sway.press(*k)
                record('keys', f'{name} in an ordinary window', 'reaches the program as a key; nothing started',
                       {'started': stub_calls(root)[n0:], 'bytes': (got_text(d, 'O')[len(o0):]).encode().hex()},
                       stub_calls(root)[n0:] == [] and got_text(d, 'O') != o0)
            subprocess.run([a.kitty, '@', '--to', addr, 'focus-window', '--match', f'id:{pid_}'], env=kenv, capture_output=True, timeout=20)
            time.sleep(0.5)
            want = {'kitty_mod+alt+h': f'history {pid_}', 'kitty_mod+i': f'compose {pid_}',
                    'kitty_mod+alt+n': f'new --attach --cwd-of-window {pid_} --window-type window'}
            for name, line in want.items():
                n0 = len(stub_calls(root))
                sway.press(*keys[name])
                got = wait_for(lambda: stub_calls(root)[n0:], 5) or []
                record('keys', f'{name} in the persistent window', f'Kitty starts `kitty-persist {line}`', got, got == [line])
                time.sleep(0.5)
                subprocess.run([a.kitty, '@', '--to', addr, 'focus-window', '--match', f'id:{pid_}'], env=kenv,
                               capture_output=True, timeout=20)
                time.sleep(0.3)
            p0 = got_text(d, 'P')
            sway.press(*keys['ctrl+v'])
            time.sleep(0.5)
            new_p = got_text(d, 'P')[len(p0):]
            record('keys', 'ctrl+v in the persistent window', "the product's marker reaches the window (then Kitty's paste)",
                   new_p.encode().hex(), new_p.startswith('\x1b_kp-paste-key\x1b\\'))
            # A second tab, so the tab bar draws both titles through the program-status template (the
            # persistent window reported `working`); a template Kitty cannot render is logged.
            subprocess.run([a.kitty, '@', '--to', addr, 'launch', '--type=tab', sys.executable, WINDOW, '--dir', d, '--name', 'T'],
                           env=kenv, capture_output=True, timeout=20)
            wait_for(lambda: os.path.exists(os.path.join(d, 'T.ready.json')), 20)
            time.sleep(1.0)
            ls = json.loads(subprocess.run([a.kitty, '@', '--to', addr, 'ls'], env=kenv, capture_output=True, timeout=20).stdout or '[]')
            record('o1', 'two tabs drawn with the program-status tab title', 'two tabs; nothing logged (load rows)',
                   {'tabs': [t.get('title') for ow in ls for t in ow['tabs']]}, sum(len(ow['tabs']) for ow in ls) == 2)

        full = run_kitty(root, sway, a.kitty, 'full', homes['full'], sid, during=o6)
        ctl = run_kitty(root, sway, a.kitty, 'control', homes['control'], None)
    finally:
        sway.stop()
    for r in (base, off, full, ctl):
        record('load', f"Kitty starts ({r['variant']})", 'window ready, remote-control socket bound, exit 0',
               {'ready': r['ready'], 'socket': r['socket'], 'exit': r['exit']}, r['ready'] and r['socket'] and r['exit'] == 0)
    noise = set(base['log'])
    record('load', 'baseline log (kitty-persist parts removed)', 'recorded as is', base['log'], True)
    # The full variant opens more windows than the baseline (keys, dictation, a second tab), and
    # their children end when the test stops them. Kitty may then log that it could not resize a
    # window whose child is already gone. That is a window's life, not configuration: it is kept
    # in its own row and not counted as a warning.
    gone = re.compile(r'^Failed to send resize signal to child with id: \d+ \(children count: 0\)')
    extra = [x for x in full['log'] if x not in noise and not gone.match(x)]
    record('load', 'the generated configuration loads without warning', "nothing in Kitty's log beyond the baseline's",
           extra or 'none', not extra)
    record('load', "full: lines about a test window whose child had ended (not counted)", 'recorded as is',
           [x for x in full['log'] if x not in noise and gone.match(x)] or 'none', True)
    extra_off = [x for x in off['log'] if x not in noise]
    record('load', 'module off: the include line with its file absent (no such seat today: only the client is one)',
           "only Kitty's own line for a missing include, which it then skips", extra_off or 'none',
           len(extra_off) == 1 and extra_off[0].startswith('Could not find included config file: ')
           and extra_off[0].endswith('/.config/kitty-persist/kitty.conf, ignoring'))
    extra_ctl = [x for x in ctl['log'] if x not in noise]
    record('load', 'control: two bad lines are seen', 'both reported in the log',
           extra_ctl, any('no_such_option_kp_control' in x for x in extra_ctl) and any('no-such-file-kp-control' in x for x in extra_ctl))
    fails = [r for r in ROWS if r['result'] != 'pass']
    summary = {'kitty': version, 'rows': ROWS, 'pass': len(ROWS) - len(fails), 'fail': len(fails)}
    if a.out:
        with open(a.out, 'w') as f:
            json.dump(summary, f, indent=1, ensure_ascii=False)
    print(f"{summary['pass']} pass, {summary['fail']} fail", flush=True)
    if not a.keep and not fails:
        shutil.rmtree(root, ignore_errors=True)
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
