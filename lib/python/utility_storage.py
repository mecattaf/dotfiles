"""Resolve utility storage from private, host-local configuration."""
import argparse
import json
import os
from pathlib import Path
import tempfile

KINDS = {"paper": "PAPER_ROOT", "speech": "SPEECH_ROOT", "recordings": "RECORDINGS_ROOT"}


def config_path():
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return Path(os.environ.get("UTILITY_STORAGE_CONFIG", config_home / "utility-storage/paths.json"))


def storage_root(kind):
    if kind not in KINDS:
        raise ValueError("unknown utility kind")
    config = config_path()
    values = json.loads(config.read_text()) if config.exists() else {}
    if not isinstance(values, dict):
        raise ValueError("utility storage configuration must be an object")
    value = os.environ.get(KINDS[kind], values.get(kind))
    if value is None:
        value = str(Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "utility-data" / kind)
    if not isinstance(value, str) or value != value.strip() or any(ord(c) < 32 for c in value):
        raise ValueError("invalid utility storage setting")
    path = Path(value).expanduser()
    if not path.is_absolute() or path == Path("/"):
        raise ValueError("utility storage must be an absolute non-root path")
    return path


def atomic_text(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".storage-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as out:
            out.write(text)
            out.flush()
            os.fsync(out.fileno())
        os.chmod(name, 0o600)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def prepare(watches):
    units = {"paper": "paper-daemon.path", "speech": "speech-queue.path"}
    user = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "systemd/user"
    for kind in watches:
        if kind not in units:
            raise ValueError("utility does not have an intake watcher")
        intake = storage_root(kind) / "intake"
        intake.mkdir(parents=True, exist_ok=True, mode=0o700)
        # Reset the packaged default before setting the private host path.
        # PathChanged takes an absolute path verbatim, not a shell word.
        value = str(intake).replace("%", "%%")
        atomic_text(user / (units[kind] + ".d") / "storage.conf",
                    '[Path]\nPathChanged=\nPathChanged=' + value + '\n')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("kind", nargs="?", choices=sorted(KINDS))
    p.add_argument("--prepare", action="store_true")
    p.add_argument("--watch", action="append", default=[], choices=["paper", "speech"])
    a = p.parse_args()
    if a.prepare:
        prepare(a.watch)
    elif a.kind:
        print(storage_root(a.kind))
    else:
        p.error("select a utility or --prepare")


if __name__ == "__main__":
    main()
