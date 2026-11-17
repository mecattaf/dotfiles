"""Paired modes, automatic defaults and direct battery JSON; no live devices."""
import copy
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
route = runpy.run_path(os.environ.get("AUDIO_ROUTE_SCRIPT", str(ROOT / "home/dot_local/bin/audio-route")))
control = runpy.run_path(os.environ.get("AUDIO_CONTROL_SCRIPT", str(ROOT / "home/dot_local/bin/imagine-audio-control")))


def node(identity, media, name, **extra):
    return {"id": identity, "type": "PipeWire:Interface:Node", "info": {"props": {
        "media.class": media, "node.name": name, "alsa.card_name": "sof-hda-dsp", **extra}}}


def graph():
    return [node(1, "Audio/Sink", "alsa_output.pci-test.HiFi__HDMI1__sink"),
            node(2, "Audio/Sink", "alsa_output.pci-test.HiFi__Speaker__sink"),
            node(3, "Audio/Source", "alsa_input.pci-test.HiFi__Mic1__source"),
            node(4, "Audio/Source", "alsa_input.usb-iContact_Camera_Pro_NEW_SERIAL"),
            {"id": 90, "type": "PipeWire:Interface:Device", "info": {"props": {
                "device.alias": "Tom's earbuds", "device.vendor.id": "bluetooth:004c",
                "device.product.id": "0x2014", "api.bluez5.address": "AA:BB:CC:11:22:33"}}},
            node(91, "Audio/Sink", "bluez_output.AA_BB_CC_11_22_33.9", **{
                "device.id": 90, "api.bluez5.codec": "aac", "api.bluez5.profile": "a2dp-sink"}),
            node(92, "Audio/Source", "bluez_input.AA:BB:CC:11:22:33", **{"device.id": 90}),
            {"type": "PipeWire:Interface:Metadata", "props": {"metadata.name": "default"}, "metadata": [
                {"key": "default.audio.sink", "value": {"name": "bluez_output.AA_BB_CC_11_22_33.9"}},
                {"key": "default.audio.source", "value": {"name": "bluez_input.AA:BB:CC:11:22:33"}}]}]


class Routes(unittest.TestCase):
    def test_camera_is_used_for_laptop_mode_and_airpods_use_their_own_mic(self):
        choices = route["discover"](graph())
        self.assertEqual([entry["source"] for entry in choices], [4, 92])
        self.assertEqual(choices[0]["sink"], 2)
        self.assertEqual([entry["selected"] for entry in choices], [False, True])
        self.assertEqual(choices[1]["modelId"], "1420")

    def test_unplugged_camera_falls_back_to_laptop_mic(self):
        current = [n for n in graph() if n.get("id") != 4]
        choices = route["discover"](current)
        self.assertEqual([entry["source"] for entry in choices], [92])
        self.assertTrue(choices[0]["id"].startswith("airpods:"))
        fallback = route["discover"](current, include_fallback=True)
        self.assertEqual(fallback[0]["source"], 3)
        self.assertEqual(fallback[0]["id"], "internal")

    def test_disconnected_airpods_disappear(self):
        choices = route["discover"]([n for n in graph() if n.get("id") != 91])
        self.assertEqual([entry["id"] for entry in choices], ["internal"])

    def test_paired_airpods_remain_available_for_reconnection(self):
        current = [n for n in graph() if n.get("id") != 91]
        paired = [{"address": "11:22:33:44:55:66", "name": "AirPods", "modelId": "1420"}]
        choices = route["discover"](current, paired)
        self.assertEqual(choices[-1]["id"], "airpods:11:22:33:44:55:66")
        self.assertFalse(choices[-1]["connected"])
        self.assertNotIn("sink", choices[-1])

    def test_reconnect_resolves_new_node_ids_and_address(self):
        current = graph()
        current[4]["info"]["props"]["api.bluez5.address"] = "01:23:45:67:89:AB"
        current[5]["id"] = 357
        current[5]["info"]["props"]["node.name"] = "bluez_output.01_23_45_67_89_AB.2"
        entry = route["discover"](current)[1]
        self.assertEqual(entry["id"], "airpods:01:23:45:67:89:AB")
        self.assertEqual(entry["sink"], 357)

    def test_retired_usb_audio_devices_are_not_menu_choices(self):
        current = graph() + [node(500, "Audio/Sink", "alsa_output.usb-Sony_INZONE_Buds-00.iec958-stereo"),
                             node(501, "Audio/Sink", "alsa_output.usb-Sound_Blaster_GS3")]
        self.assertEqual(len(route["discover"](current)), 2)

    def test_empty_internal_fallback_is_not_a_menu_choice(self):
        current = [n for n in graph() if n.get("id") not in (4, 90, 91, 92)]
        self.assertEqual(route["discover"](current), [])
        self.assertEqual(route["discover"](current, include_fallback=True)[0]["source"], 3)

    def test_missing_microphone_never_publishes_incomplete_pair(self):
        self.assertEqual(route["discover"]([n for n in graph() if n.get("id") not in (3, 4, 92)]), [])

    def test_selection_sets_both_current_ids_without_adjusting_volume(self):
        calls = []
        with patch.dict(route["select"].__globals__, run=lambda *args: calls.append(args)):
            route["select"](route["discover"](graph())[1])
        self.assertEqual(calls, [("wpctl", "set-mute", "91", "0"), ("wpctl", "set-mute", "92", "0"),
                                 ("wpctl", "set-default", "91"), ("wpctl", "set-default", "92")])

    def test_laptop_selection_changes_headphone_profile_and_resolves_new_speaker_node(self):
        before = graph()
        before[1]["info"]["props"].update({"node.name": "alsa_output.pci-test.HiFi__Headphones__sink", "device.id": 70})
        before.append({"id": 70, "type": "PipeWire:Interface:Device", "info": {"params": {
            "EnumProfile": [{"index": 9, "name": "HiFi (Speaker, Mic1)", "available": "yes"}]}}})
        entry = route["discover"](before)[0]
        self.assertEqual(entry["profileIndex"], 9)
        after = graph(); after[1]["id"] = 200
        calls = []
        def run(*args, **kwargs):
            calls.append(args)
            return json.dumps(after) if args == ("pw-dump",) else ""
        with patch.dict(route["select"].__globals__, run=run):
            route["select"](entry)
        self.assertEqual(calls[0], ("wpctl", "set-profile", "70", "9"))
        self.assertIn(("wpctl", "set-default", "200"), calls)
        self.assertNotIn(("wpctl", "set-default", "2"), calls)

    def test_connected_signal_before_audio_nodes_waits_without_reconnecting(self):
        calls = []
        def run(*args, **kwargs):
            calls.append(args)
            if args[0] == "bluetoothctl": return "Connected: yes"
            if args[0] == "pw-dump": return json.dumps(graph())
            return ""
        with patch.dict(route["select"].__globals__, run=run):
            route["select"]({"id": "airpods:AA:BB:CC:11:22:33", "connected": False})
        self.assertFalse(any("connect" in args for args in calls))
        self.assertIn(("wpctl", "set-default", "91"), calls)
        self.assertIn(("wpctl", "set-default", "92"), calls)

    def test_failed_bluetooth_connection_never_changes_audio_defaults(self):
        calls = []
        def run(*args, **kwargs):
            calls.append(args)
            return "Connected: no"
        with patch.dict(route["select"].__globals__, run=run):
            with self.assertRaisesRegex(ValueError, "not connected"):
                route["select"]({"id": "airpods:AA:BB:CC:11:22:33", "connected": False})
        self.assertFalse(any(command[0] == "wpctl" for command in calls))


class Battery(unittest.TestCase):
    def readings(self, result, choices=None):
        choices = choices if choices is not None else route["discover"](graph())
        calls = []
        def run(*args, **kwargs):
            calls.append(args)
            if args[0] == "audio-route":
                return json.dumps({"choices": choices})
            if isinstance(result, Exception):
                raise result
            return json.dumps(result)
        with patch.dict(control["battery_readings"].__globals__, run=run):
            return control["battery_readings"](), calls

    def test_model_filter_comes_from_connected_device_not_a_saved_mac(self):
        readings, calls = self.readings({"type": "in_ear", "components": [
            {"name": "left", "battery": 85, "charging": False},
            {"name": "right", "battery": 75, "charging": True}]})
        self.assertEqual(calls[-1], ("podpower", "--address", "AA:BB:CC:11:22:33", "--model-id", "1420"))
        self.assertIn("Left 85%", readings[0]["detail"])
        self.assertIn("Right 75% charging", readings[0]["detail"])
        self.assertIn("Case not reported", readings[0]["detail"])
        self.assertEqual(readings[0]["source"], "device")

    def test_failed_scan_is_unknown_and_does_not_reuse_old_percentages(self):
        readings, _ = self.readings(RuntimeError("AirPods not found"))
        self.assertIn("Waiting for battery", readings[0]["detail"])
        self.assertNotIn("sampledAt", readings[0])

    def test_multiple_pairs_are_queried_by_their_actual_connected_addresses(self):
        choices = route["discover"](graph())
        extra = copy.deepcopy(choices[-1]); extra["id"] = "airpods:12:34:56:78:90:AB"; choices.append(extra)
        readings, calls = self.readings({"type": "in_ear", "components": []}, choices)
        queried = [call[2] for call in calls if call[0] == "podpower"]
        self.assertEqual(queried, ["AA:BB:CC:11:22:33", "12:34:56:78:90:AB"])
        self.assertEqual(len(readings), 2)

    def test_no_connected_airpods_does_not_scan_radio(self):
        readings, calls = self.readings({}, [route["discover"](graph())[0]])
        self.assertEqual(readings, [])
        self.assertEqual(len(calls), 1)

    def test_paired_but_disconnected_airpods_do_not_receive_nearby_battery(self):
        choices = route["discover"](graph())
        choices[-1]["connected"] = False
        readings, calls = self.readings({}, choices)
        self.assertEqual(readings, [])
        self.assertEqual(len(calls), 1)

    def test_unknown_route_never_executes_mutating_command(self):
        calls = []
        def run(*args, **kwargs):
            calls.append(args)
            return json.dumps({"choices": route["discover"](graph())})
        with patch.dict(control["handle"].__globals__, run=run):
            with self.assertRaises(ValueError):
                control["handle"]({"action": "audio-select", "route": "speaker"})
        self.assertEqual(calls, [("audio-route", "list")])


class AutomaticDefaults(unittest.TestCase):
    def apply(self, request, choices=None):
        calls = []
        def run(*args, **kwargs):
            calls.append(args)
            if args == ("audio-route", "list"):
                return json.dumps({"choices": route["discover"](graph()) if choices is None else choices})
            return "Selected pair"
        with patch.dict(control["automatic_route"].__globals__, run=run):
            result = control["automatic_route"](request)
        return result, calls

    def test_airpods_connection_selects_both_and_requests_one_notice(self):
        result, calls = self.apply({"connected": ["AA:BB:CC:11:22:33"]})
        self.assertTrue(result["changed"])
        self.assertEqual(result["notice"], "AirPods connected")
        self.assertEqual(calls[-1], ("audio-route", "airpods:AA:BB:CC:11:22:33"))

    def test_keyboard_and_volume_updates_do_not_change_audio(self):
        result, calls = self.apply({"connected": ["12:34:56:78:90:AB"]})
        self.assertFalse(result["changed"])
        self.assertEqual(calls, [("audio-route", "list")])

    def test_disconnecting_airpods_restores_camera_pair_or_hidden_internal_fallback(self):
        choices = route["discover"](graph())
        choices[-1]["connected"] = False
        result, calls = self.apply({"disconnected": ["AA:BB:CC:11:22:33"]}, choices)
        self.assertTrue(result["changed"])
        self.assertNotIn("notice", result)
        self.assertEqual(calls[-1], ("audio-route", "fallback"))

    def test_initial_empty_state_uses_hidden_internal_fallback(self):
        result, calls = self.apply({"initial": True}, [])
        self.assertTrue(result["changed"])
        self.assertEqual(calls[-1], ("audio-route", "fallback"))


if __name__ == "__main__":
    unittest.main()
