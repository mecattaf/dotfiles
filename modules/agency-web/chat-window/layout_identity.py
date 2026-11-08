"""Identity of the currently running desktop; no commands or desktop mutations."""
import hashlib
import json
import os
from pathlib import Path
import socket
import struct
from legacy_bootstrap import find_desktop


def identity():
    directory = Path.home() / '.local/state/imagine'
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    if directory.is_symlink() or directory.stat().st_uid != os.getuid():
        raise ValueError('Untrusted layout directory')
    directory.chmod(0o700)
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR', '/run/user/' + str(os.getuid())))
    path, _ = find_desktop(runtime)
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as peer:
        peer.connect(str(path))
        pid, uid, _ = struct.unpack('3i', peer.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
    if uid != os.getuid():
        raise ValueError('Desktop ownership changed')
    def incarnation(process):
        return str(process) + ':' + Path('/proc', str(process), 'stat').read_text().split(') ', 1)[1].split()[19]
    # The launcher survives engine recovery. Include BOTH children so reused
    # browser/app IDs after an engine or compositor restart cannot match.
    engines, compositors = [], []
    for child in Path('/proc', str(pid), 'task', str(pid), 'children').read_text().split():
        executable = os.readlink(Path('/proc', child, 'exe'))
        if '-domicile-engine-' in executable and executable.endswith('/.chrome-unwrapped'):
            engines.append(incarnation(child))
        elif executable.endswith('/.domicile-compositor-wrapped'):
            compositors.append(incarnation(child))
    if len(engines) != 1 or len(compositors) != 1:
        raise ValueError('Desktop process identity is unavailable')
    processes = [incarnation(pid), engines[0], compositors[0]]
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    key = hashlib.sha256((boot + ':' + ':'.join(processes)).encode()).hexdigest()
    return {'version': 1, 'key': key}


if __name__ == '__main__':
    print(json.dumps(identity()))
