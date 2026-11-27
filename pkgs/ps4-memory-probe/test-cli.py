"""Exercise argument/preflight rejection without opening any GPU device."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

binary, source = sys.argv[1:]
source_hash = hashlib.sha256(Path(source).read_bytes()).hexdigest()
# This basename cannot be a Linux DRM minor. Never select an actual device.
node = "/dev/dri/renderD99999999999999999999999999999999"
cases = [
    (["--node", node, "--touch"], "arguments"),
    (["--node", node, "--allocate-mib", "0"], "arguments"),
    (["--node", node, "--allocate-mib", "-1"], "arguments"),
    (["--node", node, "--allocate-mib", "1.5"], "arguments"),
    (["--node", node, "--allocate-mib", "18446744073709551616"], "arguments"),
    (["--node", node, "--allocate-mib", "17592186044416"], "arguments"),
    (["--node", "/dev/dri/card0"], "arguments"),
    # Valid uint64 arithmetic even with the 256-MiB reserve, but physically
    # impossible: the memory preflight must reject this before device access.
    (["--node", node, "--allocate-mib", "17592186044159"], "preflight"),
    (["--node", node], "open-node"),
]
for arguments, expected_stage in cases:
    result = subprocess.run(
        [binary, *arguments], capture_output=True, text=True, timeout=10
    )
    rows = [json.loads(line) for line in result.stdout.splitlines()]
    assert result.returncode == 1, (arguments, result.returncode, result.stderr)
    assert rows and rows[-1]["stage"] == expected_stage, (arguments, rows)
    assert rows[-1]["status"] == "fail", (arguments, rows)
    for row in rows:
        assert row["sourceSha256"] == source_hash, row
        assert not row["allocationAccepted"], row
        assert not row["gpuSubmissionPerformed"], row
        assert not row["gpuVaMappingAccepted"], row
        assert not row["cpuMappingAccepted"], row
    assert not any(row["stage"] == "query" for row in rows), rows
print(f"PASS: {len(cases)} no-device CLI guards; source SHA256 {source_hash}")
