"""Identity of the currently running desktop; no commands or desktop mutations.

Imagine's layout persistence runs this as its `identity` helper. The Domicile
socket discovery below is self-contained: it reads only the owned control
socket in the user runtime directory and asks it `which_shell`.
"""
import hashlib
import json
import os
from pathlib import Path
import socket
import stat
import struct

MAX_REPLY = 16384


class LaunchError(Exception):
    pass


def owned_socket(path):
    try:
        info=path.lstat()
        if info.st_uid!=os.getuid() or not stat.S_ISSOCK(info.st_mode):
            return None
        return (info.st_dev,info.st_ino)
    except OSError:
        return None


def request(path, message):
    identity=owned_socket(path)
    if identity is None:
        raise LaunchError('Domicile control socket is not owned by this user')
    try:
        with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as connection:
            connection.settimeout(3)
            connection.connect(str(path))
            if owned_socket(path)!=identity:
                raise LaunchError('Domicile socket changed during connection')
            connection.sendall(json.dumps(message,separators=(',',':')).encode()+b'\n')
            raw=bytearray()
            while b'\n' not in raw:
                part=connection.recv(min(4096,MAX_REPLY+1-len(raw)))
                if not part or len(raw)+len(part)>MAX_REPLY:
                    raise LaunchError('Domicile control response was incomplete or too large')
                raw.extend(part)
            if raw.count(b'\n')!=1 or raw.split(b'\n',1)[1]:
                raise LaunchError('Domicile control response framing is incompatible')
            reply=json.loads(raw)
            if not isinstance(reply,dict):
                raise LaunchError('Domicile control response has an incompatible shape')
            return reply
    except (OSError,ValueError):
        # Refusal/parse responses can echo a request; never display their body.
        raise LaunchError('Domicile control connection or protocol check failed') from None


def find_desktop(runtime):
    try:
        info=runtime.lstat()
    except OSError:
        raise LaunchError('No Domicile user runtime is available') from None
    if not stat.S_ISDIR(info.st_mode) or info.st_uid!=os.getuid() or info.st_mode&0o022:
        raise LaunchError('Domicile runtime ownership or permissions are invalid')
    live=[]
    for path in sorted(runtime.glob('domicile-ipc.*.sock')):
        if owned_socket(path) is None:
            continue
        try:
            reply=request(path,{'type':'which_shell'})
        except LaunchError:
            continue
        if reply.get('type')=='shell' and isinstance(reply.get('module'),str) and Path(reply['module']).is_absolute():
            live.append((path,reply['module']))
    if len(live)!=1:
        raise LaunchError('Layout identity needs exactly one live owned Domicile desktop')
    return live[0]


def identity(prepare_directory=True):
    directory = Path.home() / '.local/state/imagine'
    if prepare_directory:
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
        process = Path('/proc', child)
        try:
            if process.stat().st_uid != os.getuid():
                continue
            name = (process / 'comm').read_text().strip()
            # Official processes can deny /proc/exe even to this UID. These
            # are direct children of the peer-credential-verified launcher.
            # PID+birth identifies the incarnation; names select its two roles.
            # This is not executable provenance (that is attested separately).
            if name == '.chrome-unwrapp':
                engines.append(incarnation(child))
            elif name == '.domicile-compo':
                compositors.append(incarnation(child))
        except (FileNotFoundError, ProcessLookupError):
            continue
    if len(engines) != 1 or len(compositors) != 1:
        raise ValueError('Desktop process identity is unavailable')
    processes = [incarnation(pid), engines[0], compositors[0]]
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    key = hashlib.sha256((boot + ':' + ':'.join(processes)).encode()).hexdigest()
    return {'version': 1, 'key': key}


if __name__ == '__main__':
    print(json.dumps(identity()))
