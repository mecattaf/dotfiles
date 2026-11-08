#!/usr/bin/env python3
"""Read-only NixOS systemd-boot rescue observation and artifact generator."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import sys
import time

SCHEMA = 1
ESP = Path("/boot")
STORE = Path("/nix/store")
GCROOTS = Path("/nix/var/nix/gcroots")
EFI = Path("/sys/firmware/efi/efivars")
MARGIN = 16 * 1024 * 1024


class Refusal(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise Refusal(message)


def run(*argv):
    p = subprocess.run(argv, text=True, capture_output=True, timeout=120)
    if p.returncode:
        raise Refusal(f"read command failed ({p.returncode}): {argv!r}\n{p.stderr}")
    if p.stderr:
        sys.stderr.write(p.stderr)
    return p.stdout


def digest(data):
    return hashlib.sha256(data).hexdigest()


def hash_file(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def store_root(path):
    p = Path(path)
    require(p.is_relative_to(STORE) and len(p.parts) >= 4, f"outside store: {path}")
    return str(STORE / p.parts[3])


def asset(path):
    p = Path(path).resolve(strict=True)
    st = p.stat()
    require(stat.S_ISREG(st.st_mode) and st.st_size > 0, f"not a nonempty file: {p}")
    with p.open("rb") as f:
        header = f.read(0x210)
    return dict(path=str(p), size=st.st_size, mode=stat.S_IMODE(st.st_mode),
                sha256=hash_file(p), magic_hex=header[:6].hex(), linux_hdrs_hex=header[0x202:0x206].hex())


def file_record(path):
    p = Path(path)
    if not p.exists():
        return None
    return dict(sha256=hash_file(p), size=p.stat().st_size)


def selectors():
    names = {"LoaderEntryDefault", "LoaderEntryOneShot", "LoaderEntrySelected",
             "LoaderEntrySysFail", "LoaderConfigTimeout", "LoaderConfigTimeoutOneShot"}
    return {p.name: file_record(p) for p in sorted(EFI.iterdir())
            if p.name.startswith("Boot") or p.name.split("-")[0] in names}


def selector_values():
    result = {}
    for name in ("LoaderEntryDefault", "LoaderEntryOneShot", "LoaderEntrySysFail"):
        path = EFI / (name + "-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f")
        if path.exists():
            result[name] = path.read_bytes()[4:].decode("utf-16-le").rstrip("\0")
    return result


def esp_files():
    return {str(p.relative_to(ESP)): file_record(p)
            for p in sorted((ESP/"EFI").rglob("*")) if p.is_file()}


def installed_source(closure):
    switch = (Path(closure) / "bin/switch-to-configuration").read_text()
    m = re.search(r"^export INSTALL_BOOTLOADER='(/nix/store/[^']+)'$", switch, re.M)
    require(m is not None, "cannot identify installed NixOS bootloader wrapper")
    wrapper = Path(m[1])
    wm = re.search(r"^(/nix/store/\S+/bin/systemd-boot) ", wrapper.read_text(), re.M)
    require(wm is not None, "not the installed systemd-boot mechanism")
    source = Path(wm[1])
    text = source.read_text()
    markers = [
        'EFI_SYS_MOUNT_POINT = Path("/boot")',
        'BOOT_MOUNT_POINT = Path("/boot")',
        'for e in os.scandir(BOOT_MOUNT_POINT / NIXOS_DIR):',
        'for e in os.scandir(BOOT_MOUNT_POINT / "loader" / "entries"):',
        'match = re.fullmatch(r"nixos-.+\\.conf", e.name)',
        'kernel_params = " ".join([f"init={bootspec.init}"] + bootspec.kernelParams)',
    ]
    return dict(path=str(source), sha256=hash_file(source), wrapper=str(wrapper),
                markers={m: m in text for m in markers})


def names(booted, kernel):
    nixhash = Path(booted).name.split("-")[0]
    require(re.fullmatch(r"[0-9a-z]{32}", nixhash), "invalid booted store hash")
    require(re.fullmatch(r"[0-9][0-9A-Za-z._-]*", kernel), "unsafe kernel release")
    entry_id = f"domicile-rescue-{kernel}-{nixhash[:8]}.conf"
    return dict(entry_id=entry_id, entry=f"/boot/loader/entries/{entry_id}",
                kernel=f"/EFI/domicile-rescue/{nixhash}-kernel.efi",
                initrd=f"/EFI/domicile-rescue/{nixhash}-initrd.efi",
                gcroot=str(GCROOTS / f"domicile-rescue-{nixhash}"))


def observe():
    require(ESP.is_mount(), "/boot must be a mounted ESP")
    booted = str(Path("/run/booted-system").resolve(strict=True))
    current = str(Path("/run/current-system").resolve(strict=True))
    boot_json = Path(booted) / "boot.json"
    bootspec = json.loads(boot_json.read_text())
    assets = {k: asset(Path(booted) / k) for k in ("kernel", "initrd", "init")}
    with Path(assets["kernel"]["path"]).open("rb") as f:
        header = f.read(0x210)
        offset = int.from_bytes(header[0x20e:0x210], "little") + 0x200
        f.seek(offset)
        release_string = f.read(512).split(b"\0")[0].decode("ascii", errors="strict")
    closure = sorted(set(run("nix-store", "-qR", booted).splitlines()))
    targets = names(booted, os.uname().release)
    collision_paths = [targets["entry"], str(ESP / targets["kernel"].lstrip("/")),
                       str(ESP / targets["initrd"].lstrip("/")), targets["gcroot"]]
    vfs = os.statvfs(ESP)
    s = dict(schema=SCHEMA, observed_at=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
             hostname=os.uname().nodename, kernel=os.uname().release,
             machine_id=Path("/etc/machine-id").read_text().strip(),
             boot_id=Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
             booted=booted, current=current, bootspec=bootspec,
             boot_json_sha256=hash_file(boot_json), assets=assets,
             kernel_release_string=release_string,
             module_versions=sorted(p.name for p in (Path(booted) / "kernel-modules/lib/modules").iterdir()),
             kernel_params= (Path(booted) / "kernel-params").read_text(),
             cmdline=Path("/proc/cmdline").read_text().strip(),
             kernel_type=run("bootctl", "--no-pager", "kernel-identify", assets["kernel"]["path"]).strip(),
             bootctl_version=run("bootctl", "--version").splitlines()[0],
             bootctl_status=run("bootctl", "--no-pager", "status"),
             secure_boot=Path(EFI / "SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c").read_bytes().hex(),
             esp_path=run("bootctl", "--print-esp-path").strip(),
             boot_path=run("bootctl", "--print-boot-path").strip(),
             mount=json.loads(run("findmnt", "-J", "/boot"))["filesystems"],
             esp=dict(available=vfs.f_bavail * vfs.f_frsize, block_size=vfs.f_frsize),
             loader_conf=(ESP / "loader/loader.conf").read_text(),
             selectors=selectors(), selector_values=selector_values(), esp_files=esp_files(),
             entries={p.name: p.read_text() for p in sorted((ESP / "loader/entries").glob("*.conf"))},
             boot_entries=json.loads(run("bootctl", "--no-pager", "list", "--json=short")),
             closure=dict(count=len(closure), sha256=digest(("\n".join(closure)+"\n").encode()),
                          missing=[p for p in closure if not Path(p).exists()],
                          includes_sources=all(store_root(a["path"]) in closure for a in assets.values())),
             installed_sources={k: installed_source(v) for k,v in (("booted",booted),("current",current))},
             collisions=[p for p in collision_paths if os.path.lexists(p)])
    return s


def parameters(s):
    spec = s["bootspec"]["org.nixos.bootspec.v1"]
    params = spec["kernelParams"]
    require(isinstance(params, list) and all(isinstance(x, str) for x in params), "invalid kernelParams")
    tokens = [f'init={spec["init"]}'] + params
    require(all(t and not re.search(r"\s", t) for t in tokens), "ambiguous or multiline options")
    require(not any(t.startswith(("init=", "initrd=", "BOOT_IMAGE=")) for t in params),
            "boot loader arguments inside kernelParams")
    # Do not shlex-decode the backslashes in the EFI-added initrd= argument.
    live = s["cmdline"].split()
    source = Path(spec["initrd"])
    old_name = Path(store_root(source)).name + "-" + source.name + ".efi"
    initrds = [t[len("initrd="):].replace(chr(92), "/") for t in live if t.startswith("initrd=")]
    require(initrds == ["/EFI/nixos/" + old_name], "live EFI initrd argument differs from booted source")
    stripped = [t for t in live if not t.startswith("initrd=")]
    require(stripped == tokens, "live cmdline differs from bootspec beyond EFI initrd= argument")
    require(s["kernel_params"].split() == params, "kernel-params differs from bootspec")
    return " ".join(tokens)


def validate(s):
    require(s["schema"] == SCHEMA, "unsupported snapshot schema")
    require(s["hostname"] == "client", "this preparation is bounded to hostname client")
    require(re.fullmatch(r"[0-9a-f]{32}", s["machine_id"]), "invalid machine-id")
    require(s["esp_path"] == "/boot" and s["boot_path"] == "/boot", "XBOOTLDR/ESP layout differs")
    require(len(s["mount"]) == 1 and s["mount"][0]["target"] == "/boot"
            and s["mount"][0]["fstype"] == "vfat", "not the measured FAT ESP")
    require("rw" in s["mount"][0]["options"].split(","), "ESP is mounted read-only")
    require(s["secure_boot"][-2:] == "00", "Secure Boot requires a separately reviewed signing workflow")
    require("systemd-boot" in s["bootctl_status"], "not running systemd-boot")
    for source in s["installed_sources"].values():
        require(all(source["markers"].values()), "installed NixOS bootloader layout/cleanup differs")
    spec = s["bootspec"]["org.nixos.bootspec.v1"]
    require(spec["system"] == "x86_64-linux", "unsupported architecture")
    require(spec["toplevel"] == s["booted"] and spec["init"] == s["booted"]+"/init",
            "bootspec does not describe actual booted closure")
    require(not spec.get("initrdSecrets"), "initrd secret appending requires separate review")
    require(not s["bootspec"].get("org.nixos.extra-initrd.v1", {}).get("paths"), "extra initrds unsupported")
    require(not s["bootspec"].get("org.nixos.systemd-boot", {}).get("devicetree"), "devicetree unsupported")
    for k in ("kernel", "initrd", "init"):
        a = s["assets"][k]
        store_root(a["path"])
        require(a["path"] == spec[k], f"bootspec/link mismatch for {k}")
        require(a["size"] > 0 and not (a["mode"] & 0o222), f"empty or writable store {k}")
        require(re.fullmatch("[0-9a-f]{64}", a["sha256"]), f"invalid digest for {k}")
    require(s["assets"]["init"]["mode"] & 0o111, "init is not executable")
    init_header = bytes.fromhex(s["assets"]["init"]["magic_hex"])
    require(init_header.startswith((b"\x7fELF", b"#!")), "unrecognized init executable")
    k = s["assets"]["kernel"]
    require(k["magic_hex"].startswith("4d5a") and k["linux_hdrs_hex"] == b"HdrS".hex() and s["kernel_type"] == "pe",
            "kernel is not an x86 Linux EFI-stub PE image")
    require(s["kernel_release_string"].split()[0] == s["kernel"], "kernel image differs from uname")
    require(s["module_versions"] == [s["kernel"]], "kernel module version mismatch")
    ih = bytes.fromhex(s["assets"]["initrd"]["magic_hex"])
    require(any(ih.startswith(m) for m in (b"\x1f\x8b", b"\x28\xb5\x2f\xfd", b"\xfd7zXZ\x00",
                                         b"070701", b"070702")), "unrecognized initrd format")
    require(s["closure"]["count"] > 0 and not s["closure"]["missing"]
            and s["closure"]["includes_sources"], "incomplete booted system closure")
    require(not s["collisions"], f"rescue destination already exists: {s['collisions']}")
    require(len(s["entries"]) > 0, "no existing boot entries")
    defaults = [e for e in s["boot_entries"] if e.get("isDefault")]
    require(len(defaults) == 1 and defaults[0]["id"] in s["entries"], "default is not a real entry")
    require(defaults[0].get("sortKey") == "nixos", "unexpected default sorting")
    require(all(re.match(r"Generation [1-9][0-9]* ", e.get("version", "")) for e in s["boot_entries"]
                if e.get("type") == "type1"), "unexpected existing version ordering")
    n = names(s["booted"], s["kernel"])
    for key, value in s["selector_values"].items():
        require(value in s["entries"] or value == "nixos-*",
                f"unreviewed {key} selector: {value!r}")
    for line in s["loader_conf"].splitlines():
        parts = line.split()
        if parts and parts[0] in ("default", "preferred"):
            require(len(parts) == 2 and (parts[1] in s["entries"] or parts[1] == "nixos-*"),
                    "default/preferred glob could select rescue; review required")
    parameters(s)
    allocation = s["esp"]["block_size"]
    required = sum(((s["assets"][k]["size"] + allocation-1)//allocation)*allocation
                   for k in ("kernel","initrd")) + allocation + MARGIN
    require(s["esp"]["available"] >= required, f"insufficient ESP space: need {required}")
    return n, required, defaults[0]["id"]


def build_plan(s):
    n, required, default = validate(s)
    title = f"Domicile rescue - booted Linux {s['kernel']} ({Path(s['booted']).name[:8]})"
    entry = "\n".join([f"title {title}", "sort-key nixos", "version Generation 0 rescue",
                        f"machine-id {s['machine_id']}", f"linux {n['kernel']}",
                        f"initrd {n['initrd']}", f"options {parameters(s)}", ""])
    return dict(schema=SCHEMA, status="VALIDATED_READ_ONLY_PREPARATION",
                snapshot_sha256=digest(json.dumps(s, sort_keys=True).encode()),
                snapshot=s, target=n, title=title, entry_text=entry, required_bytes=required,
                default_id=default, mutations_executed=False,
                guard="install requires root and --authorize-install ACTUAL_BOOTED_CLOSURE",
                human_steps=[
                    "At the keyboard, authorize rescue installation separately from the desktop transition.",
                    "Refresh observation and artifacts; compare them with this reviewed plan if state changed.",
                    "Review install-reviewed.py and preview.json, then run its explicit authorization command.",
                    "Require the successful install receipt: durable GC root, verified assets, visible non-default entry, unchanged selectors.",
                    "Open the physical systemd-boot menu and confirm the named rescue entry before transition.",
                    "Select rescue manually for a supervised boot test; this preparation does not prove a successful rescue boot.",
                    "Keep the rescue entry, its dedicated ESP assets and GC root until recovery is no longer needed."])


def render(s, out):
    p = build_plan(s)
    out = Path(out)
    out.mkdir(parents=True, exist_ok=False)
    (out/"plan.json").write_text(json.dumps(p, indent=2)+"\n")
    (out/"rescue-entry.conf").write_text(p["entry_text"])
    core = Path(__file__).read_text().split("\ndef render(")[0]
    template = Path(__file__).with_name("install.py").read_text()
    script = template.replace("from rescue import *  # embedded in reviewed output", core)
    script += "\nif __name__ == '__main__':\n    install_main(" + repr(p) + ")\n"
    compile(script, str(out/"install-reviewed.py"), "exec")
    (out/"install-reviewed.py").write_text(script)
    (out/"PLAN.txt").write_text(
        f"VALIDATED read-only preparation; NOT installed and NOT boot-tested.\n"
        f"Observed: {s['observed_at']}; host {s['hostname']}; Linux {s['kernel']}\n"
        f"Booted: {s['booted']}\nInstalled: {s['current']}\n"
        f"Existing real entry files: {len(s['entries'])}. Firmware history alone is not bootable.\n"
        f"Rescue title: {p['title']}\nEntry: {p['target']['entry']}\n"
        f"Durable direct GC root: {p['target']['gcroot']} -> {s['booted']}\n"
        f"Closure: {s['closure']['count']} present store paths; list sha256 {s['closure']['sha256']}\n"
        f"ESP free {s['esp']['available']} bytes; required incl 16 MiB margin {p['required_bytes']} bytes.\n"
        f"Existing default remains {p['default_id']}.\n"
        "Kernel and initrd use /EFI/domicile-rescue, outside NixOS installer garbage collection.\n"
        "Entry starts domicile-rescue, outside nixos-*.conf garbage collection; Generation 0 rescue ranks below installed generations.\n"
        "A Strix bootctl fixture preview must confirm the entry ranks below the existing default.\n"
        "The later installer revalidates source/boot/layout/entries/EFI-selector identity before writes.\n"
        "It pins the entire closure first, stages and hashes both assets, publishes the entry last by rename,\n"
        "checks visibility/default/selectors, and removes only its new entry on post-publication verification failure.\n"
        "No automatic unpin/cleanup: partial artifacts and failures remain for review.\n\n"
        "Later, ONLY after explicit authorization on client, review then run:\n"
        f"sudo -n python3 install-reviewed.py --authorize-install {shlex.quote(s['booted'])}\n\n"
        + "\n".join(f"{i+1}. {x}" for i,x in enumerate(p["human_steps"])) + "\n")
    return dict(status=p["status"], out=str(out), entry_id=p["target"]["entry_id"],
                required_bytes=p["required_bytes"], available_bytes=s["esp"]["available"],
                script_sha256=hash_file(out/"install-reviewed.py"))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="command", required=True)
    sub.add_parser("observe", help="read client state to stdout; no writes")
    p = sub.add_parser("render", help="validate snapshot and generate local review artifacts")
    p.add_argument("--snapshot", required=True)
    p.add_argument("--out", required=True)
    args = ap.parse_args()
    try:
        if args.command == "observe":
            result = observe()
        else:
            s = json.load(sys.stdin if args.snapshot == "-" else open(args.snapshot))
            result = render(s, args.out)
        print(json.dumps(result, indent=2))
    except (Refusal, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as e:
        print(f"REFUSED: {e}", file=sys.stderr)
        return 1
    return 0


# CLI ENTRYPOINT
if __name__ == "__main__":
    sys.exit(main())
