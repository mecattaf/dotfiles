"""Supplementary native checks: Ultra's one-question calibration and Box/Track."""

import argparse
import base64
import hashlib
import json
from pathlib import Path
import time
from urllib.request import Request, urlopen

from benchmark import QUESTIONS, WORKLOADS


def call(base, body):
    request = Request(base.rstrip("/") + "/v1/systemone", data=json.dumps(body).encode(),
                      headers={"Content-Type": "application/json"})
    start = time.perf_counter()
    with urlopen(request, timeout=300) as response:
        result = json.load(response)
    return result, time.perf_counter() - start


def data_url(path, kind):
    return f"data:{kind};base64," + base64.b64encode(path.read_bytes()).decode()


def box_valid(box):
    return (set(box) == {"top", "bottom", "left", "right"} and
            0 <= box["top"] < box["bottom"] <= 1 and
            0 <= box["left"] < box["right"] <= 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--model", default="d3-ultra")
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--video", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--provenance", default="")
    args = parser.parse_args()
    cases = [
        ("single-choice-temperature", {"model": args.model, "state": WORKLOADS[0][1],
                                       "questions": {"kind": QUESTIONS["kind"]}}),
        ("synthetic-image-box", {
            "model": args.model, "state": "Inspect this synthetic geometric picture.",
            "images": [data_url(args.image, "image/png")],
            "questions": {
                "shape": {"type": "choice", "instructions": "What is the prominent colored shape?",
                          "criteria": {"red_square": "A red square", "blue_circle": "A blue circle",
                                       "green_triangle": "A green triangle"}},
                "red": {"type": "noul", "instructions": "Is there a red square?"},
                "where": {"type": "box", "instructions": "the red square"},
            },
        }),
    ]
    if args.video:
        cases.append(("synthetic-video-track", {
            "model": args.model, "state": "Inspect this short synthetic geometric video.",
            "videos": [data_url(args.video, "video/mp4")],
            "questions": {"where": {"type": "track", "instructions": "the red square", "rate": 1}},
        }))
    rows = []
    report = {"model": args.model, "base_url": args.base_url, "provenance": args.provenance, "cases": rows}
    try:
        for name, body in cases:
            request_digest = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
            result, latency = call(args.base_url, body)
            row = {"name": name, "request_sha256": request_digest, "request": body,
                   "latency_seconds": latency, "response": result}
            rows.append(row)
            answers = result.get("answers", {})
            assert set(answers) == set(body["questions"]), result
            for key, question in body["questions"].items():
                answer = answers[key]
                assert answer.get("type") == question["type"] and "error" not in answer, result
                if question["type"] == "box":
                    assert box_valid(answer["box"]), result
                elif question["type"] == "track":
                    assert answer["track"], result
                    assert all(box_valid(frame["box"]) and 0 <= frame["visible"] <= 1
                               for frame in answer["track"]), result
                elif question["type"] == "noul":
                    assert 0 <= answer["noul"] <= 1, result
                else:
                    assert abs(sum(answer["probabilities"].values()) - 1) < 1e-5, result
            row["valid"] = True
    except BaseException as error:
        report["error"] = repr(error)
        raise
    finally:
        args.output.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"output": str(args.output), "cases": [
            {"name": row["name"], "latency_seconds": row["latency_seconds"],
             "valid": row.get("valid", False)} for row in rows]}, indent=2))


if __name__ == "__main__":
    main()
