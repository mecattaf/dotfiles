"""Repeat matched CLI invocations, explicitly retaining no resident model."""
import argparse
import json
import os
from pathlib import Path

from audition import render
from measure import Meter


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--engine', choices=['serveurperso'], required=True)
    p.add_argument('--binary', required=True)
    p.add_argument('--model', required=True)
    p.add_argument('--codec', required=True)
    p.add_argument('--reference', type=Path, required=True)
    p.add_argument('--text', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--repeats', type=int, default=3)
    args = p.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    report = {'engine': args.engine, 'conditions': 'Separate process per invocation; OS/shader caches retained. Each run includes reference encoding. Resources include the small Python harness process.', 'runs': []}
    text = args.text.read_text().strip()
    for i in range(args.repeats):
        path = args.output / f'run-{i+1}.wav'
        if path.exists():
            raise FileExistsError(path)
        with Meter(os.getpid()) as meter:
            code = render(args.engine, args.binary, args.model, args.codec, text, args.reference, path)
        result = json.loads(path.with_suffix('.json').read_text())
        result['resources'] = meter.report()
        path.with_suffix('.json').write_text(json.dumps(result, indent=2) + '\n')
        report['runs'].append(result)
        (args.output / 'benchmark.json').write_text(json.dumps(report, indent=2) + '\n')
        if code:
            raise SystemExit(code)


if __name__ == '__main__':
    main()
