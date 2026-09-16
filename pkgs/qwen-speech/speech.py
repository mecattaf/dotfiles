"""Qwen output: on-demand coordinator synthesis, client PipeWire playback."""

import argparse
import base64
import contextlib
import fcntl
import http.client
import io
import math
import json
import os
from pathlib import Path
import re
import shlex
import signal
import socket
import subprocess
import struct
import sys
import threading
import tempfile
import time
import wave

MAX_TEXT_BYTES = 65536
CHUNK_CHARS = 400
MAX_CHUNK_TOKENS = 512
MAX_CHUNK_PCM_BYTES = MAX_CHUNK_TOKENS * 1920 * 2
VOICE = "assistant-main"
UNIT = "qwen-tts.service"
MIN_AVAILABLE_BYTES = 16 * 1024**3
MAX_DEVICE_GTT_BYTES = 64 * 1024**3
MAX_WAV_BYTES = 8 * 1024**2
MAX_PROFILE_BYTES = 12 * 1024**2
MAX_TRANSCRIPT_BYTES = 32000
SPEAKER_DIM = 2048
RVQ_CODEBOOKS = 16
RVQ_CODE_BITS = 11
RVQ_FRAME_BYTES = RVQ_CODEBOOKS * RVQ_CODE_BITS // 8
MAX_ICL_FRAMES = 375  # 30 seconds at 12.5 Hz (1920 samples/frame at 24 kHz).
MAX_RVQ_FRAMES = 7500  # Bounded ten-minute cache; long codes require empty ref_text.


def memory_pressure():
    """Host headroom matters: Vulkan allocations need not count toward RSS."""
    fields = dict(line.split(":", 1) for line in Path("/proc/meminfo").read_text().splitlines())
    available = int(fields["MemAvailable"].split()[0]) * 1024
    if available < MIN_AVAILABLE_BYTES:
        return "less than 16 GiB system memory available"
    devices = [p for p in Path("/sys/class/drm").glob("card[0-9]*/device/mem_info_gtt_used")
               if (p.parent / "vendor").read_text().strip() == "0x1002"]
    if not devices:
        raise RuntimeError("AMD memory counter unavailable; cannot guard speech inference")
    if any(int(p.read_text()) >= MAX_DEVICE_GTT_BYTES for p in devices):
        return "AMD device GTT reached 64 GiB"
    return None


@contextlib.contextmanager
def memory_guard(child):
    """Stop only our engine under pressure; leave other processes untouched."""
    stopped = threading.Event()

    def watch():
        while not stopped.is_set() and child.poll() is None:
            try:
                reason = memory_pressure()
            except (OSError, ValueError, KeyError, RuntimeError) as error:
                reason = f"memory guard cannot read counters: {error}"
            if reason:
                log(f"stopping Qwen engine: {reason}")
                try:
                    child.kill()
                except ProcessLookupError:
                    pass
                return
            stopped.wait(0.1)

    thread = threading.Thread(target=watch, daemon=True)
    thread.start()
    try:
        yield
    finally:
        stopped.set()
        thread.join(timeout=1)


def log(message):
    print("qwen-speech: " + message, file=sys.stderr, flush=True)


def runtime():
    path = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "qwen-speech"
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    return path


def state():
    return Path(os.environ.get("QWEN_SPEECH_STATE", str(Path.home() / ".local/state/qwen-speech")))


def port():
    return int(os.environ.get("QWEN_SPEECH_PORT", "8733"))


@contextlib.contextmanager
def lock(name):
    with (runtime() / name).open("a+") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("speech is busy; stop the current reading before starting another")
        yield handle


def chunks(text, limit=CHUNK_CHARS):
    """Partition without adding, dropping or rewriting text, including whitespace."""
    while len(text) > limit:
        window = text[:limit]
        ends = list(re.finditer(r"[.!?][\"')]*\s+|\n+", window))
        cut = ends[-1].end() if ends else 0
        if cut < limit // 3:
            spaces = list(re.finditer(r"\s+", window))
            cut = spaces[-1].end() if spaces else limit
        yield text[:cut]
        text = text[cut:]
    if text:
        yield text


def read_text(args):
    if getattr(args, "text", None):
        raw = " ".join(args.text).encode("utf-8")
    elif getattr(args, "file", None):
        with open(args.file, "rb") as source:
            raw = source.read(MAX_TEXT_BYTES + 1)
    else:
        raw = sys.stdin.buffer.read(MAX_TEXT_BYTES + 1)
    if len(raw) > MAX_TEXT_BYTES:
        raise ValueError("text exceeds 64 KiB; split the document")
    text = raw.decode("utf-8")
    if not text.strip() or "\0" in text:
        raise ValueError("expected nonempty UTF-8 text without NUL bytes")
    return text


@contextlib.contextmanager
def request(path, body=None, timeout=180):
    connection = http.client.HTTPConnection("127.0.0.1", port(), timeout=timeout)
    try:
        connection.request("GET" if body is None else "POST", path,
                           body=None if body is None else json.dumps(body).encode(),
                           headers={"Content-Type": "application/json"})
        response = connection.getresponse()
        if response.status != 200:
            detail = response.read(4096).decode(errors="replace")
            raise RuntimeError(f"TTS HTTP {response.status}: {detail}")
        yield response
    finally:
        connection.close()


def wait_ready(child, timeout=180):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if child.poll() is not None:
            raise RuntimeError(f"Qwen engine exited with status {child.returncode}")
        try:
            with request("/health", timeout=1) as response:
                response.read()
            return
        except (OSError, http.client.HTTPException):
            time.sleep(0.2)
    raise RuntimeError("Qwen engine did not become ready within 180 seconds")


def read_bounded(path, limit):
    with open(path, "rb") as source:
        data = source.read(limit + 1)
    if len(data) > limit:
        raise ValueError(f"file exceeds {limit} bytes: {path}")
    return data


def validate_transcript(text, allow_empty=False):
    if not isinstance(text, str) or "\0" in text or len(text) > 8000:
        raise ValueError("reference transcript must be UTF-8 text without NUL, at most 8000 characters")
    if len(text.encode("utf-8")) > MAX_TRANSCRIPT_BYTES:
        raise ValueError("reference transcript exceeds its UTF-8 byte bound")
    text = text.strip()
    if not text and not allow_empty:
        raise ValueError("WAV reference requires a nonempty transcript")
    return text


def validate_wav(audio):
    if not audio or len(audio) > MAX_WAV_BYTES:
        raise ValueError("reference WAV must be nonempty and at most 8 MiB")
    try:
        with wave.open(io.BytesIO(audio), "rb") as wav:
            if (wav.getnchannels(), wav.getframerate(), wav.getsampwidth()) != (1, 24000, 2):
                raise ValueError("reference must be mono 24 kHz signed 16-bit PCM WAV")
            frames = wav.getnframes()
            duration = frames / 24000
            if not 2 <= duration <= 30:
                raise ValueError("reference must contain 2–30 seconds of audio")
            if len(wav.readframes(frames)) != frames * 2:
                raise ValueError("reference WAV contains incomplete PCM")
    except (wave.Error, EOFError) as error:
        raise ValueError(f"invalid reference WAV: {error}") from error
    return duration


def validate_latents(speaker, codes, transcript):
    if len(speaker) != SPEAKER_DIM * 4:
        raise ValueError("speaker must contain exactly 2048 little-endian float32 values")
    values = struct.unpack("<2048f", speaker)
    if not all(math.isfinite(value) for value in values):
        raise ValueError("speaker values must all be finite")
    # Native rvq-file.h: no header, [16,T] row-major, LSB-first packed
    # 11-bit values. Each decoded value is necessarily in 0..2047.
    if not codes or len(codes) % RVQ_FRAME_BYTES:
        raise ValueError("native RVQ must be nonempty, headerless packed 11-bit codes: 22 bytes per frame")
    frames = len(codes) // RVQ_FRAME_BYTES
    if frames > MAX_RVQ_FRAMES:
        raise ValueError("RVQ cache exceeds the ten-minute file bound")
    if transcript and frames > MAX_ICL_FRAMES:
        raise ValueError("reference codes paired with a transcript must cover at most 30 seconds")
    return frames


def decode_profile_field(profile, key, limit):
    value = profile.get(key)
    if not isinstance(value, str) or len(value) > 4 * ((limit + 2) // 3):
        raise ValueError(f"invalid or oversized {key}")
    try:
        data = base64.b64decode(value, validate=True)
    except (ValueError, base64.binascii.Error) as error:
        raise ValueError(f"invalid base64 in {key}") from error
    if len(data) > limit:
        raise ValueError(f"oversized {key}")
    return data


def validate_profile(profile):
    """Return only native Base registration fields, validating before startup."""
    if not isinstance(profile, dict) or profile.get("name") != VOICE:
        raise ValueError("voice profile has an unexpected name")
    wav_fields = {"name", "ref_text", "wav_b64"}
    latent_fields = {"name", "ref_text", "spk_b64", "rvq_b64"}
    if set(profile) == wav_fields:
        transcript = validate_transcript(profile["ref_text"])
        validate_wav(decode_profile_field(profile, "wav_b64", MAX_WAV_BYTES))
    elif set(profile) == latent_fields:
        transcript = validate_transcript(profile["ref_text"], allow_empty=True)
        validate_latents(decode_profile_field(profile, "spk_b64", SPEAKER_DIM * 4),
                         decode_profile_field(profile, "rvq_b64", MAX_RVQ_FRAMES * RVQ_FRAME_BYTES), transcript)
    else:
        raise ValueError("expected one Base WAV or native cached-reference profile with only registration fields")
    return {**profile, "ref_text": transcript}


def atomic_private_write(destination, data):
    fd, name = tempfile.mkstemp(prefix="voice-install-", suffix=".tmp", dir=destination.parent)
    temporary = Path(name)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, destination)
        directory_fd = os.open(destination.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        temporary.unlink(missing_ok=True)


def install_profile(profile):
    # Invalid inputs must not stop the service or change its current profile.
    profile = validate_profile(profile)
    data = json.dumps(profile).encode("utf-8")
    with lock("synthesis.lock"):
        directory = state()
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        directory.chmod(0o700)
        destination = directory / "voice.json"
        if destination.exists():
            previous = read_bounded(destination, MAX_PROFILE_BYTES)
            backup = directory / f"voice-backup-{time.time_ns()}-{os.getpid()}.json"
            atomic_private_write(backup, previous)
        subprocess.run(["systemctl", "--user", "stop", UNIT], check=True)
        atomic_private_write(destination, data)


def enroll(wav_path, transcript_path):
    """Persist a validated WAV reference; extraction happens on engine startup."""
    audio = read_bounded(wav_path, MAX_WAV_BYTES)
    transcript = validate_transcript(read_bounded(transcript_path, MAX_TRANSCRIPT_BYTES).decode("utf-8"))
    duration = validate_wav(audio)
    install_profile({"name": VOICE, "ref_text": transcript,
                     "wav_b64": base64.b64encode(audio).decode("ascii")})
    log(f"saved {VOICE} WAV reference ({duration:.2f}s); it will load on the next request")


def enroll_latents(speaker_path, codes_path, transcript_path):
    """Persist one offline-extracted identity and its native cached reference."""
    speaker = read_bounded(speaker_path, SPEAKER_DIM * 4)
    codes = read_bounded(codes_path, MAX_RVQ_FRAMES * RVQ_FRAME_BYTES)
    transcript = validate_transcript(read_bounded(transcript_path, MAX_TRANSCRIPT_BYTES).decode("utf-8"),
                                     allow_empty=True)
    frames = validate_latents(speaker, codes, transcript)
    install_profile({"name": VOICE, "ref_text": transcript,
                     "spk_b64": base64.b64encode(speaker).decode("ascii"),
                     "rvq_b64": base64.b64encode(codes).decode("ascii")})
    mode = "transcript-conditioned prefix" if transcript else "speaker only; cached codes unused during synthesis"
    log(f"saved {VOICE} native reference ({frames} frames; {mode})")


def terminate(child):
    if child is None or child.poll() is not None:
        return
    child.terminate()
    try:
        child.wait(timeout=5)
    except subprocess.TimeoutExpired:
        child.kill()
        child.wait(timeout=5)


def notify_ready():
    address = os.environ.get("NOTIFY_SOCKET")
    if address:
        if address.startswith("@"):
            address = "\0" + address[1:]
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sock:
            sock.sendto(b"READY=1", address)


def serve(args):
    profile_path = state() / "voice.json"
    if not profile_path.exists():
        profile_path = Path(os.environ.get("QWEN_VOICE_PROFILE", str(profile_path)))
    profile = validate_profile(json.loads(read_bounded(profile_path, MAX_PROFILE_BYTES)))
    for path in [args.model, args.codec]:
        if not Path(path).is_file():
            raise RuntimeError(f"missing loaned model: {path}; run local-models-borrow explicitly")
    pressure = memory_pressure()
    if pressure:
        raise RuntimeError(f"cannot start speech: {pressure}")
    # Child diagnostics go to journald, never onto the relay's PCM stdout.
    child = subprocess.Popen([args.engine, "--model", args.model, "--codec", args.codec,
                              "--host", "127.0.0.1", "--port", str(port()),
                              "--lang", "English", "--max-batch", "1"],
                             stdout=sys.stderr, stderr=sys.stderr)
    marker = runtime() / "last-used"
    with memory_guard(child):
        serve_loaded(args, profile, child, marker)


def serve_loaded(args, profile, child, marker):
    try:
        wait_ready(child)
        with request("/v1/audio/voices", profile) as response:
            response.read()
        # Pay shader setup and model warmup before announcing readiness.
        with request("/v1/audio/speech", {"input": "Ready.", "voice": VOICE,
                     "response_format": "pcm", "seed": 42, "max_new_tokens": 120}) as response:
            while response.read1(4096):
                pass
        marker.touch()
        notify_ready()
        log("ready; Qwen voice loaded")
        while child.poll() is None:
            time.sleep(1)
            if time.time() - marker.stat().st_mtime < args.idle_seconds:
                continue
            try:
                with lock("synthesis.lock"):
                    if time.time() - marker.stat().st_mtime >= args.idle_seconds:
                        # Stop while holding admission lock so a relay cannot
                        # start using a service that has decided to retire.
                        terminate(child)
                        log("idle; released speech model")
                        return
            except RuntimeError:
                pass
        raise RuntimeError(f"Qwen engine exited with status {child.returncode}")
    except KeyboardInterrupt:
        log("stopped")
    finally:
        terminate(child)


def relay(args):
    text = read_text(args)
    with lock("synthesis.lock"):
        marker = runtime() / "last-used"
        marker.touch()
        subprocess.run(["systemctl", "--user", "start", UNIT], check=True, timeout=300)
        started = time.monotonic()
        received = 0
        try:
            for part in chunks(text):
                if not part.strip():
                    continue
                with request("/v1/audio/speech", {"input": part, "voice": VOICE,
                             "response_format": "pcm", "max_new_tokens": MAX_CHUNK_TOKENS}) as response:
                    if response.getheader("Content-Type", "").split(";")[0] != "audio/pcm":
                        raise RuntimeError("engine returned something other than PCM")
                    chunk_bytes = 0
                    while True:
                        block = response.read1(4096)
                        if not block:
                            break
                        if not received:
                            log(f"first PCM after ready: {time.monotonic() - started:.3f}s")
                        received += len(block)
                        chunk_bytes += len(block)
                        if chunk_bytes >= MAX_CHUNK_PCM_BYTES:
                            raise RuntimeError("speech chunk reached the 512-token output cap; reading is incomplete")
                        sys.stdout.buffer.write(block)
                        sys.stdout.buffer.flush()
                    if getattr(response, "length", None) not in (None, 0):
                        raise RuntimeError("engine closed a PCM response before its declared length")
                    if not chunk_bytes or chunk_bytes % 2:
                        raise RuntimeError("engine returned an empty or incomplete PCM chunk")
                marker.touch()
            if not received or received % 2:
                raise RuntimeError("engine returned empty or incomplete PCM")
            elapsed = time.monotonic() - started
            log(f"{received / 48000:.2f}s audio in {elapsed:.2f}s (includes transport backpressure)")
        finally:
            marker.touch()


def ssh(host, command):
    if not re.fullmatch(r"[A-Za-z0-9_.@-]+", host) or host.startswith("-"):
        raise ValueError("invalid SSH host")
    return ["ssh", "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=2",
            host, shlex.join(command)]


def process_start(pid):
    # /proc comm can contain spaces or parentheses; starttime is field 22.
    return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[19]


def stop():
    pidfile = runtime() / "playback.json"
    if not pidfile.exists():
        log("no active playback")
        return
    record = json.loads(pidfile.read_text())
    try:
        if process_start(record["pid"]) == record["start"]:
            os.kill(record["pid"], signal.SIGTERM)
    except (FileNotFoundError, ProcessLookupError):
        pass


def speak(args):
    if args.client:
        command = [args.remote_command, "speak", "--coordinator", args.coordinator,
                   "--remote-command", args.remote_command]
        if args.stop:
            command.append("--stop")
        if args.output:
            raise ValueError("--output records locally; omit --client")
        payload = None if args.stop else read_text(args).encode()
        subprocess.run(ssh(args.client, command), input=payload, check=True)
        return
    if args.stop:
        stop()
        return
    text = read_text(args)
    if not args.output and socket.gethostname() not in ("client", "coordinator"):
        raise RuntimeError("playback requires a physical seat; use --client client or --output FILE.wav")
    with lock("playback.lock"):
        pidfile = runtime() / "playback.json"
        pidfile.write_text(json.dumps({"pid": os.getpid(), "start": process_start(os.getpid())}))
        producer = player = None
        try:
            producer = subprocess.Popen(ssh(args.coordinator, [args.remote_command, "relay"]),
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE)
            producer.stdin.write(text.encode())
            producer.stdin.close()
            if args.output:
                # Keep a failed render as .part, never a success-looking WAV.
                target = Path(args.output)
                temporary = target.with_name(target.name + ".part")
                with wave.open(str(temporary), "wb") as audio:
                    audio.setparams((1, 2, 24000, 0, "NONE", "not compressed"))
                    while True:
                        block = producer.stdout.read(4096)
                        if not block:
                            break
                        audio.writeframesraw(block)
                if producer.wait() != 0:
                    raise RuntimeError("remote synthesis failed; partial audio retained as .part")
                os.replace(temporary, target)
                log(f"wrote {target}")
            else:
                player = subprocess.Popen(["pw-cat", "--playback", "--raw", "--rate=24000",
                                           "--channels=1", "--format=s16", "--latency=100", "-"],
                                          stdin=producer.stdout)
                producer.stdout.close()
                if player.wait() != 0:
                    raise RuntimeError("PipeWire playback failed")
                if producer.wait() != 0:
                    raise RuntimeError("remote synthesis failed")
        finally:
            # Stop the reader first; close SSH next, propagating disconnect
            # through the relay to the engine's cancellation callback.
            terminate(player)
            terminate(producer)
            pidfile.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    play = sub.add_parser("speak")
    play.add_argument("text", nargs="*")
    play.add_argument("--file")
    play.add_argument("--output", help="save a WAV instead of playing")
    play.add_argument("--client", help="forward playback to this client (normally client)")
    play.add_argument("--coordinator", default="coordinator")
    play.add_argument("--remote-command", default="qwen-speech")
    play.add_argument("--stop", action="store_true")
    sub.add_parser("relay")
    service = sub.add_parser("serve")
    service.add_argument("--engine", required=True)
    service.add_argument("--model", required=True)
    service.add_argument("--codec", required=True)
    service.add_argument("--idle-seconds", type=int, default=300)
    enrollment = sub.add_parser("enroll")
    enrollment.add_argument("wav")
    enrollment.add_argument("transcript")
    latents = sub.add_parser("enroll-latents", help="save native offline-extracted .spk and .rvq files")
    latents.add_argument("--speaker", required=True)
    latents.add_argument("--codes", required=True)
    latents.add_argument("--transcript", required=True, help="UTF-8 text file; empty selects speaker-only conditioning")
    args = parser.parse_args()
    if getattr(args, "text", None) and getattr(args, "file", None):
        parser.error("use either text or --file")
    if args.command == "serve":
        serve(args)
    elif args.command == "relay":
        relay(args)
    elif args.command == "enroll":
        enroll(args.wav, args.transcript)
    elif args.command == "enroll-latents":
        enroll_latents(args.speaker, args.codes, args.transcript)
    else:
        speak(args)


def interrupted(_signum, _frame):
    raise KeyboardInterrupt


if __name__ == "__main__":
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, interrupted)
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        # Avoid Python flushing a broken binary stream again at interpreter exit.
        with open(os.devnull, "wb") as null:
            os.dup2(null.fileno(), sys.stdout.fileno())
        sys.exit(130)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError,
            http.client.HTTPException) as error:
        log(str(error))
        sys.exit(1)
