"""Run matched local Qwen auditions; write exact argv and timing beside each WAV."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def render(engine, binary, model, codec, text, reference, output, instructions=None):
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.with_suffix(".txt").write_text(text)
    command = [binary, "--model", model, "--codec", codec, "--lang", "English",
               "--seed", "42", "--max-new", "900", "-o", str(output)]
    if reference:
        command += ["--ref-wav", str(reference), "--ref-text", str(reference.with_suffix(".txt"))]
    if instructions:
        command += ["--instruct", instructions]
    environment = dict(os.environ, VK_ICD_FILENAMES="/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json")
    started = time.monotonic()
    with output.with_suffix(".log").open("w") as log:
        result = subprocess.run(command, input=text, text=True, stdout=log, stderr=log,
                                env=environment, timeout=300)
    elapsed = time.monotonic() - started
    receipt = {"engine": engine, "binary": str(Path(binary).resolve()), "argv": command,
               "wall_seconds_including_load": elapsed, "exit_code": result.returncode,
               "text_sha256": hashlib.sha256(text.encode()).hexdigest(),
               "reference": str(reference) if reference else None,
               "reference_sha256": digest(reference) if reference else None,
               "seed": 42, "instructions": instructions}
    if result.returncode == 0 and output.exists():
        # ffprobe handles both PCM and IEEE float WAV output across runtimes.
        probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                "-of", "json", str(output)], capture_output=True, text=True, check=True)
        duration = float(json.loads(probe.stdout)["format"]["duration"])
        receipt.update(audio_seconds=duration, wall_rtf=elapsed / duration, audio_sha256=digest(output))
        logtext = output.with_suffix(".log").read_text()
        match = re.search(r"\[Perf\] Total ([\d.]+) ms.*RTF ([\d.]+)", logtext)
        if match:
            receipt.update(engine_synthesis_seconds=float(match[1]) / 1000, engine_rtf=float(match[2]))
    output.with_suffix(".json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"{output.name}: rc={result.returncode}, wall={elapsed:.2f}s, audio={receipt.get('audio_seconds', 0):.2f}s", flush=True)
    return result.returncode


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", choices=["serveurperso"], required=True)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--codec", required=True)
    parser.add_argument("--root", type=Path, default=Path.home() / "tts-audition-20260914")
    parser.add_argument("--references", nargs="+", default=[
        "intro_6s_raw", "intro_9s_raw", "intro_9s_light", "intro_9s_demucs",
        "probability_9s_raw", "occupation_6s_raw", "diverse_25s_raw"])
    args = parser.parse_args()
    text = (args.root / "comparison.txt").read_text().strip()
    failed = False
    for name in args.references:
        reference = args.root / "k2so/refs" / (name + ".wav")
        output = args.root / "samples" / (f"qwen-{args.engine}-{name}.wav")
        if output.with_suffix(".json").exists():
            continue
        failed |= render(args.engine, args.binary, args.model, args.codec, text, reference, output) != 0
    raise SystemExit(int(failed))
