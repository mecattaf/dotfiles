"""Exercise routing/DNS failure policy without touching the real network."""
import contextlib
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / "hosts/coordinator/uplink.py"
spec = importlib.util.spec_from_file_location("uplink", SOURCE)
uplink = importlib.util.module_from_spec(spec)
spec.loader.exec_module(uplink)


class Policy(unittest.TestCase):
    def run_tick(self, state, tier="nas", healthy=None, active=None):
        healthy = healthy or {}
        with patch.object(uplink, "active", return_value=active or uplink.PRIMARY), \
             patch.object(uplink, "current_tier", return_value=tier), \
             patch.object(uplink, "probe", side_effect=lambda path: healthy.get(path, False)), \
             patch.object(uplink, "apply_tier") as apply, \
             patch.object(uplink, "switch_freebox") as freebox:
            result = uplink.tick(state)
            return result, apply.call_args_list, freebox.call_count

    def test_midday_activation_is_not_a_boot_return(self):
        with patch.object(uplink.Path, "read_text", return_value="18000.1 99.0"):
            self.assertFalse(uplink.boot_window())
        with patch.object(uplink.Path, "read_text", return_value="121.0 99.0"):
            self.assertTrue(uplink.boot_window())

    def test_transient_failure_keeps_connection(self):
        state, changes, radio = self.run_tick({})
        self.assertEqual(state, {"tier": "nas", "failures": 1})
        self.assertEqual((changes, radio), ([], 0))

    def test_nas_failure_uses_be550_without_radio_switch(self):
        state, changes, radio = self.run_tick({"tier": "nas", "failures": 2}, healthy={"be550": True})
        self.assertEqual(state, {})
        self.assertEqual(changes[0].args, ("be550",))
        self.assertEqual(radio, 0)

    def test_missing_be550_uses_freebox(self):
        state, changes, radio = self.run_tick({"tier": "nas", "failures": 2})
        self.assertEqual((state, changes, radio), ({}, [], 1))

    def test_failed_bypass_uses_freebox(self):
        _, changes, radio = self.run_tick({"tier": "be550", "failures": 2}, tier="be550")
        self.assertEqual((changes, radio), ([], 1))

    def test_manual_freebox_is_untouched(self):
        self.assertEqual(self.run_tick({"tier": "nas", "failures": 2}, active=uplink.FREEBOX), ({}, [], 0))

    def test_healthy_bypass_does_not_return_during_day(self):
        self.assertEqual(self.run_tick({}, tier="be550", healthy={"nas": True, "be550": True}), ({}, [], 0))

    def test_recovery_resets_failure_counter(self):
        self.assertEqual(self.run_tick({"tier": "nas", "failures": 2}, healthy={"nas": True}), ({}, [], 0))

    def test_nas_dns_only_failure_is_unhealthy(self):
        with patch.object(uplink, "command", return_value=subprocess.CompletedProcess([], 0)), \
             patch.object(uplink, "dns_alive", return_value=False):
            self.assertFalse(uplink.probe("nas"))

    def test_missing_internal_dns_is_unhealthy(self):
        with patch.object(uplink, "command", return_value=subprocess.CompletedProcess([], 0)), \
             patch.object(uplink, "dns_alive", side_effect=[True, False]):
            self.assertFalse(uplink.probe("nas"))

    def test_each_path_uses_its_own_mark(self):
        with patch.object(uplink, "command", return_value=subprocess.CompletedProcess([], 0)) as cmd, \
             patch.object(uplink, "dns_alive", return_value=True) as dns:
            self.assertTrue(uplink.probe("nas"))
            self.assertIn("42001", cmd.call_args.args)
            self.assertEqual(dns.call_args.args, ("10.42.0.1", 42001, "photos.internal"))
            self.assertTrue(uplink.probe("be550"))
            self.assertIn("42003", cmd.call_args.args)
            self.assertEqual(dns.call_args.args, ("1.1.1.1", 42003))

    def test_runtime_changes_do_not_modify_saved_profile(self):
        with patch.object(uplink, "active", return_value=uplink.PRIMARY), patch.object(uplink, "command") as cmd:
            uplink.apply_tier("be550")
            self.assertEqual(cmd.call_args.args[:4], ("nmcli", "device", "modify", uplink.DEVICE))
            self.assertIn("10.42.0.3", cmd.call_args.args)
            self.assertIn("1.1.1.1,9.9.9.9", cmd.call_args.args)

    def test_manual_change_during_probe_wins(self):
        with patch.object(uplink, "active", return_value=uplink.FREEBOX), patch.object(uplink, "command") as cmd:
            self.assertFalse(uplink.apply_tier("nas"))
            uplink.switch_freebox()
            cmd.assert_not_called()

    def test_controlled_return_probes_primary_before_restoring(self):
        with patch.object(uplink, "active", return_value=uplink.PRIMARY), \
             patch.object(uplink, "probe_routes", return_value=contextlib.nullcontext()), \
             patch.object(uplink, "probe", return_value=True) as probe, \
             patch.object(uplink, "apply_tier") as apply:
            uplink.controlled_return()
            probe.assert_called_once_with("nas")
            apply.assert_called_once_with("nas")

    def test_controlled_return_keeps_bypass_if_nas_still_broken(self):
        with patch.object(uplink, "active", return_value=uplink.PRIMARY), \
             patch.object(uplink, "probe_routes", return_value=contextlib.nullcontext()), \
             patch.object(uplink, "probe", side_effect=[False, True]), \
             patch.object(uplink, "apply_tier") as apply:
            uplink.controlled_return()
            apply.assert_called_once_with("be550")

    def test_failed_controlled_return_restores_freebox(self):
        with patch.object(uplink, "active", side_effect=[uplink.FREEBOX, uplink.PRIMARY, uplink.PRIMARY]), \
             patch.object(uplink, "command", return_value=subprocess.CompletedProcess([], 0, stdout=uplink.PRIMARY)), \
             patch.object(uplink, "probe_routes", return_value=contextlib.nullcontext()), \
             patch.object(uplink, "probe", return_value=False), \
             patch.object(uplink, "switch_freebox") as freebox, patch.object(uplink.time, "sleep"):
            uplink.controlled_return()
            freebox.assert_called_once()

    def run_boot(self, uptime, active):
        with tempfile.TemporaryDirectory() as state, \
             patch.object(uplink, "STATE", Path(state)), \
             patch.object(uplink.sys, "argv", ["uplink.py", "boot"]), \
             patch.object(uplink, "boot_window", return_value=uptime <= 300), \
             patch.object(uplink, "active", return_value=active), \
             patch.object(uplink, "controlled_return") as returned, \
             patch.object(uplink, "save_state") as saved:
            uplink.main()
            return returned.call_count, saved.call_count

    def test_boot_repeat_is_a_noop_once_primary_is_up(self):
        # Polled every 20 s, so it must not re-probe or reset the watchdog counter.
        self.assertEqual(self.run_boot(40, uplink.PRIMARY), (0, 0))

    def test_boot_retries_the_return_while_on_freebox(self):
        self.assertEqual(self.run_boot(40, uplink.FREEBOX), (1, 1))

    def test_boot_outside_window_leaves_freebox_alone(self):
        self.assertEqual(self.run_boot(400, uplink.FREEBOX), (0, 0))

    def test_probe_rules_include_terminal_route_and_cleanup(self):
        with patch.object(uplink, "command") as cmd:
            with uplink.probe_routes():
                pass
            commands = [call.args for call in cmd.call_args_list]
            self.assertTrue(any("unreachable" in call for call in commands))
            self.assertTrue(any("10.42.0.0/24" in call and "src" in call for call in commands))
            self.assertEqual(sum(call[2:4] == ("rule", "del") for call in commands), 4)


if __name__ == "__main__":
    unittest.main()
