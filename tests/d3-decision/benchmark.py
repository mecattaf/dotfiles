"""Bounded typed-decision qualification; emits timings and numerical evidence.

This is an appliance smoke workload, not a model-quality benchmark. Run it on
compute through runtime-test, pointing at the native endpoint or llama-swap's
explicit /upstream/MODEL prefix. It never starts or stops services itself.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import platform
import statistics
import time
from urllib.request import Request, urlopen


QUESTIONS = {
    "kind": {
        "type": "choice",
        "instructions": "What is the main kind of work described in this state?",
        "criteria": {"code": "Writing or debugging software", "billing": "Payments and refunds",
                     "summary": "Summarizing a document"},
    },
    "reasoning": {"type": "noul", "instructions": "Does the task require multi-step reasoning?"},
    "difficulty": {"type": "score", "instructions": "How difficult is the requested task?",
                   "criteria": ["Trivial", "Moderate", "Hard"]},
}
WORKLOADS = [
    ("code", "Write a Python function that merges two sorted lists, handles duplicates, and explains its running time."),
    ("billing", {"ticket": "My card was charged twice for one order. Please refund the duplicate charge.",
                 "order": "fixture-123"}),
    ("long-summary", "Summarize these engineering notes in five sentences.\n" +
     "The service reads a bounded queue, verifies each record, commits an atomic result, and records its latency. " * 64),
]


def host_memory():
    wanted = {"MemTotal", "MemAvailable", "SwapFree"}
    values = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, _, value = line.partition(":")
        if key in wanted:
            values[key + "KiB"] = int(value.split()[0])
    return values


def probabilities(answer):
    if answer["type"] == "noul":
        value = float(answer["noul"])
        return {"false": 1 - value, "true": value}
    return {key: float(value) for key, value in answer["probabilities"].items()}


def validate(answer):
    values = probabilities(answer)
    if not all(math.isfinite(value) and 0 <= value <= 1 for value in values.values()):
        raise ValueError(f"invalid probabilities: {answer}")
    if abs(sum(values.values()) - 1) > 1e-5:
        raise ValueError(f"probabilities do not sum to one: {answer}")
    return values


def call(base, path, body=None):
    request = Request(base.rstrip("/") + path,
                      data=None if body is None else json.dumps(body).encode(),
                      headers={"Content-Type": "application/json"})
    with urlopen(request, timeout=1200) as response:
        return json.load(response)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--model", default="d3-ultra")
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--provenance", default="")
    parser.add_argument("--workload", action="append", choices=[name for name, _ in WORKLOADS])
    args = parser.parse_args()
    if not 2 <= args.repeats <= 10:
        parser.error("repeats must be between 2 and 10")
    report = {
        "created": datetime.now(timezone.utc).isoformat(), "python": platform.python_version(),
        "model": args.model, "base_url": args.base_url, "provenance": args.provenance,
        "before": host_memory(), "requests": [], "summary": {},
    }
    readiness_start = time.perf_counter()
    report["model_card"] = call(args.base_url, "/v1/models")
    report["model_readiness_seconds"] = time.perf_counter() - readiness_start
    for name, state in WORKLOADS:
        if args.workload and name not in args.workload:
            continue
        body = {"model": args.model, "state": state, "questions": QUESTIONS}
        canonical = json.dumps(body, sort_keys=True, separators=(",", ":")).encode()
        runs = []
        for repeat in range(args.repeats):
            before = host_memory()
            start = time.perf_counter()
            result = call(args.base_url, "/v1/systemone", body)
            duration = time.perf_counter() - start
            answers = result.get("answers", {})
            if set(answers) != set(QUESTIONS):
                raise ValueError(f"wrong answer keys: {result}")
            distributions = {}
            for key, question in QUESTIONS.items():
                answer = answers[key]
                if answer.get("type") != question["type"] or "error" in answer:
                    raise ValueError(f"failed typed question: {result}")
                distributions[key] = validate(answer)
            row = {"workload": name, "repeat": repeat, "request_sha256": hashlib.sha256(canonical).hexdigest(),
                   "latency_seconds": duration, "before": before, "after": host_memory(), "response": result}
            report["requests"].append(row)
            runs.append((duration, distributions))
        drift = max(abs(value - runs[0][1][key][option])
                    for _, distributions in runs for key, options in distributions.items()
                    for option, value in options.items())
        argmax_stable = all(
            max(distributions[key], key=distributions[key].get) ==
            max(runs[0][1][key], key=runs[0][1][key].get)
            for _, distributions in runs for key in QUESTIONS)
        report["summary"][name] = {
            "latency_median_seconds": statistics.median(duration for duration, _ in runs),
            "max_probability_drift": drift, "argmax_stable": argmax_stable,
        }
    report["after"] = host_memory()
    report["all_argmax_stable"] = all(row["argmax_stable"] for row in report["summary"].values())
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "summary": report["summary"],
                      "all_argmax_stable": report["all_argmax_stable"]}, indent=2))


if __name__ == "__main__":
    main()
