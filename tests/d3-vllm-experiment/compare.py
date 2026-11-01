"""Compare identical D3 qualification requests, preserving numerical drift.

The benchmark reports must carry matching workload/repeat/request SHA tuples.
This reports evidence without deciding a universal numerical acceptance limit.
"""

import argparse
import json
import math
from pathlib import Path
import statistics


def distribution(answer):
    if answer["type"] == "noul":
        value = float(answer["noul"])
        return {"false": 1 - value, "true": value}
    return {key: float(value) for key, value in answer["probabilities"].items()}


def compare(reference, candidate):
    def rows(report):
        return {(row["workload"], row["repeat"], row["request_sha256"]): row
                for row in report["requests"]}
    left, right = rows(reference), rows(candidate)
    if left.keys() != right.keys():
        raise ValueError("request workload/repeat/SHA tuples differ")
    changes, deltas, confidence_deltas, score_deltas, workloads = [], [], [], [], {}
    for key, baseline in left.items():
        current = right[key]
        answers = baseline["response"]["answers"]
        others = current["response"]["answers"]
        if answers.keys() != others.keys():
            raise ValueError(f"answer keys differ: {key}")
        for question, answer in answers.items():
            other = others[question]
            if answer["type"] != other["type"]:
                raise ValueError(f"answer type differs: {key}/{question}")
            p, q = distribution(answer), distribution(other)
            if p.keys() != q.keys():
                raise ValueError(f"probability keys differ: {key}/{question}")
            deltas.extend(abs(p[option] - q[option]) for option in p)
            if max(p, key=p.get) != max(q, key=q.get):
                changes.append({"workload": key[0], "repeat": key[1], "question": question,
                                "reference": p, "candidate": q})
            if "confidence" in answer:
                confidence_deltas.append(abs(answer["confidence"] - other["confidence"]))
            if "score" in answer:
                score_deltas.append(abs(answer["score"] - other["score"]))
        workloads.setdefault(key[0], {"reference": [], "candidate": []})
        workloads[key[0]]["reference"].append(baseline["latency_seconds"])
        workloads[key[0]]["candidate"].append(current["latency_seconds"])
    if not all(math.isfinite(value) for value in deltas + confidence_deltas + score_deltas):
        raise ValueError("non-finite comparison output")
    return {
        "matched_requests": len(left), "argmax_changes": changes,
        "maximum_absolute_probability_delta": max(deltas, default=0),
        "median_absolute_probability_delta": statistics.median(deltas),
        "maximum_absolute_confidence_delta": max(confidence_deltas, default=0),
        "maximum_absolute_expected_score_delta": max(score_deltas, default=0),
        "latency": {name: {
            "reference_median_seconds": statistics.median(values["reference"]),
            "candidate_median_seconds": statistics.median(values["candidate"]),
            "candidate_over_reference": statistics.median(values["candidate"]) /
                                        statistics.median(values["reference"]),
        } for name, values in workloads.items()},
        "reference_repeat_summary": reference["summary"],
        "candidate_repeat_summary": candidate["summary"],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--libstrix", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    reports = {name: json.loads(getattr(args, name).read_text())
               for name in ("native", "baseline", "libstrix")}
    result = {
        "provenance": {name: report.get("provenance") for name, report in reports.items()},
        "native_to_stock": compare(reports["native"], reports["baseline"]),
        "stock_to_libstrix": compare(reports["baseline"], reports["libstrix"]),
        "native_to_libstrix": compare(reports["native"], reports["libstrix"]),
        "limits": ["Three typed text questions per request; no multimodal or single-question calibration claim.",
                   "Native shares state across questions; stock repeats its prefills.",
                   "The two runtimes use different Torch/ROCm and attention implementations.",
                   "This is a small appliance qualification, not a model-quality benchmark."],
    }
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
