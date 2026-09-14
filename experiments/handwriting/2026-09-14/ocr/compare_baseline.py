#!/usr/bin/env python3
"""Report pairwise transcript disagreement, never ground-truth accuracy.

Usage: python3 compare_baseline.py RUN_DIRECTORY
"""
import difflib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def distance(left, right):
    previous = list(range(len(right) + 1))
    for i, a in enumerate(left, 1):
        row = [i]
        for j, b in enumerate(right, 1):
            row.append(min(row[-1] + 1, previous[j] + 1, previous[j-1] + (a != b)))
        previous = row
    return previous[-1]


def words(value):
    return re.findall(r"\w+(?:['’]\w+)*", value.casefold())


def transcription(answer):
    match = re.search(r"(?ms)^TRANSCRIPTION:\s*\n(.*?)^UNCERTAINTIES:", answer)
    if not match:
        raise ValueError("Missing expected transcription section; inspect raw output")
    return match.group(1).strip()


def main():
    run = Path(sys.argv[1]).resolve()
    astra = json.loads((ROOT / "runs/codex-initial.json").read_text())
    claude = {p["id"]: "\n".join(p["lines"]) for p in json.loads((ROOT / "runs/claude-transcription.json").read_text())["pages"]}
    records = []
    for page in astra["pages"]:
        pid = page["id"]
        metadata = json.loads((run / f"{pid}-metadata.json").read_text())
        if not metadata["complete"]:
            raise ValueError(f"Incomplete answer: {pid}")
        halogen = transcription((run / f"{pid}-answer.txt").read_text())
        reference = "\n".join(r["candidate"] for r in page["regions"])
        ref_chars = " ".join(reference.split())
        hyp_chars = " ".join(halogen.split())
        a, b = words(reference), words(halogen)
        diff = []
        for tag, i, j, k, l in difflib.SequenceMatcher(a=a, b=b, autojunk=False).get_opcodes():
            if tag != "equal":
                diff.append({"operation": tag, "astra": " ".join(a[i:j]), "halogen": " ".join(b[k:l])})
        records.append({"page_id": pid, "astra": reference, "halogen": halogen, "claude": claude[pid], "elapsed_seconds": metadata["elapsed_seconds"], "usage": metadata["usage"], "word_edits": distance(a,b), "astra_word_count": len(a), "character_edits": distance(ref_chars,hyp_chars), "astra_character_count": len(ref_chars), "lexical_differences": diff})
    metrics = {"interpretation": "Pairwise disagreement against provisional Astra readings, not accuracy or ground-truth error rate.", "word_normalization": "Unicode word tokens, casefolded, punctuation removed; apostrophes internal to words preserved. Raw circle rendered as O is retained as an extra token.", "character_normalization": "All whitespace collapsed to single spaces; case and punctuation retained. Physical line breaks are not scored.", "diff_alignment": "SequenceMatcher for readable spans; exact Levenshtein for counts.", "pages": records}
    for field in ["word_edits", "astra_word_count", "character_edits", "astra_character_count", "elapsed_seconds"]:
        metrics[field] = sum(r[field] for r in records)
    metrics["word_disagreement_percent"] = 100 * metrics["word_edits"] / metrics["astra_word_count"]
    metrics["character_disagreement_percent"] = 100 * metrics["character_edits"] / metrics["astra_character_count"]
    (run / "comparison.json").write_text(json.dumps(metrics,ensure_ascii=False,indent=2)+"\n")
    lines = ["# Vanilla Halogen versus GPT-6 Astra — initial handwriting baseline", "", "Six original Huion PNGs, one request each, no lookup table, examples, crops, stroke JSON or transcript supplied to Halogen. The server is the fleet's Flash deployment; this measures Qwen through Halogen, not a separate upstream inference engine.", "", "Astra means the frozen first-pass `runs/codex-initial.json` from this session, verified by session metadata as gpt-6-astra (high effort). That interactive pass had project context and multiple page images; prompts and timing are not matched. Claude's earlier independent pass is included for triangulation. None is writer-confirmed ground truth; do not interpret agreement as accuracy.", "", "| Page | Halogen seconds | Word edits / Astra words | Character edits / Astra characters |", "| --- | ---: | ---: | ---: |"]
    for r in records:
        lines.append(f'| {r["page_id"]} | {r["elapsed_seconds"]:.1f} | {r["word_edits"]} / {r["astra_word_count"]} | {r["character_edits"]} / {r["astra_character_count"]} |')
    lines += ["", f'Total: {metrics["elapsed_seconds"]:.1f} seconds for six serial requests. Case/punctuation-insensitive word disagreement: {metrics["word_edits"]}/{metrics["astra_word_count"]} ({metrics["word_disagreement_percent"]:.1f}%). Whitespace-normalized, case/punctuation-sensitive character disagreement: {metrics["character_edits"]}/{metrics["astra_character_count"]} ({metrics["character_disagreement_percent"]:.1f}%). These rates are directional against the provisional Astra transcript and are not OCR accuracy.', "", "All answers ended with `finish_reason: stop`. Timing is client-observed HTTP wall time including vision, prompt processing, reasoning and output. There is one run per page, with cache mode 2 enabled; this is not a cold-start benchmark or a latency distribution. Astra OCR-only latency and cost were not measured. Halogen is self-hosted without per-request API billing; hardware and electricity costs are excluded.", "", "Word comparison lowercases and removes punctuation. Character comparison collapses whitespace but retains case and punctuation. The `O` Halogen includes for the battery circle is counted as an extra token; see marks separately. Physical layout and line-break fidelity are not scored. All six pages are Huion renders, not phone photographs, so this baseline says nothing yet about journal-photo performance.", ""]
    for r in records:
        lines += [f'## {r["page_id"]}', "", "GPT-6 Astra, initial reading:", "", "```text", r["astra"], "```", "", "Halogen Flash, vanilla:", "", "```text", r["halogen"], "```", "", "Claude, independent initial reading:", "", "```text", r["claude"], "```", "", "Lexical disagreements (Astra → Halogen):", ""]
        lines += [f'- `{d["astra"] or "∅"}` → `{d["halogen"] or "∅"}`' for d in r["lexical_differences"]] or ["None."]
        lines += ["", f'Full uncertainties and marks: [{r["page_id"]}-answer.txt]({r["page_id"]}-answer.txt).', ""]
    (run / "COMPARISON.md").write_text("\n".join(lines))
    print(json.dumps({k:v for k,v in metrics.items() if k not in ["pages", "diff_alignment", "word_normalization", "character_normalization"]},indent=2))


if __name__ == "__main__":
    main()
