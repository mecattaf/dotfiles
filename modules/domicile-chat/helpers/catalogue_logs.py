"""Private helper diagnostics; never print Host URLs or metadata into shell logs."""
import os
from pathlib import Path
import stat


def diagnostic(name):
    directory = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'agency-chat-window/diagnostics'
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError('Untrusted diagnostic directory')
    path = directory / (name + '.log')
    if path.exists() and path.stat().st_size > 1024 * 1024:
        os.replace(path, path.with_suffix('.previous.log'))
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        os.close(fd); raise ValueError('Untrusted diagnostic file')
    return os.fdopen(fd, 'ab', buffering=0)
