#!/usr/bin/env python3
"""Template: generated self-contained artifact requires separate installation authorization."""
from rescue import *  # embedded in reviewed output
import ctypes
import fcntl
import shutil
import tempfile

FROZEN_KEYS = (
    "hostname", "machine_id", "boot_id", "kernel", "booted", "current", "bootspec",
    "boot_json_sha256", "assets", "kernel_release_string", "module_versions",
    "kernel_params", "cmdline", "kernel_type", "bootctl_version", "secure_boot",
    "esp_path", "boot_path", "mount", "loader_conf", "selectors", "entries",
    "boot_entries", "closure", "installed_sources", "collisions", "selector_values", "esp_files",
)


def preflight(plan, fresh):
    expected = build_plan(plan["snapshot"])
    require(plan == expected, "plan or derived targets differ from validated snapshot")
    build_plan(fresh)
    for key in FROZEN_KEYS:
        require(fresh[key] == plan["snapshot"][key], f"state changed since review: {key}")


def fsync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def safe_directory(path):
    path = Path(path)
    require(path.is_dir() and not path.is_symlink(), f"unsafe destination directory: {path}")
    require(path.resolve() == path, f"symlink ancestor in destination: {path}")


def publish_noreplace(staged, target):
    """Atomic, no replacement, including on FAT (no hardlink assumption)."""
    libc = ctypes.CDLL(None, use_errno=True)
    rc = libc.renameat2(-100, os.fsencode(staged), -100, os.fsencode(target), 1)
    if rc:
        err = ctypes.get_errno()
        raise OSError(err, os.strerror(err), str(target))



def stage_copy(source, directory, expected_hash, expected_size):
    safe_directory(directory)
    fd, name = tempfile.mkstemp(prefix=".domicile-rescue-", suffix=".tmp", dir=directory)
    # Preserve partial stages on errors for operator inspection.
    with os.fdopen(fd, "wb") as dst, open(source, "rb") as src:
        shutil.copyfileobj(src, dst, 1024 * 1024)
        dst.flush()
        os.fsync(dst.fileno())
    require(Path(name).stat().st_size == expected_size and hash_file(name) == expected_hash,
            f"staged asset verification failed: {name}")
    return Path(name)


def verify_menu(plan, entries):
    matches = [e for e in entries if e.get("id") == plan["target"]["entry_id"]]
    require(len(matches) == 1, "rescue is not visible exactly once in bootctl")
    e = matches[0]
    require(e.get("type") == "type1" and e.get("path") == plan["target"]["entry"],
            "rescue visibility is firmware history rather than a real entry")
    require(not e.get("isDefault") and not e.get("isSelected"), "rescue became default/selected")
    require(e.get("linux") == plan["target"]["kernel"]
            and e.get("initrd") == [plan["target"]["initrd"]]
            and e.get("options") == parameters(plan["snapshot"]), "bootctl parsed unexpected rescue paths/options")
    require([e["id"] for e in entries if e.get("isDefault")] == [plan["default_id"]],
            "effective default changed")


def postflight(plan):
    s = plan["snapshot"]
    for k in ("kernel", "initrd"):
        p = ESP / plan["target"][k].lstrip("/")
        require(hash_file(p) == s["assets"][k]["sha256"], f"installed {k} digest differs")
    require(Path(plan["target"]["gcroot"]).is_symlink()
            and os.readlink(plan["target"]["gcroot"]) == s["booted"], "GC root is missing or wrong")
    require(selectors() == s["selectors"], "EFI boot/default/oneshot selectors changed")
    for path, record in s["esp_files"].items():
        require(file_record(ESP/path) == record, f"existing EFI file changed: {path}")
    require((ESP/"loader/loader.conf").read_text() == s["loader_conf"], "loader.conf changed")
    for name, contents in s["entries"].items():
        require((ESP/"loader/entries"/name).read_text() == contents, f"existing entry changed: {name}")
    entries = json.loads(run("bootctl", "--no-pager", "list", "--json=short"))
    verify_menu(plan, entries)
    return entries


def apply(plan):
    """Only called by install_main after explicit root+closure authorization."""
    # Lock an existing root directory; do not create runtime lock files.
    fd = os.open(GCROOTS, os.O_RDONLY | os.O_DIRECTORY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        preflight(plan, observe())
        safe_directory(GCROOTS)
        safe_directory(ESP/"EFI")
        safe_directory(ESP/"loader/entries")
        target = plan["target"]
        # A direct GC root pins the *whole system*, not just kernel and initrd.
        os.symlink(plan["snapshot"]["booted"], target["gcroot"])
        fsync_dir(GCROOTS)
        require(os.readlink(target["gcroot"]) == plan["snapshot"]["booted"], "failed to establish GC root")
        assets_dir = ESP/"EFI/domicile-rescue"
        if not assets_dir.exists():
            assets_dir.mkdir()
            fsync_dir(assets_dir.parent)
        safe_directory(assets_dir)
        staged = {}
        for k in ("kernel", "initrd"):
            a = plan["snapshot"]["assets"][k]
            staged[k] = stage_copy(a["path"], assets_dir, a["sha256"], a["size"])
        for k in ("kernel", "initrd"):
            publish_noreplace(staged[k], ESP/target[k].lstrip("/"))
            fsync_dir(assets_dir)
        # Check selector identity again immediately before publishing an entry.
        require(selectors() == plan["snapshot"]["selectors"], "selectors changed during staging")
        require((ESP/"loader/loader.conf").read_text() == plan["snapshot"]["loader_conf"],
                "loader.conf changed during staging")
        fd_entry, stage = tempfile.mkstemp(prefix=".domicile-rescue-", suffix=".tmp",
                                           dir=ESP/"loader/entries")
        with os.fdopen(fd_entry, "wb") as f:
            f.write(plan["entry_text"].encode())
            f.flush()
            os.fsync(f.fileno())
        published = False
        try:
            publish_noreplace(stage, target["entry"])
            published = True
            fsync_dir(Path(target["entry"]).parent)
            entries = postflight(plan)
        except BaseException:
            # Only withdraw our just-created entry; retain root/assets/stages.
            # The selectors are never written, even during recovery.
            if published and Path(target["entry"]).read_text() == plan["entry_text"]:
                Path(target["entry"]).unlink()
                fsync_dir(Path(target["entry"]).parent)
            raise
        return dict(status="INSTALLED_VERIFIED_NOT_DEFAULT", entry_id=target["entry_id"],
                    default_id=plan["default_id"], selectors_unchanged=True,
                    gcroot=target["gcroot"], booted=plan["snapshot"]["booted"],
                    rescue_boot_tested=False,
                    installed_asset_sha256={k: plan["snapshot"]["assets"][k]["sha256"]
                                            for k in ("kernel","initrd")})
    finally:
        os.close(fd)


def install_main(plan):
    ap = argparse.ArgumentParser(description="Install ONLY the reviewed booted-closure rescue entry")
    ap.add_argument("--authorize-install", required=True, metavar="ACTUAL_BOOTED_CLOSURE")
    args = ap.parse_args()
    try:
        require(os.geteuid() == 0, "installation requires root")
        require(args.authorize_install == plan["snapshot"]["booted"], "wrong authorized closure")
        receipt = apply(plan)
        print(json.dumps(receipt, indent=2))
    except (Refusal, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as e:
        print(json.dumps(dict(status="FAILED", error=str(e),
            note="Inspect retained GC root/assets/stages; do not remove protection blindly. "
                 "No boot selector is written by this installer.")), file=sys.stderr)
        sys.exit(1)
