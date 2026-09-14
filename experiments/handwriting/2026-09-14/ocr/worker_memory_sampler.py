"""Read-only worker sampler; invoked over SSH by effort_benchmark.py."""
import json
import re
import time
from pathlib import Path

device = next(Path('/sys/class/drm').glob('card[0-9]*/device/gpu_busy_percent')).parent


def number(path):
    try:
        return int(path.read_text().strip())
    except (OSError, ValueError):
        return None


def status(path):
    result = {}
    try:
        for line in path.read_text().splitlines():
            key, _, val = line.partition(':')
            if key in ['VmRSS', 'VmLck', 'VmPin', 'RssAnon', 'RssFile', 'RssShmem', 'MemTotal', 'MemAvailable', 'Mlocked', 'Unevictable', 'Cached']:
                result[key + '_bytes'] = int(val.split()[0]) * 1024
    except OSError:
        pass
    return result


engine_pids = []
frontend_pids = []
for proc in Path('/proc').glob('[0-9]*'):
    try:
        if proc.joinpath('comm').read_text().strip() == 'flash_serve':
            engine_pids.append(proc.name)
        args = proc.joinpath('cmdline').read_bytes().split(b'\0')
        if b'/halogen/tools/serve_api.py' in args:
            frontend_pids.append(proc.name)
    except OSError:
        pass
end = time.monotonic() + 1200
while time.monotonic() < end:
    sample = {'worker_time_ns': time.time_ns(), 'device': str(device), 'gpu_busy_percent': number(device/'gpu_busy_percent')}
    for name in ['mem_info_gtt_used', 'mem_info_gtt_total', 'mem_info_vram_used', 'mem_info_vram_total']:
        sample[name + '_bytes'] = number(device/name)
    sample['host_memory'] = status(Path('/proc/meminfo'))
    sample['engines'] = {pid: status(Path('/proc')/pid/'status') for pid in engine_pids}
    sample['frontends'] = {pid: status(Path('/proc')/pid/'status') for pid in frontend_pids}
    try:
        value = Path('/sys/kernel/debug/kfd/mem_limit').read_text()
        sample['kfd_memory'] = {kind.lower()+'_used_bytes': int(used)*2**20 for kind,used in re.findall(r'(System|TTM) mem used (\d+)M', value)}
    except OSError:
        sample['kfd_memory'] = None
    try:
        print(json.dumps(sample), flush=True)
    except BrokenPipeError:
        break
    time.sleep(0.25)
