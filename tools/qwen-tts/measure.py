"""Sample coordinator process and AMD driver counters during one isolated run.

PPT is the APU sensor, not wall power. RSS, GTT, VRAM and allocator statistics
overlap on unified memory; never add them to claim total memory consumption.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import threading
import time


class Meter:
    def __init__(self, pid=None, interval=0.1):
        self.pid = pid
        self.interval = interval
        self.rows = []
        self.done = threading.Event()
        self.thread = None
        self.device = Path('/sys/class/drm/card1/device')
        self.power = next(self.device.glob('hwmon/hwmon*/power1_average'), None)

    @staticmethod
    def value(path):
        try:
            return int(path.read_text().strip())
        except (OSError, ValueError, AttributeError):
            return None

    def sample(self):
        row = {'t': time.monotonic(), 'gpu_busy_percent': self.value(self.device / 'gpu_busy_percent'),
               'driver_vram_bytes': self.value(self.device / 'mem_info_vram_used'),
               'driver_gtt_bytes': self.value(self.device / 'mem_info_gtt_used'),
               'apu_ppt_microwatts': self.value(self.power)}
        if self.pid:
            pids, todo, rss, ticks = set(), [self.pid], 0, 0
            while todo:
                pid = todo.pop()
                if pid in pids:
                    continue
                pids.add(pid)
                try:
                    root = Path('/proc') / str(pid)
                    fields = (root / 'stat').read_text().rsplit(')', 1)[1].split()
                    ticks += int(fields[11]) + int(fields[12])
                    rss += int((root / 'statm').read_text().split()[1]) * os.sysconf('SC_PAGE_SIZE')
                    for children in root.glob('task/*/children'):
                        todo.extend(map(int, children.read_text().split()))
                except (OSError, ValueError, IndexError):
                    pass
            row.update(process_tree_rss_bytes=rss, process_tree_cpu_seconds=ticks / os.sysconf('SC_CLK_TCK'))
        self.rows.append(row)

    def __enter__(self):
        self.sample()
        def loop():
            while not self.done.wait(self.interval):
                self.sample()
        self.thread = threading.Thread(target=loop, daemon=True)
        self.thread.start()
        return self

    def __exit__(self, *args):
        self.done.set()
        self.thread.join()
        self.sample()

    def report(self):
        result = {'interval_seconds': self.interval, 'samples': len(self.rows),
                  'sensor_path': str(self.device),
                  'caveats': ['APU PPT sensor is not whole-system wall power.',
                              'Driver counters are device-wide, including background allocations.',
                              'RSS, driver GTT/VRAM, and torch allocator statistics overlap; do not sum.',
                              'Sampled peaks can miss transients shorter than the polling interval.']}
        for key in sorted({key for row in self.rows for key in row}):
            values = [r[key] for r in self.rows if r.get(key) is not None]
            if key != 't' and values:
                result[key] = {'baseline': values[0], 'peak': max(values), 'mean': sum(values) / len(values),
                               'peak_minus_baseline': max(values) - values[0]}
        result['sampled_apu_ppt_joules'] = sum(
            (b['t'] - a['t']) * (a['apu_ppt_microwatts'] + b['apu_ppt_microwatts']) / 2e6
            for a, b in zip(self.rows, self.rows[1:])
            if a.get('apu_ppt_microwatts') is not None and b.get('apu_ppt_microwatts') is not None)
        return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--timeout', type=float, default=900)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    start = time.monotonic()
    with Meter() as meter:
        child = subprocess.Popen(command)
        meter.pid = child.pid
        try:
            code = child.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            child.terminate()
            try:
                child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
            code = 124
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({'command': command, 'exit_code': code,
        'wall_seconds': time.monotonic() - start, 'resources': meter.report()}, indent=2) + '\n')
    raise SystemExit(code)
