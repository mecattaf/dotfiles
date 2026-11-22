import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[2] / 'home/dot_local/bin/domicile-perf'
spec = importlib.util.spec_from_loader('domicile_perf', importlib.machinery.SourceFileLoader('domicile_perf', str(SCRIPT)))
perf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(perf)


class PerformanceMeasurement(unittest.TestCase):
    def test_duplicate_fds_are_one_client_and_distinct_devices_stay_distinct(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root / 'proc/42/fdinfo'
            folder.mkdir(parents=True)
            for fd, device, client in [(10, '0000:00:02.0', 6), (11, '0000:00:02.0', 6),
                                       (12, '0000:00:02.0', 5), (13, '0000:03:00.0', 6)]:
                (folder / str(fd)).write_text(f'drm-pdev: {device}\ndrm-client-id: {client}\n'
                                             'drm-engine-render: 100 ns\n')
            real_path = Path
            with patch.object(perf, 'Path', side_effect=lambda p: root / 'proc' if p == '/proc' else real_path(p)):
                clients = perf.drm_clients(42)
            self.assertEqual(len(clients), 3)
            self.assertEqual(sum(perf.render_counters(clients).values()), 300)

    def test_reused_fd_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'fdinfo'
            path.write_text('drm-pdev: device\ndrm-client-id: 7\ndrm-engine-render: 100 ns\n')
            with self.assertRaisesRegex(RuntimeError, 'client changed'):
                perf.render_counters({('device', '6'): path})

    def test_wrap_and_known_occupancy(self):
        before = {'monotonic': 10, 'cpu': [10, 0, 0, 990, 0, 0, 0, 0],
                  'render_ns': {'client': 1_000_000_000}, 'energy_uj': 99_000_000}
        after = {'monotonic': 12, 'cpu': [12, 0, 0, 1188, 0, 0, 0, 0],
                 'render_ns': {'client': 1_600_000_000}, 'energy_uj': 19_000_000,
                 'temperature_c': 62, 'fan_rpm': 2900}
        actual = perf.metrics(before, after, 100_000_000)
        self.assertEqual(actual['gpu_render_pct'], 30)
        self.assertEqual(actual['package_watts'], 10)
        self.assertEqual(actual['cpu_total_pct'], 1)

    def test_reset_and_missing_sensor_are_not_zero_load(self):
        with self.assertRaises(RuntimeError):
            perf.counter_delta(100, 10)
        samples = [{'seconds': 5, 'gpu_render_pct': 20, 'package_watts': None,
                    'cpu_total_pct': 1, 'temperature_c': None, 'fan_rpm': None}]
        self.assertIsNone(perf.summarize(samples)['fan_rpm'])
        self.assertIsNone(perf.summarize(samples)['package_watts'])

    def test_duration_weighted_mean(self):
        samples = []
        for seconds, value in [(5, 10), (1, 40)]:
            samples.append(dict(seconds=seconds, **{k: value for k in
                ['gpu_render_pct', 'package_watts', 'cpu_total_pct', 'temperature_c', 'fan_rpm']}))
        self.assertEqual(perf.summarize(samples)['package_watts']['mean'], 15)

    def test_failed_remote_run_keeps_latest(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / 'state'
            root = state / 'domicile-perf'
            root.mkdir(parents=True)
            latest = root / 'latest.json'
            latest.write_text('{"old": true}')
            fake_bin = Path(directory) / 'bin'
            fake_bin.mkdir()
            fake_ssh = fake_bin / 'ssh'
            fake_ssh.write_text('#!/bin/sh\necho "test remote unavailable" >&2\nexit 17\n')
            fake_ssh.chmod(0o755)
            result = subprocess.run([str(SCRIPT), 'record', '--label', 'test'],
                                    env={**os.environ, 'XDG_STATE_HOME': str(state),
                                         'PATH': str(fake_bin) + ':' + os.environ['PATH']},
                                    text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('No result saved', result.stderr)
            self.assertEqual(json.loads(latest.read_text()), {'old': True})

    def test_success_retains_result_and_exact_reusable_source(self):
        report = {'schema': 1, 'started_at': '2026-11-22T00:00:00Z',
                  'metadata': {'running_version': 'fixture'}, 'summary': {}, 'warnings': []}
        with tempfile.TemporaryDirectory() as directory, \
                patch.dict(os.environ, {'XDG_STATE_HOME': directory}), \
                patch.object(sys, 'argv', ['domicile-perf', 'record', '--label', 'fixture']), \
                patch.object(perf.subprocess, 'run', return_value=subprocess.CompletedProcess(
                    [], 0, json.dumps(report), '')), patch('sys.stdout', new_callable=io.StringIO):
            perf.main()
            root = Path(directory) / 'domicile-perf'
            saved = json.loads((root / 'latest.json').read_text())
            self.assertEqual(saved['label'], 'fixture')
            self.assertEqual((root / 'run').resolve().name, 'collector-' + saved['collector_sha256'] + '.py')
            self.assertEqual((root / 'run').read_text(), SCRIPT.read_text())


if __name__ == '__main__':
    unittest.main()
