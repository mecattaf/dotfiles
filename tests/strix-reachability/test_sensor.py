import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class InboundReachability(unittest.TestCase):
    def probe(self, route, reachable):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            marker = root / 'marker'
            marker.write_text('previous episode')
            for name, script in {
                'ip': "#!/bin/sh\nprintf '%s\\n' '" + json.dumps(route) + "'\n",
                'nc': '#!/bin/sh\nexit ' + ('0' if reachable else '1') + '\n',
            }.items():
                path = root / name
                path.write_text(script)
                path.chmod(0o700)
            # The complete Nix sensor, with only its marker redirected into this fixture.
            sensor = Path(os.environ['SENSOR']).read_text().replace(
                '/var/lib/failure-markers/strix-reachability', str(marker))
            result = subprocess.run(['bash', '-euo', 'pipefail', '-c', sensor],
                                    env={**os.environ, 'PATH': str(root) + ':' + os.environ['PATH']},
                                    text=True, capture_output=True, check=True)
            return result.stdout.strip(), marker.exists()

    def test_home_lan_failure_is_observed(self):
        self.assertEqual(self.probe([{'dev': 'wlo1', 'prefsrc': '10.42.0.16'}], False),
                         ('1 strix 1', True))

    def test_tailnet_failure_is_observed(self):
        self.assertEqual(self.probe([{'dev': 'tailscale0', 'prefsrc': '100.100.1.2'}], False),
                         ('1 strix 1', True))

    def test_unrelated_wifi_is_not_a_closet_outage(self):
        self.assertEqual(self.probe([{'dev': 'wlo1', 'prefsrc': '192.168.1.30'}], False),
                         ('0 offline 1', True))

    def test_recovery_clears_only_its_marker(self):
        self.assertEqual(self.probe([{'dev': 'wlo1', 'prefsrc': '10.42.0.16'}], True),
                         ('0 strix 1', False))

if __name__ == '__main__':
    unittest.main()
