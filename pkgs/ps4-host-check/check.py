"""Read-only PS4 host admission checks; never allocates or dispatches GPU work."""

import argparse
import json
from pathlib import Path
import re
import sys

GIB = 1024**3
PAGE_SIZE = 4096
BACKING_BYTES = 7 * GIB


def read(path):
    try:
        return path.read_text().strip()
    except (OSError, UnicodeError):
        return None


def number(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def inspect(root=Path('/')):
    """Collect visible capacity/configuration only, including explicit unknowns."""
    checks = []

    def add(name, okay, detail):
        checks.append({'name': name, 'status': 'unknown' if okay is None else 'pass' if okay else 'fail',
                       'detail': detail})

    command_line = read(root / 'proc/cmdline')
    arguments = (command_line or '').split()
    meminfo = read(root / 'proc/meminfo') or ''
    memory = {name: int(value) * 1024 for name, value in re.findall(r'^(MemTotal|MemAvailable):\s+(\d+) kB', meminfo, re.M)}
    add('physical-memory', None if 'MemTotal' not in memory else memory['MemTotal'] >= 7680 * 1024**2,
        {'MemTotalBytes': memory.get('MemTotal'), 'MemAvailableBytes': memory.get('MemAvailable'),
         'minimumTotalMiB': 7680, 'note': 'Total capacity is not free or GPU-allocated memory.'})
    add('gpu-driver-enabled', None if command_line is None else
        not any(arg == 'nomodeset' or arg in ('amdgpu.modeset=0', 'modprobe.blacklist=amdgpu') for arg in arguments),
        {'cmdline': command_line, 'note': 'A headless host still needs its amdgpu render device.'})
    page_limit = number(read(root / 'sys/module/ttm/parameters/pages_limit'))
    requested = next((number(arg.split('=', 1)[1]) for arg in arguments if arg.startswith('ttm.pages_limit=')), None)
    add('ttm-command-line', None if command_line is None else requested is not None and requested >= BACKING_BYTES // PAGE_SIZE,
        {'requestedPages': requested, 'minimumPages': BACKING_BYTES // PAGE_SIZE})
    add('ttm-effective-limit', None if page_limit is None else page_limit >= BACKING_BYTES // PAGE_SIZE,
        {'effectivePages': page_limit, 'minimumPages': BACKING_BYTES // PAGE_SIZE,
         'note': 'This is a ceiling, not a reservation or successful allocation.'})
    devices = []
    for path in sorted((root / 'sys/class/drm').glob('card*/device/mem_info_gtt_total')):
        devices.append({'path': str(path.relative_to(root)), 'bytes': number(read(path))})
    known = [entry['bytes'] for entry in devices if entry['bytes'] is not None]
    add('gtt-capacity', None if not known else max(known) >= BACKING_BYTES,
        {'devices': devices, 'minimumBytes': BACKING_BYTES,
         'note': 'Shared GDDR5 backing, never add GTT and system RAM as independent capacities.'})
    render = sorted(str(path.relative_to(root)) for path in (root / 'dev/dri').glob('renderD*'))
    add('render-device', bool(render), {'nodes': render})
    add('tailscale-tun', (root / 'dev/net/tun').exists(), {'path': '/dev/net/tun'})
    try:
        policy = json.loads(read(root / 'etc/ps4/appliance.json') or 'null')
    except ValueError:
        policy = None
    add('appliance-policy', isinstance(policy, dict) and policy.get('host') == 'ps4-dummy', {'policy': policy})
    declared_mib = number(policy.get('gpuBackingLimitMiB')) if isinstance(policy, dict) else None
    declared_pages = declared_mib * 1024**2 // PAGE_SIZE if declared_mib else None
    add('declared-gpu-budget', None if declared_pages is None else
        requested == declared_pages and page_limit is not None and page_limit >= declared_pages,
        {'declaredMiB': declared_mib, 'declaredPages': declared_pages,
         'requestedPages': requested, 'effectivePages': page_limit,
         'note': 'The running external boot arguments must match the selected NixOS budget.'})
    expected_release = policy.get('kernelRelease') if isinstance(policy, dict) else None
    running_release = read(root / 'proc/sys/kernel/osrelease')
    module_directory = root / 'run/current-system/kernel-modules/lib/modules' / (running_release or 'unknown')
    add('kernel-module-pair', None if not expected_release or not running_release else
        expected_release == running_release and module_directory.is_dir(),
        {'expectedRelease': expected_release, 'runningRelease': running_release,
         'matchingModules': module_directory.is_dir(),
         'note': 'A userspace generation switch does not update the external FAT boot set.'})
    return {'schemaVersion': 1, 'checks': checks,
            'configurationReady': all(item['status'] == 'pass' for item in checks),
            'qualifications': {'gpuAllocation7GiB': False, 'gpuBandwidth': False, 'garlicParity': False,
                               'bonsaiInference': False},
            'next': 'Capacity/configuration checks precede explicit GPU allocation, bandwidth, coherence and model tests.'}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args(argv)
    result = inspect()
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        for item in result['checks']:
            print(f"{item['status'].upper()}: {item['name']}: {json.dumps(item['detail'], sort_keys=True)}")
        print(result['next'])
    return 0 if result['configurationReady'] else 1


if __name__ == '__main__':
    sys.exit(main())
