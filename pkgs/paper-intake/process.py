#!/usr/bin/env python3
"""paper-intake — process one scanned paper batch through the local OCR lane.

Tally invokes this as a shell-adapter job with one argument: the job
directory created by paper-intake-collect, containing `scans/page-*.jpg`
as pushed/pulled from the Brother ADS-1800W.

Stages, each recorded in receipt.json (atomic write-then-rename):
  received -> rotated -> transcribed -> done   (or error)

v1 contract:
- Stacks are loaded face-down, top edge first, so every capture arrives
  rotated 180 degrees; the rotate stage applies a constant correction.
- Transcription is the proven full-page qwen3-vl-8b-ocr pass (llama-swap,
  temperature 0, anti-rumination prompt) from the 2026-08-13 feasibility
  eval. Page identification via printed DataMatrix codes, registration
  against rendered originals, and feedback routing arrive in later
  stages; this version delivers faithful per-page transcripts.
"""

import base64
import glob
import json
import os
import subprocess
import sys
import time
import urllib.request

LLAMA_SWAP = os.environ.get("PAPER_INTAKE_ENDPOINT",
                            "http://localhost:9292/v1/chat/completions")
MODEL = os.environ.get("PAPER_INTAKE_MODEL", "qwen3-vl-8b-ocr")

SYSTEM = (
    "You are an OCR engine, not a writing assistant. Task: read the image and "
    "output the exact transcription of the HANDWRITTEN text only, as plain "
    "text. Ignore printed/typeset text entirely. Do NOT explain what you are "
    "doing. Do NOT think step-by-step. Do NOT correct spelling or grammar. "
    "If you notice yourself repeating a word or phrase, immediately stop and "
    "output your best single transcription. If there is no handwriting, "
    "output exactly: [no handwriting]"
)

PROMPT = (
    "Transcribe every piece of handwritten text on this page. For each, give "
    "the nearest printed heading or label (e.g. the decision number) so the "
    "handwriting can be located, then the verbatim transcription."
)


def write_receipt(job, state, extra=None):
    receipt = {"job": job, "state": state, "updated": int(time.time())}
    if extra:
        receipt.update(extra)
    tmp = os.path.join(job, ".receipt.tmp")
    with open(tmp, "w") as f:
        json.dump(receipt, f, indent=2)
        f.write("\n")
    os.replace(tmp, os.path.join(job, "receipt.json"))


def transcribe(image_path):
    with open(image_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    payload = {
        "model": MODEL,
        "temperature": 0,
        "max_tokens": 2048,
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": [
                {"type": "image_url",
                 "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
                {"type": "text", "text": PROMPT},
            ]},
        ],
    }
    req = urllib.request.Request(
        LLAMA_SWAP, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=600) as resp:
        out = json.load(resp)
    choice = out["choices"][0]
    if choice.get("finish_reason") == "length":
        raise RuntimeError(f"truncated transcription for {image_path}")
    return {
        "image": os.path.basename(image_path),
        "seconds": round(time.time() - t0, 1),
        "text": choice["message"]["content"],
    }


def main():
    if len(sys.argv) != 2:
        print("usage: paper-intake JOB_DIR", file=sys.stderr)
        return 2
    job = os.path.abspath(sys.argv[1])
    scans = sorted(glob.glob(os.path.join(job, "scans", "page-*.jpg")))
    if not scans:
        print(f"paper-intake: no scans in {job}/scans", file=sys.stderr)
        write_receipt(job, "error", {"error": "no scans"})
        return 1
    write_receipt(job, "received", {"pages": len(scans)})

    rotated_dir = os.path.join(job, "rotated")
    os.makedirs(rotated_dir, exist_ok=True)
    for src in scans:
        dst = os.path.join(rotated_dir, os.path.basename(src))
        subprocess.run(["magick", src, "-rotate", "180", dst], check=True)
    write_receipt(job, "rotated", {"pages": len(scans)})

    jsonl = os.path.join(job, "ocr-8b.jsonl")
    results = []
    with open(jsonl, "w") as f:
        for img in sorted(glob.glob(os.path.join(rotated_dir, "page-*.jpg"))):
            r = transcribe(img)
            results.append(r)
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
            f.flush()
    write_receipt(job, "transcribed", {"pages": len(results)})

    with open(os.path.join(job, "transcripts.md"), "w") as f:
        f.write(f"# Scanned batch {os.path.basename(job)}\n")
        for r in results:
            f.write(f"\n## {r['image']}\n\n{r['text']}\n")
    write_receipt(job, "done", {"pages": len(results)})
    print(f"paper-intake: {len(results)} pages -> {job}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
