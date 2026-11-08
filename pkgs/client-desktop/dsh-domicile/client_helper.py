#!/usr/bin/env python3
"""Installed on the selected desktop: one private, bounded read-only request."""
import argparse
import json
import os
from pathlib import Path
import re
import stat
import socket as sockets
import subprocess
import sys
import time
import uuid
from protocol import MAX_BYTES, ProtocolError, validate_reply

def private_directory(path, create=False):
    if create:
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info=path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid!=os.getuid() or info.st_mode & 0o077:
        raise ProtocolError("reply directory must be owned by this user and mode 0700")

def discover_socket(config):
    if "socketPath" in config:
        # Explicit path is useful for a named private fixture; production uses
        # a private runtime root and discovers the current launcher instance.
        paths=[Path(config["socketPath"])]
    else:
        runtime=Path(config["runtimeDirectory"])
        if not runtime.is_absolute():raise ProtocolError("absolute runtime directory required")
        private_directory(runtime)
        paths=list(runtime.glob("domicile-ipc.*.sock"))
    candidates=[]
    for path in paths:
        info=path.lstat()
        if not path.is_absolute() or not stat.S_ISSOCK(info.st_mode) or info.st_uid!=os.getuid():
            raise ProtocolError("desktop socket is not owned by this user")
        probe=sockets.socket(sockets.AF_UNIX)
        try:
            probe.settimeout(.2)
            probe.connect(str(path))
            # SO_PEERCRED verifies the process behind this socket, not just
            # the on-disk entry. Do not send a command during discovery.
            import struct
            _,uid,_=struct.unpack("3i",probe.getsockopt(sockets.SOL_SOCKET,sockets.SO_PEERCRED,12))
            if uid!=os.getuid():raise ProtocolError("desktop socket peer UID mismatch")
            candidates.append(path)
        except (ConnectionRefusedError,FileNotFoundError,sockets.timeout):
            continue
        finally:probe.close()
    if len(candidates)!=1:raise ProtocolError("desktop socket is absent or ambiguous")
    return str(candidates[0])

def request(config, desktop_id, expected=None, timeout=3.0, runner=subprocess.run):
    if config.get("desktopId")!=desktop_id:
        raise ProtocolError("selected desktop does not match local configuration")
    if not re.fullmatch(r"[a-z][a-z0-9-]{0,63}",desktop_id):
        raise ProtocolError("invalid desktop identity")
    root=Path(config.get("replyRoot",str(Path.home()/".local/state/dsh-domicile/replies")))
    if not root.is_absolute(): root=Path.home()/root
    private_directory(root,create=True)
    nonce=uuid.uuid4().hex
    directory=root/nonce
    directory.mkdir(mode=0o700)
    private_directory(directory)
    file=directory/"reply.json"
    try:
        binary=config["domicileBinary"]
        socket=discover_socket(config)
        if not Path(binary).is_absolute() or not Path(socket).is_absolute():
            raise ProtocolError("explicit absolute binary/socket required")
        env=dict(os.environ,DOMICILE_SOCK=socket)
        args=[binary,"send-shell","imagine","snapshot-v1",nonce,desktop_id,*([expected[0],str(expected[1])] if expected else ["-","-"])]
        started=time.monotonic()
        delivered=runner(args,env=env,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout,check=False)
        if delivered.returncode!=0: raise ProtocolError("native shell delivery failed")
        while time.monotonic()-started<timeout:
            try:
                fd=os.open(file,os.O_RDONLY|os.O_NOFOLLOW)
            except FileNotFoundError:
                time.sleep(.02)
                continue
            with os.fdopen(fd,"rb") as stream:
                info=os.fstat(stream.fileno())
                if not stat.S_ISREG(info.st_mode) or info.st_uid!=os.getuid():
                    raise ProtocolError("invalid response owner/type")
                data=stream.read(MAX_BYTES+1)
            return validate_reply(data,nonce,desktop_id)
        raise ProtocolError("snapshot timeout; shell absent, locked, or unavailable")
    finally:
        # Own nonce directory only; never clean a shared runtime/state tree.
        try: file.unlink()
        except FileNotFoundError: pass
        directory.rmdir()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("desktop")
    parser.add_argument("--expect-epoch")
    parser.add_argument("--expect-revision",type=int)
    parser.add_argument("--config",type=Path,default=Path.home()/".config/dsh-domicile/client.json")
    options=parser.parse_args()
    if (options.expect_epoch is None)!=(options.expect_revision is None):parser.error("both expected epoch and revision are required")
    try:
        config=json.loads(options.config.read_text())
        expected=(options.expect_epoch,options.expect_revision) if options.expect_epoch else None
        reply=request(config,options.desktop,expected)
        print(json.dumps(reply,separators=(",",":")))
        return 0 if reply["ok"] else 3
    except (OSError,ValueError,KeyError,subprocess.SubprocessError) as error:
        print(json.dumps({"ok":False,"error":{"code":"unavailable","message":str(error) if isinstance(error,ProtocolError) else "local snapshot transport failed"}}))
        return 2

if __name__=="__main__":sys.exit(main())
