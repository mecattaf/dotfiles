"""Benchmark a fresh Qwen server, then repeat requests in the same process."""
import argparse
import array
import base64
import hashlib
import http.client
import json
import importlib.util
import os
from pathlib import Path
import subprocess
import time
import wave

from measure import Meter


def request(port, path, body=None):
    connection = http.client.HTTPConnection('127.0.0.1', port, timeout=600)
    connection.request('GET' if body is None else 'POST', path,
                       None if body is None else json.dumps(body), {'Content-Type': 'application/json'})
    response = connection.getresponse()
    if response.status != 200:
        raise RuntimeError(f'HTTP {response.status}: {response.read(4096)!r}')
    return connection, response


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--binary', required=True)
    p.add_argument('--model', required=True)
    p.add_argument('--codec', required=True)
    p.add_argument('--reference', required=True, type=Path)
    p.add_argument('--text', required=True, type=Path)
    p.add_argument('--output', required=True, type=Path)
    p.add_argument('--repeats', type=int, default=3)
    p.add_argument('--chunk-chars', type=int, default=0)
    p.add_argument('--max-new-tokens', type=int, help='Override the per-request audio token cap')
    p.add_argument('--port', type=int, default=18789)
    args = p.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    text = args.text.read_text().strip()
    max_new_tokens = args.max_new_tokens or (2048 if args.chunk_chars else 3500)
    parts = [text]
    if args.chunk_chars:
        spec = importlib.util.spec_from_file_location('speech', Path(__file__).resolve().parents[2] / 'pkgs/qwen-speech/speech.py')
        speech = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(speech)
        parts = [part for part in speech.chunks(text, args.chunk_chars) if part.strip()]
    cmd = [args.binary, '--model', args.model, '--codec', args.codec,
           '--host', '127.0.0.1', '--port', str(args.port), '--lang', 'English', '--max-batch', '1']
    env = dict(os.environ, VK_ICD_FILENAMES='/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json')
    report = {'command': cmd, 'text': text, 'text_characters': len(text),
              'text_sha256': hashlib.sha256(text.encode()).hexdigest(),
              'reference': str(args.reference), 'reference_sha256': hashlib.sha256(args.reference.read_bytes()).hexdigest(),
              'chunk_chars': args.chunk_chars, 'chunks': parts,
              'request_parameters': {'seed': 42, 'response_format': 'pcm', 'max_new_tokens': max_new_tokens},
              'conditions': 'Fresh server process; existing OS file and Vulkan shader caches retained. Same loaded model for all repeats. No synthetic warmup.',
              'runs': []}
    with (args.output / 'server.log').open('w') as log:
        start = time.monotonic()
        with Meter() as loading:
            child = subprocess.Popen(cmd, env=env, stdout=log, stderr=log)
            loading.pid = child.pid
            try:
                while True:
                    if child.poll() is not None or time.monotonic() - start > 120:
                        raise RuntimeError('Server failed to become ready')
                    try:
                        c, r = request(args.port, '/health')
                        r.read(); c.close()
                        break
                    except (OSError, http.client.HTTPException):
                        time.sleep(0.05)
                report['health_seconds'] = time.monotonic() - start
                c, r = request(args.port, '/v1/audio/voices', {
                    'name': 'benchmark', 'ref_text': args.reference.with_suffix('.txt').read_text().strip(),
                    'wav_b64': base64.b64encode(args.reference.read_bytes()).decode()})
                r.read(); c.close()
                report['loaded_and_enrolled_seconds'] = time.monotonic() - start
            except BaseException:
                child.terminate(); child.wait(timeout=15)
                raise
        report['loading_resources'] = loading.report()
        try:
            for i in range(args.repeats):
                target = args.output / f'run-{i+1}.wav'
                target.with_suffix('.txt').write_text(text)
                data, first, first_nonquiet = bytearray(), None, None
                chunk_results = []
                started = time.monotonic()
                with Meter(child.pid) as meter:
                    for part in parts:
                        chunk_started, previous_bytes = time.monotonic(), len(data)
                        c, r = request(args.port, '/v1/audio/speech', {
                            'input': part, 'voice': 'benchmark', 'response_format': 'pcm',
                            'seed': 42, 'max_new_tokens': max_new_tokens})
                        try:
                            if r.getheader('Content-Type', '').split(';')[0] != 'audio/pcm':
                                raise RuntimeError('Expected PCM stream')
                            while True:
                                block = r.read1(4096)
                                if not block:
                                    break
                                now = time.monotonic() - started
                                if first is None:
                                    first = now
                                data.extend(block)
                                if first_nonquiet is None and len(data) >= 2:
                                    pcm = array.array('h', data[:len(data)//2*2])
                                    if max(map(abs, pcm)) >= 300:
                                        first_nonquiet = now
                        except BaseException as error:
                            (args.output / f'run-{i+1}.partial.pcm').write_bytes(data)
                            report['error'] = repr(error)
                            report['partial_audio_seconds'] = len(data) / 48000
                            (args.output / 'benchmark.json').write_text(json.dumps(report, indent=2) + '\n')
                            raise
                        finally:
                            c.close()
                        chunk_results.append({'characters': len(part), 'wall_seconds': time.monotonic() - chunk_started,
                                              'audio_seconds': (len(data) - previous_bytes) / 48000})
                    elapsed = time.monotonic() - started
                if not data or len(data) % 2:
                    raise RuntimeError('Empty or truncated PCM')
                with wave.open(str(target), 'wb') as wav:
                    wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(24000)
                    wav.writeframes(data)
                duration = len(data) / 48000
                run = {'run': i+1, 'wall_seconds': elapsed, 'audio_seconds': duration,
                       'rtf': elapsed / duration, 'first_pcm_seconds': first,
                       'first_nonquiet_pcm_delivery_seconds': first_nonquiet,
                       'first_pcm_including_process_start_seconds': first + report['loaded_and_enrolled_seconds'] if i == 0 else None,
                       'audio_sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
                       'chunks': chunk_results,
                       'resources': meter.report()}
                report['runs'].append(run)
                (args.output / 'benchmark.json').write_text(json.dumps(report, indent=2) + '\n')
                print(json.dumps({k:v for k,v in run.items() if k != 'resources'}), flush=True)
        finally:
            child.terminate()
            try:
                child.wait(timeout=15)
            except subprocess.TimeoutExpired:
                child.kill(); child.wait()


if __name__ == '__main__':
    main()
