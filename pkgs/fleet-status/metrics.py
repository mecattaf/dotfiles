#!/usr/bin/env python3
"""Fixed non-waking proc/AMDGPU counters; no discovery, SMART or model calls."""
import argparse
import datetime
import json
from pathlib import Path


def read_metrics(gpu_device=None):
    result = {"at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "memory": {}, "load": [], "gpu": {}}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        if key in ["MemTotal", "MemAvailable", "SwapTotal", "SwapFree"]:
            result["memory"][key] = int(value.split()[0]) * 1024
    result["load"] = [float(value) for value in Path("/proc/loadavg").read_text().split()[:3]]
    if gpu_device:
        device = Path(gpu_device)
        # A suspended device is never woken just to improve a status display.
        if (device / "power/runtime_status").read_text().strip() == "active":
            for name in ["gpu_busy_percent", "mem_info_gtt_used", "mem_info_vram_used", "mem_info_gtt_total", "mem_info_vram_total"]:
                try:
                    result["gpu"][name] = int((device / name).read_text().strip())
                except (OSError, ValueError):
                    pass
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gpu-device")
    args = parser.parse_args()
    print(json.dumps(read_metrics(args.gpu_device)))
