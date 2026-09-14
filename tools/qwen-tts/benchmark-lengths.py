"""Bounded one-request size sweep through the guarded deployment Qwen service."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import time
import wave
from measure import Meter


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--text', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('speech', Path(__file__).resolve().parents[2] / 'pkgs/qwen-speech/speech.py')
    speech = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(speech)
    args.output.mkdir(parents=True, exist_ok=True)
    source = args.text.read_text().strip()
    report = {'scope': 'One resident request per increasing text size; complete wording must be independently checked. Uses the guarded deployment service. Existing caches/warmup retained.',
              'max_new_tokens': 2048, 'seed': 42, 'runs': []}
    with speech.lock('synthesis.lock'):
        start = time.monotonic()
        subprocess.run(['systemctl', '--user', 'start', speech.UNIT], check=True, timeout=300)
        report['service_start_seconds'] = time.monotonic() - start
        pid = int(subprocess.check_output(['systemctl', '--user', 'show', speech.UNIT, '-p', 'MainPID', '--value'], text=True))
        for limit in [400, 800, 1200, 1600]:
            text = next(speech.chunks(source, limit)).strip()
            path = args.output / f'limit-{limit}.wav'
            path.with_suffix('.txt').write_text(text+'\n')
            pcm = bytearray()
            run = {'limit_characters': limit, 'actual_characters': len(text), 'text': text, 'output': str(path)}
            started = time.monotonic()
            first = None
            try:
                with Meter(pid) as meter:
                    with speech.request('/v1/audio/speech', {'input': text, 'voice': speech.VOICE,
                                        'response_format': 'pcm', 'seed': 42, 'max_new_tokens': 2048}) as response:
                        if response.getheader('Content-Type', '').split(';')[0] != 'audio/pcm':
                            raise RuntimeError('Expected PCM')
                        while block := response.read1(4096):
                            if first is None:
                                first = time.monotonic()-started
                            pcm.extend(block)
                        if getattr(response, 'length', None) not in (None, 0) or not pcm or len(pcm)%2:
                            raise RuntimeError('Incomplete PCM response')
                    elapsed = time.monotonic()-started
                with wave.open(str(path), 'wb') as wav:
                    wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(24000); wav.writeframes(pcm)
                run.update(status='transport_complete_content_unverified', generation_seconds=elapsed,
                           audio_seconds=len(pcm)/48000, rtf_generation=elapsed/(len(pcm)/48000),
                           first_pcm_seconds=first, pcm_sha256=hashlib.sha256(pcm).hexdigest(), resources=meter.report())
            except Exception as error:
                path.with_suffix('.partial.pcm').write_bytes(pcm)
                run.update(status='failed', error=repr(error), partial_audio_seconds=len(pcm)/48000)
            speech.runtime().joinpath('last-used').touch()
            path.with_suffix('.json').write_text(json.dumps(run, indent=2)+'\n')
            report['runs'].append(run)
            (args.output/'benchmark.json').write_text(json.dumps(report, indent=2)+'\n')
            print(json.dumps({k:v for k,v in run.items() if k not in {'resources','text'}}), flush=True)
            if run['status']=='failed':
                break


if __name__ == '__main__':
    main()
