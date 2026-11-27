"""Admission checks distinguish capacity, unknowns and proof of GPU execution."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('ps4_check', sys.argv.pop(1))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class HostChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name, data in {
            'proc/meminfo': 'MemTotal:       8000000 kB\nMemAvailable:   7400000 kB\n',
            'proc/cmdline': 'root=LABEL=ps4-nixos ttm.pages_limit=1835008',
            'sys/module/ttm/parameters/pages_limit': '1835008',
            'sys/class/drm/card0/device/mem_info_gtt_total': str(7 * 1024**3),
            'dev/dri/renderD128': '', 'dev/net/tun': '',
            'etc/ps4/appliance.json': json.dumps({'host': 'ps4-dummy', 'kernelRelease': 'psx-fixture'}),
            'proc/sys/kernel/osrelease': 'psx-fixture',
        }.items():
            self.write(name, data)
        (self.root / "run/current-system/kernel-modules/lib/modules/psx-fixture").mkdir(parents=True)

    def write(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)

    def checked(self):
        result = checker.inspect(self.root)
        return result, {item['name']: item['status'] for item in result['checks']}

    def test_capacity_does_not_claim_execution_or_allocation(self):
        result, _ = self.checked()
        self.assertTrue(result['configurationReady'])
        self.assertFalse(any(result['qualifications'].values()))

    def test_default_half_ram_ceiling_is_rejected(self):
        self.write('sys/class/drm/card0/device/mem_info_gtt_total', str(4 * 1024**3))
        result, status = self.checked()
        self.assertFalse(result['configurationReady'])
        self.assertEqual(status['gtt-capacity'], 'fail')

    def test_missing_effective_limit_remains_unknown(self):
        (self.root / 'sys/module/ttm/parameters/pages_limit').unlink()
        result, status = self.checked()
        self.assertFalse(result['configurationReady'])
        self.assertEqual(status['ttm-effective-limit'], 'unknown')

    def test_headless_must_not_disable_amdgpu(self):
        self.write('proc/cmdline', 'ttm.pages_limit=1835008 amdgpu.modeset=0')
        _, status = self.checked()
        self.assertEqual(status['gpu-driver-enabled'], 'fail')

    def test_page_limit_is_pages_not_mib(self):
        self.write('proc/cmdline', 'ttm.pages_limit=7168')
        _, status = self.checked()
        self.assertEqual(status['ttm-command-line'], 'fail')

    def test_external_kernel_must_match_installed_module_tree(self):
        self.write('proc/sys/kernel/osrelease', 'other-build')
        result, status = self.checked()
        self.assertFalse(result['configurationReady'])
        self.assertEqual(status['kernel-module-pair'], 'fail')

    def test_no_render_device_fails_even_with_sufficient_memory(self):
        (self.root / 'dev/dri/renderD128').unlink()
        _, status = self.checked()
        self.assertEqual(status['render-device'], 'fail')


if __name__ == '__main__':
    unittest.main()
