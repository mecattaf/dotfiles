#!/usr/bin/env python3
"""Render reproducible handwriting reference crops from original Huion strokes.

Usage: python3 prepare.py
Requires Pillow. Original captures are read-only; all outputs live beside this script.
Crop coordinates use the extractor's 900 x 1190 page space, not device coordinates.
"""
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def render(data, bounds, target, scale=3):
    left, top, right, bottom = bounds
    if not (0 <= left < right <= 900 and 0 <= top < bottom <= 1190):
        raise ValueError(f"Invalid page-space bounds: {bounds}")
    canvas = Image.new("RGB", (round((right-left)*scale), round((bottom-top)*scale)), "white")
    draw = ImageDraw.Draw(canvas)
    width = max(1, round(1.2*scale))
    for stroke in data["strokes"]:
        points = [((15+p["x"]/data["max_x"]*870-left)*scale,
                   (15+p["y"]/data["max_y"]*1160-top)*scale) for p in stroke]
        if len(points) > 1:
            draw.line(points, fill="#111111", width=width, joint="curve")
        # Round caps also preserve isolated dots.
        for x, y in points[:1] + points[-1:]:
            radius = width / 2
            draw.ellipse((x-radius, y-radius, x+radius, y+radius), fill="#111111")
    canvas.save(target)


def main():
    config = json.loads((ROOT / "corpus.json").read_text())
    captures = []
    for folder in config["source_roots"]:
        for path in sorted(Path(folder).rglob("*.json")):
            data = json.loads(path.read_text())
            if not {"strokes", "max_x", "max_y", "max_press"} <= data.keys():
                continue
            captures.append((path, data))
    manifest = []
    for page in config["pages"]:
        source = Path(page["source"])
        data = json.loads(source.read_text())
        related = []
        for path, other in captures:
            if any(data[k] != other[k] for k in ("max_x", "max_y", "max_press")):
                continue
            count = len(other["strokes"])
            if count and other["strokes"] == data["strokes"][:count]:
                related.append({"source": str(path), "relationship": "identical" if count == len(data["strokes"]) else "earlier_prefix", "stroke_count": count})
        manifest.append({"id": page["id"], "source": str(source), "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "strokes_sha256": digest(data["strokes"]), "stroke_count": len(data["strokes"]), "related_captures": related, "split": "calibration_pending_review"})
        output = ROOT / "crops" / page["id"]
        output.mkdir(parents=True, exist_ok=True)
        render(data, [0, 0, 900, 1190], output / "page.png", scale=2)
        for region in page["regions"]:
            render(data, region["bounds"], output / f'{region["id"]}.png')
    (ROOT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    review = ["# Handwriting review", "", "These are Codex's provisional readings, not ground truth. Confirm literal wording and marks, including mistakes. Crop coordinates and candidate labels are in `corpus.json`. Claude's independent pass is in `runs/`.", ""]
    for page in config["pages"]:
        review += [f'## {page["id"]}', "", f'Source: `{page["source"]}`', ""]
        for region in page["regions"]:
            confirmed = region["label_status"] == "confirmed" and region["confirmed_text"] is not None
            label = region["confirmed_text"] if confirmed else region["candidate"]
            review += [f'![{region["id"]}](crops/{page["id"]}/{region["id"]}.png)', "", f'**{region["id"]} — {"confirmed" if confirmed else "provisional"}:**', "", "```text", label, "```", ""]
            if region.get("note"):
                review += [region["note"], ""]
    (ROOT / "REVIEW.md").write_text("\n".join(review))
    lookup = json.loads((ROOT / "lookup.json").read_text())
    pages = {page["id"]: page for page in config["pages"]}
    atlas = ["# Handwriting lookup table — provisional", "", "Each entry links an image to a candidate word and its original coordinates. None is writer-confirmed yet. A reference prompt may use an entry only after `label_status` is `confirmed` and `confirmed_text` is supplied. Recognition agreement alone is not confirmation.", "", "| Candidate | Source crop | What to compare |", "| --- | --- | --- |"]
    output = ROOT / "crops" / "words"
    output.mkdir(parents=True, exist_ok=True)
    for entry in lookup["entries"]:
        data = json.loads(Path(pages[entry["page_id"]]["source"]).read_text())
        render(data, entry["bounds"], output / f'{entry["id"]}.png')
        confirmed = entry["label_status"] == "confirmed" and entry["confirmed_text"] is not None
        label = entry["confirmed_text"] if confirmed else entry["candidate"]
        label = label.replace("|", "\\|").replace("\n", "<br>")
        atlas.append(f'| {label} ({"confirmed" if confirmed else "provisional"}) | ![{entry["id"]}](crops/words/{entry["id"]}.png) | {entry["note"]} |')
    (ROOT / "LOOKUP.md").write_text("\n".join(atlas) + "\n")
    print(f"Indexed {len(captures)} captures into {len(manifest)} page families; rendered review crops.")


if __name__ == "__main__":
    main()
