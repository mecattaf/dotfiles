"""Reopen Agency Web through NAS-owned services; no provider state lives here."""
import argparse
import json
import os
from pathlib import Path
import shlex
import socket
import stat
import subprocess
import sys
from urllib.parse import urlsplit

SYSTEM_CLI = Path('/run/current-system/sw/bin/domicile')
MAX_REPLY = 16384

# Static remote code only. The browser bootstrap returns over encrypted stdout,
# is captured in memory, and is never part of SSH/native-command arguments.
NAS_READER = r'''
import json,os,stat,subprocess
from pathlib import Path
from urllib.parse import urlsplit
peer=os.environ.get('SSH_CONNECTION','').split()
if len(peer)!=4 or peer[0]!='100.121.160.100' or peer[2]!='100.65.85.114':
    raise SystemExit('Agency Web requires its declared Tailscale route')
status=subprocess.run(['systemctl','--user','is-active','agency-web.service','agency-web-client-tunnel.service'],capture_output=True,text=True)
if status.returncode or status.stdout.split()!=['active','active']:
    raise SystemExit('Agency Web NAS services are not active')
path=Path('/home/tom/wednesday/domicile-first-pass-20261105/agency-web-backend/state/active.json')
fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW)
try:
    info=os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid!=os.getuid() or info.st_mode&0o077:
        raise SystemExit('Agency Web bootstrap file ownership is invalid')
    raw=os.read(fd,16385)
finally:os.close(fd)
if len(raw)>16384:raise SystemExit('Agency Web bootstrap record is too large')
url=json.loads(raw)['url'];parts=urlsplit(url)
if parts.scheme!='http' or parts.hostname!='127.0.0.1' or parts.port!=17318 or parts.username or parts.password or not parts.query:
    raise SystemExit('Agency Web bootstrap origin is invalid')
print(json.dumps({'url':url,'source':peer[0],'target':peer[2]}))
'''


class LaunchError(Exception):
    pass


def validate_url(url):
    if not isinstance(url, str) or len(url)>8192 or any(ord(c)<32 for c in url):
        raise LaunchError('NAS returned an invalid browser address')
    try:
        parts=urlsplit(url)
        valid=(parts.scheme=='http' and parts.hostname=='127.0.0.1' and parts.port==17318
               and not parts.username and not parts.password and bool(parts.query))
    except ValueError:
        valid=False
    if not valid:
        raise LaunchError('NAS returned an unexpected browser origin')
    return url


def fetch_bootstrap():
    command=['/run/current-system/sw/bin/ssh','-T','-S','none','-o','ControlMaster=no','-o','BatchMode=yes',
        '-o','StrictHostKeyChecking=yes','-o','ForwardAgent=no','-o','ConnectTimeout=8',
        '-o','Hostname=100.65.85.114','-o','HostKeyAlias=nas','nas',
        'python3 -c '+shlex.quote(NAS_READER)]
    try:
        result=subprocess.run(command,stdin=subprocess.DEVNULL,capture_output=True,text=True,timeout=15)
    except (OSError,subprocess.TimeoutExpired):
        raise LaunchError('Cannot reach Agency Web on NAS through Tailscale') from None
    if result.returncode or len(result.stdout)>MAX_REPLY:
        # Never echo remote stdout/stderr: it may contain browser credentials.
        raise LaunchError('NAS SSH or managed Agency Web service check failed')
    try:
        record=json.loads(result.stdout)
        if record['source']!='100.121.160.100' or record['target']!='100.65.85.114':
            raise ValueError('unexpected route')
        return validate_url(record['url'])
    except (ValueError,KeyError,TypeError):
        raise LaunchError('NAS returned an invalid Agency Web bootstrap record') from None


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
        raise LaunchError('Agency Web needs exactly one live owned Domicile desktop')
    return live[0]


def verify_current_cli(path, module, cli=SYSTEM_CLI):
    if not cli.is_file() or not os.access(cli,os.X_OK):
        raise LaunchError('Current system Domicile command is unavailable')
    env=dict(os.environ,DOMICILE_SOCK=str(path),XDG_RUNTIME_DIR=str(path.parent))
    try:
        result=subprocess.run([str(cli),'which-shell'],env=env,stdin=subprocess.DEVNULL,capture_output=True,text=True,timeout=5)
    except (OSError,subprocess.TimeoutExpired):
        raise LaunchError('Current system Domicile command did not answer') from None
    if result.returncode or result.stdout.strip()!=module:
        raise LaunchError('Current system Domicile command and desktop do not agree')


def open_app(path,url):
    validate_url(url)
    reply=request(path,{'type':'open_app','url':url,'id':'agency-web','reuse':'focus'})
    if reply!={'type':'opened'}:
        raise LaunchError('Domicile refused Agency Web or its control protocol changed')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true',help='check the current desktop and NAS services without opening or reloading')
    args=parser.parse_args()
    try:
        path,module=find_desktop(Path('/run/user')/str(os.getuid()))
        verify_current_cli(path,module)
        url=fetch_bootstrap()
        if args.check:
            print('Agency Web: one live Domicile desktop; NAS services reachable through verified Tailscale SSH')
        else:
            open_app(path,url)
    except LaunchError as error:
        print('Agency Web: '+str(error),file=sys.stderr)
        return 1
    return 0


if __name__=='__main__':
    raise SystemExit(main())
