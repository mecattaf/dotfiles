import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(os.environ.get(
    "HOME_PRINTING_SCRIPT",
    str(Path(__file__).resolve().parents[2] / "hosts/client/home-printing.sh"),
))
HOME = {
    "GENERAL.CONNECTION": "thomas-6ghz",
    "IP4.GATEWAY": "10.42.0.1",
    "IP4.ADDRESS": "10.42.0.16/24",
    "IP4.DNS": "10.42.0.1",
    "802-11-wireless.ssid": "thomas-6ghz",
}
CLOSED = "flush set inet home_printing wifi_interfaces\n"
OPEN = CLOSED + 'add element inet home_printing wifi_interfaces { "wlo1" }\n'


class HomePrintingWifiTest(unittest.TestCase):
    def run_gate(self, facts, *, fail=False):
        with tempfile.TemporaryDirectory(prefix="home-printing-test-") as tmp:
            tools = Path(tmp)
            nmcli = tools / "nmcli"
            nmcli.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "if os.environ.get('NM_FAIL'): sys.exit(4)\n"
                "print(json.loads(os.environ['NM_FACTS']).get(sys.argv[2], ''))\n"
            )
            nft = tools / "nft"
            nft.write_text(
                f"#!{sys.executable}\n"
                "import sys\n"
                "assert sys.argv[1:] == ['-f', '-']\n"
                "print(sys.stdin.read(), end='')\n"
            )
            nmcli.chmod(0o755)
            nft.chmod(0o755)
            env = dict(os.environ, NM_FACTS=json.dumps(facts))
            env["PATH"] = str(tools) + os.pathsep + env["PATH"]
            if fail:
                env["NM_FAIL"] = "1"
            return subprocess.run(
                ["bash", str(SCRIPT)], env=env, text=True,
                capture_output=True, check=True,
            ).stdout

    def test_nas_managed_home_wifi_allows_only_wifi_interface(self):
        self.assertEqual(self.run_gate(HOME), OPEN)

    def test_other_connections_close_the_gate(self):
        for field, value in (
            ("GENERAL.CONNECTION", "thomas-6ghz-direct"),
            ("GENERAL.CONNECTION", "Freebox-AB3ACE"),
            ("GENERAL.CONNECTION", "hotel"),
            ("802-11-wireless.ssid", "hotel"),
            ("IP4.GATEWAY", "10.42.0.3"),
            ("IP4.ADDRESS", "192.168.1.16/24"),
            ("IP4.DNS", "10.42.0.3"),
        ):
            with self.subTest(field=field, value=value):
                self.assertEqual(self.run_gate(HOME | {field: value}), CLOSED)

    def test_disconnected_or_unavailable_network_manager_closes_gate(self):
        self.assertEqual(self.run_gate({}), CLOSED)
        self.assertEqual(self.run_gate(HOME, fail=True), CLOSED)


if __name__ == "__main__":
    unittest.main()
