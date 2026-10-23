"""Check the generated PM QoS bytes and fd inheritance using a regular file."""

import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


source = Path(sys.argv[1]).read_text()
device_open = "exec 3> /dev/cpu_dma_latency"
assert source.count(device_open) == 1
# Replace only the device open and final sleep. Never open the real device,
# even if this test is invoked outside the Nix builder's private /dev.
fixture = source.replace(device_open, 'exec 3> "$1"')
fixture, count = re.subn(
    r"^exec /nix/store/[^/]+/bin/sleep infinity$",
    'exec "$2" -c \'import os; assert os.fstat(3).st_ino == os.stat(os.environ["QOS_FILE"]).st_ino\'',
    fixture,
    flags=re.MULTILINE,
)
assert count == 1
assert "/dev/cpu_dma_latency" not in fixture
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    script = root / "hold-fixture.sh"
    target = root / "cpu-latency-file"
    script.write_text(fixture)
    subprocess.run(
        [sys.argv[2], str(script), str(target), sys.executable],
        env={**os.environ, "QOS_FILE": str(target)},
        check=True,
    )
    assert target.read_bytes() == (100).to_bytes(4, "little", signed=True)
print("PM QoS fixture: 100 us, four bytes, fd 3 survives exec")
