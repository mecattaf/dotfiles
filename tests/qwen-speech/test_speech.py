import contextlib
import base64
import http.server
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import threading
import subprocess
import sys
import struct
import wave
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location(
    "speech", Path(__file__).resolve().parents[2] / "pkgs/qwen-speech/speech.py"
)
speech = importlib.util.module_from_spec(spec)
spec.loader.exec_module(speech)


class SpeechTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.env = patch.dict(os.environ, {"XDG_RUNTIME_DIR": self.tmp.name,
                                          "QWEN_SPEECH_STATE": str(Path(self.tmp.name) / "state")})
        self.env.start()
        self.addCleanup(self.env.stop)
        speech.state().mkdir()

    def wav_bytes(self, seconds=2):
        data = io.BytesIO()
        with wave.open(data, "wb") as wav:
            wav.setparams((1, 2, 24000, 0, "NONE", "not compressed"))
            wav.writeframes(b"\0\0" * int(seconds * 24000))
        return data.getvalue()

    def latent_files(self, frames=100, text="A matching reference."):
        speaker = Path(self.tmp.name) / "reference.spk"
        speaker.write_bytes(struct.pack("<2048f", *([0.25] * 2048)))
        codes = Path(self.tmp.name) / "reference.rvq"
        codes.write_bytes(b"\xff" * (22 * frames))  # All codes are 2047.
        transcript = Path(self.tmp.name) / "reference.txt"
        transcript.write_text(text)
        return speaker, codes, transcript

    def test_legacy_wav_profile_is_validated_and_keeps_exact_api_schema(self):
        profile = {"name": speech.VOICE, "ref_text": "A matching reference.",
                   "wav_b64": base64.b64encode(self.wav_bytes()).decode()}
        self.assertEqual(speech.validate_profile(profile), profile)
        with self.assertRaisesRegex(ValueError, "only registration fields"):
            speech.validate_profile({**profile, "unknown_metadata": "not an API field"})
        profile["wav_b64"] = base64.b64encode(self.wav_bytes()[:-2]).decode()
        with self.assertRaisesRegex(ValueError, "incomplete PCM"):
            speech.validate_profile(profile)

    def test_native_latents_install_privately_and_preserve_exact_previous_profile(self):
        previous = b'{ "name" : "assistant-main", "legacy": "unchanged bytes" }\n'
        destination = speech.state() / "voice.json"
        destination.write_bytes(previous)
        files = self.latent_files()
        with patch.object(speech.subprocess, "run") as run:
            speech.enroll_latents(*files)
        run.assert_called_once_with(["systemctl", "--user", "stop", speech.UNIT], check=True)
        profile = json.loads(destination.read_text())
        self.assertEqual(set(profile), {"name", "ref_text", "spk_b64", "rvq_b64"})
        self.assertEqual(base64.b64decode(profile["spk_b64"]), files[0].read_bytes())
        self.assertEqual(base64.b64decode(profile["rvq_b64"]), files[1].read_bytes())
        self.assertEqual(profile["ref_text"], files[2].read_text())
        backups = list(speech.state().glob("voice-backup-*.json"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), previous)
        for path in (destination, backups[0]):
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(speech.state().stat().st_mode & 0o777, 0o700)

    def test_cached_reference_rejects_bad_speaker_and_rvq_before_service_stop(self):
        speaker, codes, transcript = self.latent_files()
        valid = speaker.read_bytes()
        invalid_speakers = [valid[:-4], valid + b"\0\0\0\0", struct.pack("<f", float("nan")) + valid[4:],
                            struct.pack("<f", float("inf")) + valid[4:]]
        for data in invalid_speakers:
            speaker.write_bytes(data)
            with self.subTest(bytes=len(data)), patch.object(speech.subprocess, "run") as run:
                with self.assertRaises(ValueError):
                    speech.enroll_latents(speaker, codes, transcript)
                run.assert_not_called()
        speaker.write_bytes(valid)
        for data in (b"", b"x" * 21, b"x" * 23, b"x" * (speech.MAX_RVQ_FRAMES * 22 + 1)):
            codes.write_bytes(data)
            with self.subTest(bytes=len(data)), patch.object(speech.subprocess, "run") as run:
                with self.assertRaises(ValueError):
                    speech.enroll_latents(speaker, codes, transcript)
                run.assert_not_called()
        self.assertFalse((speech.state() / "voice.json").exists())

    def test_icl_prefix_boundary_and_long_speaker_only_cache(self):
        speaker = struct.pack("<2048f", *([0.25] * 2048))
        self.assertEqual(speech.validate_latents(speaker, b"\0" * 22 * 375, "Reference."), 375)
        with self.assertRaisesRegex(ValueError, "30 seconds"):
            speech.validate_latents(speaker, b"\0" * 22 * 376, "Reference.")
        files = self.latent_files(frames=928, text="  \n")
        with patch.object(speech.subprocess, "run"):
            speech.enroll_latents(*files)
        profile = json.loads((speech.state() / "voice.json").read_text())
        self.assertEqual(profile["ref_text"], "")
        self.assertEqual(speech.validate_profile(profile), profile)

    def test_invalid_transcript_never_changes_profile(self):
        files = self.latent_files()
        destination = speech.state() / "voice.json"
        destination.write_bytes(b"old profile")
        for raw in (b"bad\0text", b"\xff", b"a" * 8001, b"a" * 32001):
            files[2].write_bytes(raw)
            with self.subTest(raw_size=len(raw)), patch.object(speech.subprocess, "run") as run:
                with self.assertRaises(ValueError):
                    speech.enroll_latents(*files)
                run.assert_not_called()
            self.assertEqual(destination.read_bytes(), b"old profile")
        self.assertFalse(list(speech.state().glob("voice-backup-*")))

    def test_invalid_profile_fails_before_starting_engine(self):
        (speech.state() / "voice.json").write_text(json.dumps({"name": speech.VOICE, "ref_text": "", "spk_b64": "bad", "rvq_b64": "AAAA"}))
        with patch.object(speech.subprocess, "Popen") as popen:
            with self.assertRaises(ValueError):
                speech.serve(SimpleNamespace())
        popen.assert_not_called()

    def test_legacy_wav_enrollment_still_works_and_retains_backup(self):
        wav = Path(self.tmp.name) / "ref.wav"; wav.write_bytes(self.wav_bytes())
        text = Path(self.tmp.name) / "ref.txt"; text.write_text("Matching words.\n")
        old = speech.state() / "voice.json"; old.write_bytes(b"old reference")
        with patch.object(speech.subprocess, "run"):
            speech.enroll(wav, text)
        self.assertEqual(json.loads(old.read_text())["ref_text"], "Matching words.")
        self.assertEqual(next(speech.state().glob("voice-backup-*.json")).read_bytes(), b"old reference")

    def test_failed_atomic_install_preserves_old_profile_and_removes_temporary_files(self):
        destination = speech.state() / "voice.json"; destination.write_bytes(b"previous")
        replace = speech.os.replace
        def fail_only_profile(source, target):
            if Path(target) == destination:
                raise OSError("disk error")
            return replace(source, target)
        with patch.object(speech.subprocess, "run"), patch.object(speech.os, "replace", side_effect=fail_only_profile):
            with self.assertRaisesRegex(OSError, "disk error"):
                speech.enroll_latents(*self.latent_files())
        self.assertEqual(destination.read_bytes(), b"previous")
        self.assertEqual(next(speech.state().glob("voice-backup-*.json")).read_bytes(), b"previous")
        self.assertFalse(list(speech.state().glob("voice-install-*")))

    def test_serving_cached_profile_only_uploads_native_fields_without_extraction(self):
        speaker, codes, transcript = self.latent_files()
        profile = {"name": speech.VOICE, "ref_text": transcript.read_text(),
                   "spk_b64": base64.b64encode(speaker.read_bytes()).decode(),
                   "rvq_b64": base64.b64encode(codes.read_bytes()).decode()}
        calls = []
        @contextlib.contextmanager
        def request(path, body=None):
            calls.append((path, body))
            yield io.BytesIO(b"\0\0")
        child = Mock(); child.poll.return_value = None
        with patch.object(speech, "request", request), patch.object(speech, "wait_ready"), \
                patch.object(speech, "notify_ready"), patch.object(speech.time, "sleep"), \
                patch.object(speech, "terminate"):
            speech.serve_loaded(SimpleNamespace(idle_seconds=0), profile, child, speech.runtime() / "last-used")
        self.assertEqual(calls[0], ("/v1/audio/voices", profile))
        self.assertEqual(calls[1][1]["voice"], speech.VOICE)
        self.assertNotIn("instructions", calls[1][1])

    def test_cli_cached_enrollment_passes_only_explicit_native_paths(self):
        with patch.object(sys, "argv", ["qwen-speech", "enroll-latents", "--speaker", "a.spk", "--codes", "b.rvq", "--transcript", "c.txt"]), \
                patch.object(speech, "enroll_latents") as enroll:
            speech.main()
        enroll.assert_called_once_with("a.spk", "b.rvq", "c.txt")

    def test_output_cap_fails_reading_closes_request_and_releases_lock(self):
        calls, closed = [], []
        class Response(io.BytesIO):
            def getheader(self, *args):
                return "audio/pcm"
        @contextlib.contextmanager
        def request(path, body):
            calls.append(body)
            try:
                yield Response(b"\0" * speech.MAX_CHUNK_PCM_BYTES)
            finally:
                closed.append(True)
        output = io.BytesIO()
        with patch.object(speech, "read_text", return_value="One short sentence."), \
                patch.object(speech.subprocess, "run"), patch.object(speech, "request", request), \
                patch.object(speech.sys, "stdout", SimpleNamespace(buffer=output)):
            with self.assertRaisesRegex(RuntimeError, "512-token output cap"):
                speech.relay(object())
        self.assertEqual(calls[0]["max_new_tokens"], 512)
        self.assertEqual(closed, [True])
        self.assertLess(len(output.getvalue()), speech.MAX_CHUNK_PCM_BYTES)
        with speech.lock("synthesis.lock"):
            pass

    def test_failed_wav_render_does_not_replace_previous_recording(self):
        target = Path(self.tmp.name) / "saved.wav"; target.write_bytes(b"previous successful recording")
        producer = Mock(stdin=io.BytesIO(), stdout=io.BytesIO(b"\0\0" * 100))
        producer.wait.return_value = 1; producer.poll.return_value = 1
        args = SimpleNamespace(client=None, remote_command="qwen-speech", coordinator="coordinator", stop=False, output=str(target))
        with patch.object(speech, "read_text", return_value="Exact text, Tom."), \
                patch.object(speech.subprocess, "Popen", return_value=producer):
            with self.assertRaisesRegex(RuntimeError, "partial audio retained"):
                speech.speak(args)
        self.assertEqual(target.read_bytes(), b"previous successful recording")
        self.assertTrue(target.with_name(target.name + ".part").exists())

    def test_chunking_preserves_every_character(self):
        text = ('“Hello, sir.”\n\nA short pause. ' + 'éclair ' * 100 + 'last word!\n') * 4
        parts = list(speech.chunks(text))
        self.assertEqual("".join(parts), text)
        self.assertTrue(all(0 < len(part) <= speech.CHUNK_CHARS for part in parts))

    def test_unbroken_long_input_is_bounded(self):
        text = "x" * 3000
        self.assertEqual("".join(speech.chunks(text)), text)
        self.assertTrue(all(len(part) <= 400 for part in speech.chunks(text)))

    def test_second_request_fails_without_queueing(self):
        with speech.lock("synthesis.lock"):
            with self.assertRaisesRegex(RuntimeError, "busy"):
                with speech.lock("synthesis.lock"):
                    self.fail("second request entered")
        with speech.lock("synthesis.lock"):
            pass

    def test_remote_arguments_cannot_be_shell_commands(self):
        with self.assertRaises(ValueError):
            speech.ssh("client;touch /tmp/bad", ["speak"])
        with self.assertRaises(ValueError):
            speech.ssh("-oProxyCommand=bad", ["speak"])
        command = speech.ssh("client", ["speak", "$(touch /tmp/bad)"])
        self.assertIn("'$(touch /tmp/bad)'", command[-1])

    def test_empty_invalid_and_oversized_inputs_fail(self):
        args = type("Args", (), {})()
        for raw in (b"  ", b"bad\0text", b"\xff", b"x" * 65537):
            with patch.object(speech.sys, "stdin", type("In", (), {"buffer": io.BytesIO(raw)})()):
                with self.assertRaises(ValueError):
                    speech.read_text(args)

    def test_stale_pid_is_not_signalled(self):
        (speech.runtime() / "playback.json").write_text(json.dumps({"pid": 1234, "start": "old"}))
        with patch.object(speech, "process_start", return_value="new"), patch.object(speech.os, "kill") as kill:
            speech.stop()
            kill.assert_not_called()

    def test_memory_guard_stops_own_engine_on_pressure(self):
        with subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"]) as child:
            with patch.object(speech, "memory_pressure", return_value="low memory"):
                with speech.memory_guard(child):
                    self.assertNotEqual(child.wait(timeout=3), 0)

    def test_memory_guard_fails_closed_if_counter_disappears(self):
        with subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"]) as child:
            with patch.object(speech, "memory_pressure", side_effect=OSError("counter disappeared")):
                with speech.memory_guard(child):
                    self.assertNotEqual(child.wait(timeout=3), 0)

    def test_memory_guard_leaves_healthy_engine_running(self):
        with subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"]) as child:
            try:
                with patch.object(speech, "memory_pressure", return_value=None):
                    with speech.memory_guard(child):
                        self.assertIsNone(child.poll())
                self.assertIsNone(child.poll())
            finally:
                child.terminate()
                child.wait(timeout=3)

    def test_http_error_is_not_audio(self):
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                self.send_response(503)
                self.end_headers()
                self.wfile.write(b'{"error":"out of memory"}')

            def log_message(self, *args):
                pass

        with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                with patch.object(speech, "port", return_value=server.server_port):
                    with self.assertRaisesRegex(RuntimeError, "503.*out of memory"):
                        with speech.request("/v1/audio/speech", {"input": "test"}):
                            self.fail("HTTP error treated as success")
            finally:
                server.shutdown()
                thread.join()

    def test_early_closed_audio_response_fails_the_reading(self):
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                self.send_response(200)
                self.send_header("Content-Type", "audio/pcm")
                self.send_header("Content-Length", "1000")
                self.end_headers()
                self.wfile.write(b"\0" * 100)
                self.close_connection = True

            def log_message(self, *args):
                pass

        with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                with patch.object(speech, "port", return_value=server.server_port), \
                        patch.object(speech, "read_text", return_value="Hello."), \
                        patch.object(speech.subprocess, "run"), \
                        patch.object(speech.sys, "stdout", type("Out", (), {"buffer": io.BytesIO()})()):
                    with self.assertRaisesRegex(RuntimeError, "declared length"):
                        speech.relay(object())
                with speech.lock("synthesis.lock"):
                    pass
            finally:
                server.shutdown()
                thread.join()

    def test_playback_break_closes_response_and_releases_admission(self):
        class Response:
            def getheader(self, *args):
                return "audio/pcm"

            def read1(self, size):
                return b"\0\0" * 100

        closed = []

        @contextlib.contextmanager
        def request(*args, **kwargs):
            try:
                yield Response()
            finally:
                closed.append(True)

        class BrokenOutput:
            def write(self, data):
                raise BrokenPipeError

        with patch.object(speech, "read_text", return_value="Hello."), \
                patch.object(speech.subprocess, "run"), \
                patch.object(speech, "request", request), \
                patch.object(speech.sys, "stdout", type("Out", (), {"buffer": BrokenOutput()})()):
            with self.assertRaises(BrokenPipeError):
                speech.relay(object())
        self.assertEqual(closed, [True])
        with speech.lock("synthesis.lock"):
            pass


if __name__ == "__main__":
    unittest.main()
