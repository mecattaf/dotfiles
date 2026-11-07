#!/usr/bin/env python3
"""Private PTY input-to-UTF8 redraw microbenchmark, not key-to-photon latency.

Run only through runtime-test on compute. Identical minimal config isolates
native Neovim UI/RPC and checkpoint callback costs from plugins and networking.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pty
import random
import select
import shutil
import signal
import statistics
import struct
import subprocess
import termios
import time


ROOT = Path(__file__).resolve().parents[2]
EDITOR = ROOT / 'home/dot_local/bin/dsh-editor'


def quantile(values, fraction):
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    low = int(position)
    high = min(low + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (position - low)


def main():
    assert b'--tmpfs\0/run/user\0' in Path('/proc/1/cmdline').read_bytes(), 'use runtime-test'
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=5)
    parser.add_argument('--samples', type=int, default=80)
    args = parser.parse_args()
    assert 1 <= args.rounds <= 20 and 10 <= args.samples <= 150
    output = args.output.resolve()
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    nvim = shutil.which('nvim')
    assert nvim
    init = output / 'init.lua'
    init.write_text("vim.o.swapfile=false;vim.o.shadafile='NONE';vim.o.showmode=false;vim.o.showcmd=false\n"
                    "vim.o.ruler=false;vim.o.laststatus=0;vim.o.number=false;vim.o.relativenumber=false\n"
                    "vim.o.mouse='';vim.o.termguicolors=true;vim.o.signcolumn='no'\n")
    variants = ('direct-nvim', 'native-remote-ui', 'dsh-editor')
    aggregate = {variant: [] for variant in variants}
    runs = []
    rng = random.Random(624621)

    def rpc(address, expression, env):
        result = subprocess.run([nvim, '--headless', '-u', 'NONE', '--server', str(address),
                                 '--remote-expr', expression], env=env, capture_output=True,
                                text=True, timeout=3, check=True)
        return result.stdout.strip()

    for round_number in range(args.rounds):
        order = list(variants)
        rng.shuffle(order)
        for variant in order:
            run = output / f'{round_number}-{variant}'
            run.mkdir()
            project = run / 'project'; project.mkdir()
            file = project / 'notes.txt'; file.write_text('start:')
            for directory in ('config', 'state', 'data', 'cache'):
                (run / directory).mkdir()
            env = dict(os.environ, TERM='xterm-kitty', XDG_CONFIG_HOME=str(run / 'config'),
                       XDG_STATE_HOME=str(run / 'state'), XDG_DATA_HOME=str(run / 'data'),
                       XDG_CACHE_HOME=str(run / 'cache'))
            address = Path(env['XDG_RUNTIME_DIR']) / f'nvim-latency-{round_number}-{variants.index(variant)}.sock'
            server = None
            server_pid = None
            log = (run / 'server.log').open('wb')
            if variant == 'native-remote-ui':
                server = subprocess.Popen([nvim, '--headless', '-u', str(init), '--listen', str(address), str(file)],
                                          env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                          start_new_session=True)
                server_pid = server.pid
                command = [nvim, '-u', 'NONE', '--server', str(address), '--remote-ui']
            elif variant == 'dsh-editor':
                result = subprocess.run([str(EDITOR), '--socket-only', '--directory', str(project), '--init', str(init),
                                         '--', str(file)], env=env, text=True, capture_output=True, timeout=20, check=True)
                address = Path(result.stdout.strip())
                server_pid = int(rpc(address, 'getpid()', env))
                command = [str(EDITOR), '--directory', str(project), '--init', str(init), '--', str(file)]
            else:
                command = [nvim, '-u', str(init), '--listen', str(address), str(file)]
            if variant != 'direct-nvim':
                deadline = time.monotonic() + 10
                while not address.exists():
                    if time.monotonic() >= deadline:
                        raise TimeoutError('native server socket')
                    time.sleep(0.01)
            master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 200, 0, 0))

            def controlling_tty():
                os.setsid()
                fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

            child = subprocess.Popen(command, env=env, cwd=project, stdin=slave, stdout=slave, stderr=slave,
                                     preexec_fn=controlling_tty, close_fds=True)
            os.close(slave)

            def drain(quiet=0.002):
                data = bytearray()
                while select.select([master], [], [], quiet)[0]:
                    try:
                        data.extend(os.read(master, 65536))
                    except OSError:
                        break
                return bytes(data)

            try:
                deadline = time.monotonic() + 15
                while True:
                    if child.poll() is not None:
                        raise RuntimeError(f'{variant} TUI exited: {child.returncode}; {drain()!r}')
                    try:
                        if rpc(address, 'len(nvim_list_uis())', env) == '1':
                            break
                    except (OSError, subprocess.SubprocessError):
                        pass
                    if time.monotonic() >= deadline:
                        raise TimeoutError(f'{variant} UI attach')
                    time.sleep(0.02)
                drain(0.02)
                # Append to the one private line. Multibyte glyphs cannot be
                # confused with ASCII bytes in terminal escape sequences.
                os.write(master, b'A')
                time.sleep(0.02); drain()
                values = []
                warmup = []
                expected = 'start:'
                # Retain ten cold samples separately. A PTY with no terminal
                # answering query negotiation can delay its first glyph.
                for index in range(args.samples + 10):
                    glyph = ('é', 'λ', 'ж')[index % 3]
                    encoded = glyph.encode()
                    drain()
                    started = time.monotonic_ns()
                    os.write(master, encoded)
                    rendered = bytearray()
                    deadline = time.monotonic() + 2
                    while encoded not in rendered:
                        if time.monotonic() >= deadline:
                            raise TimeoutError(f'{variant} missing UTF8 redraw: {rendered!r}')
                        if select.select([master], [], [], 0.05)[0]:
                            rendered.extend(os.read(master, 65536))
                    elapsed = (time.monotonic_ns() - started) / 1e6
                    (warmup if index < 10 else values).append(elapsed)
                    expected += glyph
                assert rpc(address, 'getline(1)', env) == expected
                assert file.read_text() == 'start:'
                aggregate[variant].extend(values)
                runs.append({'round': round_number, 'variant': variant, 'milliseconds': values,
                             'coldWarmupMilliseconds': warmup})
            finally:
                if child.poll() is None:
                    os.write(master, b'\x1b:qa!\r')
                    try:
                        child.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        child.terminate(); child.wait(timeout=5)
                os.close(master)
                if server_pid:
                    try:
                        os.kill(server_pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                if server:
                    server.wait(timeout=5)
                log.close()
    summary = {variant: {'samples': len(values), 'medianMs': statistics.median(values),
                         'p95Ms': quantile(values, 0.95), 'p99Ms': quantile(values, 0.99),
                         'minMs': min(values), 'maxMs': max(values)} for variant, values in aggregate.items()}
    receipt = {'measurement': 'PTY write complete UTF8 glyph to same glyph in Neovim TUI output',
               'excludes': ['SSH', 'network', 'Kitty', 'display', 'physical keyboard', 'full user plugin config'],
               'nvimVersion': subprocess.check_output([nvim, '--version'], text=True).splitlines()[0],
               'dshEditorSha256': hashlib.sha256(EDITOR.read_bytes()).hexdigest(),
               'summary': summary, 'runs': runs}
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
