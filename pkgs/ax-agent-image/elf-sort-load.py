#!/usr/bin/env python3
"""Reorder an ELF64 program header table so gVisor's loader accepts it.

The ELF spec says loadable segments appear in ascending p_vaddr order, and
PT_PHDR and PT_INTERP precede every PT_LOAD. Linux tolerates a table that
breaks this; gVisor's loader refuses it with ENOEXEC, which bash reports as
exit 126. pi 0.85.1 from llm-agents ships such a table: its first PT_LOAD maps
vaddr 0x6431000 and a later one 0x1ff000 (MEASURED 2026-09-23, ax-fleet
INTEGRATE.md). The fix moves table entries only: every segment keeps its file
offset, address, size and flags, and the table keeps its place and length.

Usage: elf-sort-load.py FILE...   (files that are not ELF64 LE, or are already
in order, are left alone; prints one line per file it changed)
"""
import struct
import sys

PT_LOAD, PT_INTERP, PT_PHDR = 1, 3, 6


def fix(path):
    with open(path, "r+b") as f:
        ident = f.read(64)
        if len(ident) < 64 or ident[:4] != b"\x7fELF" or ident[4] != 2 or ident[5] != 1:
            return False
        (phoff,) = struct.unpack_from("<Q", ident, 32)
        phentsize, phnum = struct.unpack_from("<HH", ident, 54)
        if phnum == 0 or phentsize < 56:
            return False
        f.seek(phoff)
        table = f.read(phentsize * phnum)
        entries = [table[i * phentsize : (i + 1) * phentsize] for i in range(phnum)]
        kind = [struct.unpack_from("<I", e, 0)[0] for e in entries]
        vaddr = [struct.unpack_from("<Q", e, 16)[0] for e in entries]

        head = [i for i in range(phnum) if kind[i] == PT_PHDR] + [i for i in range(phnum) if kind[i] == PT_INTERP]
        loads = sorted((i for i in range(phnum) if kind[i] == PT_LOAD), key=lambda i: vaddr[i])
        rest = [i for i in range(phnum) if i not in head and i not in loads]
        order = head + loads + rest
        if order == list(range(phnum)):
            return False
        assert sorted(order) == list(range(phnum))
        f.seek(phoff)
        f.write(b"".join(entries[i] for i in order))
    print(f"elf-sort-load: {path}: program headers reordered {list(range(phnum))} -> {order}")
    return True


if __name__ == "__main__":
    for p in sys.argv[1:]:
        fix(p)
