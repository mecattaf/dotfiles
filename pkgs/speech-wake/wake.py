#!/usr/bin/env python3
"""Client wake/capture, coordinator transcription and optional dedicated session dispatch."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import select
import signal
import socket
import struct
import subprocess
import sys
import time
import threading
import wave

MIC = 'alsa_input.usb-DCX-241206-FAY_iContact_Camera_Pro_01.00.00-02.analog-stereo'
FRAME_BYTES = 2560  # 80 ms, mono PCM16 at 16 kHz
WARMUP_FRAMES = 25  # 2 seconds of fresh audio after every reset


def emit(event, **fields):
    print(json.dumps(dict(event=event, monotonic=time.monotonic(), **fields)), flush=True)


def stop(proc):
    if proc is not None:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        for stream in (proc.stdout, proc.stdin, getattr(proc, "stderr", None)):
            if stream is not None:
                stream.close()


class Inhibitors:
    def __init__(self, state):
        self.playback_monitor = None
        self.state = state
        self.wake = state / 'speech-wake'
        self.runtime = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))

    def snapshot(self):
        reasons = [name for name in ('call-record', 'manual-call', 'playback')
                   if (self.wake / name).exists()]
        if self.playback_monitor:
            reason = self.playback_monitor.snapshot_reason()
            if reason: reasons.append(reason)
        dictation_lock = self.runtime / 'speech-dictation.lock'
        if dictation_lock.exists():
            with dictation_lock.open('a') as handle:
                try: fcntl.flock(handle, fcntl.LOCK_SH | fcntl.LOCK_NB)
                except BlockingIOError: reasons.append('held-dictation')
        playback_lock = self.runtime / 'qwen-speech/playback.lock'
        if playback_lock.exists():
            with playback_lock.open('a') as handle:
                try:
                    fcntl.flock(handle, fcntl.LOCK_SH | fcntl.LOCK_NB)
                except BlockingIOError:
                    reasons.append('qwen-playback')
        if (self.state / 'call-record/current').exists():
            reasons.append('legacy-call-record')
        try:
            epoch = (self.wake / 'epoch').read_bytes()
        except FileNotFoundError:
            epoch = b''
        return tuple(reasons), epoch

    def acknowledge(self, epoch):
        self.wake.mkdir(mode=0o700, parents=True, exist_ok=True)
        temp = self.wake / f'ack.{os.getpid()}'
        temp.write_bytes(epoch)
        os.chmod(temp, 0o600)
        temp.replace(self.wake / 'ack')

    def manual(self, active):
        self.wake.mkdir(mode=0o700, parents=True, exist_ok=True)
        with (self.wake / 'manual.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            marker = self.wake / 'manual-call'
            if active:
                marker.touch(mode=0o600)
            temp = self.wake / f'epoch.{os.getpid()}'
            temp.write_text(str(time.time_ns()))
            os.chmod(temp, 0o600)
            temp.replace(self.wake / 'epoch')
            if not active:
                marker.unlink(missing_ok=True)


def microphone(nodes):
    candidates = []
    for node in nodes:
        props = node.get('info', {}).get('props', {})
        if props.get('media.class') == 'Audio/Source' and props.get('node.name') == MIC:
            serial = props.get('object.serial')
            if serial is not None:
                candidates.append(str(serial))
    return candidates[0] if len(candidates) == 1 else None


def find_microphone():
    result = subprocess.run(['pw-dump'], capture_output=True, check=True, timeout=3, stdin=subprocess.DEVNULL)
    return microphone(json.loads(result.stdout))


def capture(serial):
    props = {'node.name': 'speech-wake-capture', 'node.dont-fallback': True,
             'node.dont-reconnect': True, 'node.dont-move': True, 'node.linger': False}
    return subprocess.Popen(['pw-record', '--raw', '--target', serial,
                             '--latency', '20ms', '--rate', '16000', '--channels', '1',
                             '--format', 's16', '--properties', json.dumps(props), '-'],
                            stdout=subprocess.PIPE, stdin=subprocess.DEVNULL)


def load_model(frontend, classifier):
    # No implicit downloads: every filename is explicit and must already be loaned.
    import numpy as np
    from openwakeword.model import Model
    for path in [frontend / 'melspectrogram.onnx', frontend / 'embedding_model.onnx', classifier]:
        if not path.is_file():
            raise FileNotFoundError(f'Missing Library loan: {path}')
    np.random.seed(42)
    model = Model(wakeword_models=[str(classifier)],
                  melspec_model_path=str(frontend / 'melspectrogram.onnx'),
                  embedding_model_path=str(frontend / 'embedding_model.onnx'),
                  inference_framework='onnx', ncpu=1,
                  enable_speex_noise_suppression=False, vad_threshold=0)
    sessions = list(model.models.values()) + [model.preprocessor.melspec_model, model.preprocessor.embedding_model]
    if any(s.get_providers() != ['CPUExecutionProvider'] for s in sessions):
        raise RuntimeError('Expected CPU-only inference')
    return model


class Detector:
    def __init__(self, model, threshold):
        self.model, self.threshold = model, threshold
        self.reset()

    def reset(self):
        self.model.reset()
        self.frames = 0

    def feed(self, pcm):
        import numpy as np
        if len(pcm) != FRAME_BYTES:
            raise ValueError('Expected one complete 80 ms frame')
        scores = self.model.predict(np.frombuffer(pcm, dtype=np.int16))
        self.frames += 1
        return self.frames >= WARMUP_FRAMES and max(scores.values()) >= self.threshold


class StreamingRelay:
    """Send live PCM now, not a second real-time replay after speech ends."""
    def __init__(self, argv=None, framed=None):
        self.framed = (argv is None) if framed is None else framed
        self.process = subprocess.Popen(argv or [
            'ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5',
            'coordinator', 'parakeet-relay', '--framed'], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        os.set_blocking(self.process.stdin.fileno(), False)
        self.pending = bytearray()

    def feed(self, pcm):
        if self.process.poll() is not None:
            raise RuntimeError('Coordinator transcription relay exited during capture')
        if pcm:
            if self.framed: self.pending.extend(struct.pack('<I', len(pcm)))
            self.pending.extend(pcm)
        # At most two seconds of transport backlog. Cancel instead of silently
        # collecting an entire utterance for another real-time playback.
        if len(self.pending) > 64000:
            raise RuntimeError('Coordinator audio transport cannot keep up')
        while self.pending:
            try:
                written = os.write(self.process.stdin.fileno(), self.pending)
            except BlockingIOError:
                break
            del self.pending[:written]

    def finish(self, cancelled, timeout=45):
        deadline = time.monotonic() + timeout
        try:
            if self.framed: self.pending.extend(bytes(4))  # explicit commit; disconnect alone cancels
            while self.pending:
                if cancelled():
                    return None
                if time.monotonic() >= deadline:
                    raise TimeoutError('Audio relay drain timed out')
                self.feed(b'')
                time.sleep(.01)
            self.process.stdin.close()
            self.process.stdin = None
            # Read both streams concurrently with cancellation polls, preventing
            # a verbose SSH error or an unexpectedly long transcript deadlock.
            import threading
            answer = {}
            def collect():
                answer['result'] = self.process.communicate()
            worker = threading.Thread(target=collect, daemon=True)
            worker.start()
            while worker.is_alive():
                if cancelled():
                    return None
                if time.monotonic() >= deadline:
                    raise TimeoutError('Transcription timed out')
                worker.join(.08)
            stdout, stderr = answer['result']
            if self.process.returncode:
                raise RuntimeError('Coordinator transcription failed: ' + stderr.decode(errors='replace')[-1000:])
            return stdout.decode('utf-8').strip()
        finally:
            self.cancel()

    def cancel(self):
        stop(self.process)
        self.pending.clear()


class Command:
    """Bounded RAM capture; standard WebRTC VAD, 0.8-second trailing silence."""
    def __init__(self, vad):
        self.vad = vad
        self.data = bytearray()
        self.speech_frames = 0
        self.quiet_frames = 0

    def feed(self, pcm):
        self.data.extend(pcm)
        voiced = sum(self.vad.is_speech(pcm[i:i + 640], 16000)
                     for i in range(0, len(pcm), 640)) >= 2
        self.speech_frames += int(voiced)
        self.quiet_frames = 0 if voiced else self.quiet_frames + 1
        duration = len(self.data) / 32000
        if duration >= 30:
            return 'limit'
        if self.speech_frames >= 2 and self.quiet_frames >= 10:
            return 'complete'
        if not self.speech_frames and duration >= 8:
            return 'empty'
        return None


def fixture(args, detector, inhibitors):
    with wave.open(str(args.fixture)) as audio:
        if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) != (1, 2, 16000):
            raise ValueError('Fixture must be mono PCM16 16 kHz')
        prior = inhibitors.snapshot()
        frames = events = 0
        while pcm := audio.readframes(1280):
            if len(pcm) != FRAME_BYTES:
                break
            now = inhibitors.snapshot()
            if now != prior:
                detector.reset()
                prior = now
            if now[0]:
                inhibitors.acknowledge(now[1])
            if not now[0] and detector.feed(pcm):
                emit('fixture_wake', input_end_seconds=(frames + 1) * .08,
                     cue='would play only with live capture ready')
                events += 1
                detector.reset()
            frames += 1
        emit('fixture_complete', detections=events, microphone_opened=False, cue_played=False)


def live(args, detector, inhibitors):
    import webrtcvad
    recorder = cue = relay = None
    pending = bytearray()
    command = None
    prior = inhibitors.snapshot()
    state = 'starting'
    next_probe = 0
    serial = None
    last_pcm = 0
    try:
        while True:
            now = inhibitors.snapshot()
            if now != prior or (now[0] and state != 'inhibited'):
                stop(cue); cue = None
                stop(recorder); recorder = None
                if relay: relay.cancel()
                relay = None
                pending.clear(); command = None; detector.reset()
                if state != 'inhibited':
                    emit('inhibited', reasons=now[0])
                state = 'inhibited'; prior = now
                inhibitors.acknowledge(now[1])
            if now[0]:
                time.sleep(.08)
                continue
            if recorder is None:
                if time.monotonic() < next_probe:
                    time.sleep(.08)
                    continue
                next_probe = time.monotonic() + 1
                serial = find_microphone()
                if not serial:
                    if state != 'microphone_missing':
                        emit('microphone_missing', required=MIC)
                    state = 'microphone_missing'
                    continue
                recorder = capture(serial)
                last_pcm = time.monotonic()
                detector.reset(); pending.clear()
                state = 'warming'
                emit('warming', microphone=MIC, serial=serial)
            if recorder.poll() is not None or time.monotonic() - last_pcm > 2:
                stop(recorder); recorder = None
                stop(cue); cue = None
                if relay: relay.cancel()
                relay = None
                pending.clear(); command = None; detector.reset()
                emit('capture_lost'); state = 'capture_lost'
                continue
            if not select.select([recorder.stdout], [], [], .08)[0]:
                continue
            chunk = os.read(recorder.stdout.fileno(), FRAME_BYTES)
            if not chunk:
                stop(recorder); recorder = None
                continue
            last_pcm = time.monotonic()
            pending.extend(chunk)
            if len(pending) < FRAME_BYTES:
                continue
            pcm = bytes(pending[:FRAME_BYTES]); del pending[:FRAME_BYTES]
            # Close the acceptance race: call hooks write inhibition before capture starts.
            if inhibitors.snapshot() != prior:
                continue
            if state == 'cue':
                if cue.poll() is None:
                    continue  # Keep reading/discarding echo; never feed cue back to detector.
                code = cue.returncode; stop(cue); cue = None
                if code:
                    raise RuntimeError('Listening cue failed; command was not admitted')
                relay = StreamingRelay()
                command = Command(webrtcvad.Vad(2))
                state = 'command'
                emit('command_capture')
                continue
            if state == 'command':
                relay.feed(pcm)
                result = command.feed(pcm)
                if not result:
                    continue
                stop(recorder); recorder = None
                pending.clear(); detector.reset()
                if result != 'complete':
                    relay.cancel(); relay = None
                    emit('command_cancelled', reason=result)
                else:
                    endpoint = time.monotonic()
                    emit('transcribing', audio_endpoint_monotonic=endpoint)
                    text = relay.finish(lambda: inhibitors.snapshot() != prior)
                    relay = None
                    if text is not None:
                        emit('transcript', text=text,
                             endpoint_to_transcript_seconds=time.monotonic() - endpoint)
                        if text.strip() and getattr(args, 'dispatch', False) and inhibitors.snapshot() == prior:
                            # Literal stdin, no command interpolation or focused-window typing.
                            # Keep call/playback inhibition responsive while Claude starts.
                            def dispatch(transcript):
                                try:
                                    submitted = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5',
                                                                'coordinator', 'speech-session', '--stdin'],
                                                               input=transcript, text=True, capture_output=True, timeout=100)
                                    emit('session_submitted' if submitted.returncode == 0 else 'session_needs_review',
                                         receipt=submitted.stdout, error=submitted.stderr)
                                except Exception as exc:
                                    emit('session_needs_review', error=str(exc))
                            threading.Thread(target=dispatch, args=(text,), daemon=True).start()

                command = None
                state = 'starting'
                if args.once:
                    return
                continue
            if detector.feed(pcm):
                # Accepted wake, live PCM proven, not inhibited: one cue per turn.
                if inhibitors.snapshot() != prior:
                    continue
                emit('wake_accepted', keyword='Alexa')
                cue = subprocess.Popen(['speech-listening-cue'], stdin=subprocess.DEVNULL)
                state = 'cue'
            elif state == 'warming' and detector.frames >= WARMUP_FRAMES:
                state = 'armed'; emit('armed', keyword='Alexa')
    finally:
        stop(cue); stop(recorder)
        if relay: relay.cancel()
        pending.clear()
        if command:
            command.data.clear()
        detector.reset()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    mode = p.add_mutually_exclusive_group(required=True)
    mode.add_argument('--live', action='store_true', help='Explicitly open only the iContact USB microphone')
    mode.add_argument('--fixture', type=Path, help='Saved-audio check; never opens mic or plays cue')
    mode.add_argument('--call-mode', choices=['on', 'off', 'status'])
    p.add_argument('--once', action='store_true')
    p.add_argument('--dispatch', action='store_true', help='Create a dedicated Claude Opus speech session after transcription')
    p.add_argument('--frontend', type=Path, default=Path('/var/lib/local-models/openwakeword-baker-compat-v051'))
    p.add_argument('--classifier', type=Path, default=Path('/var/lib/local-models/openwakeword-alexa-v051/alexa_v0.1.onnx'))
    p.add_argument('--threshold', type=float, default=.5)
    args = p.parse_args()
    if not 0 < args.threshold <= 1:
        p.error('threshold must be in (0, 1]')
    state = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state')))
    inhibitors = Inhibitors(state)
    if args.call_mode:
        if args.call_mode != 'status':
            inhibitors.manual(args.call_mode == 'on')
        emit('call_mode', reasons=inhibitors.snapshot()[0])
        return
    if args.live:
        if socket.gethostname() != 'client':
            p.error('Live capture is client-only')
        hook = Path.home() / '.local/bin/call-record'
        if not hook.is_file() or hashlib.sha256(hook.read_bytes()).hexdigest() != '@callRecordHash@':
            p.error('Install the matching tested call-record hook before live listening; the current shortcut is not protected by this build')
    lock_dir = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'speech-wake'
    lock_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (lock_dir / 'lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.live:
            from playback import PlaybackMonitor
            inhibitors.playback_monitor = PlaybackMonitor()
        try:
            detector = Detector(load_model(args.frontend, args.classifier), args.threshold)
            if args.fixture:
                fixture(args, detector, inhibitors)
            else:
                signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
                live(args, detector, inhibitors)
        finally:
            if inhibitors.playback_monitor:
                inhibitors.playback_monitor.close()



if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        pass
