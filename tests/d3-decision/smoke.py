"""Exercise the installed native worker on a tiny Ultra-shaped CPU checkpoint.

The upstream fixture embeds package code that raises if imported, and follows
Ultra's prefix_bidir/header-v1 layout. This validates packaging and the real
System One HTTP contract without loading production weights or a GPU.
"""

import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
from urllib.error import URLError
from urllib.request import Request, urlopen


def main():
    executable = sys.argv[1]
    with tempfile.TemporaryDirectory(prefix="d3-smoke-") as directory:
        root = Path(directory)
        package = root / "ultra-fixture"
        env = dict(os.environ, HF_HUB_OFFLINE="1", CUDA_VISIBLE_DEVICES="", HIP_VISIBLE_DEVICES="")
        subprocess.run(
            [executable, "fixture", str(package), "--family", "decision3", "--variant", "ultra"],
            env=env,
            check=True,
        )
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        log = (root / "server.log").open("w+")
        process = subprocess.Popen(
            [executable, "serve", str(package), "--offline", "--device", "cpu",
             "--engine", "native", "--family", "decision3", "--threads", "1",
             "--served-model-name", "d3-smoke", "--host", "127.0.0.1", "--port", str(port),
             "--max-num-seqs", "1", "--max-num-batched-tokens", "4096",
             "--result-cache-entries", "0", "--media-workers", "0", "--load-attempts", "1"],
            stdout=log,
            stderr=log,
            env=env,
        )
        try:
            endpoint = f"http://127.0.0.1:{port}"
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError("native worker exited during startup")
                try:
                    with urlopen(endpoint + "/health", timeout=2) as response:
                        if response.status == 200:
                            break
                except (URLError, TimeoutError):
                    pass
                time.sleep(0.2)
            else:
                raise RuntimeError("native worker readiness timeout")
            with urlopen(endpoint + "/v1/models", timeout=5) as response:
                models = json.load(response)
            assert "d3-smoke" in json.dumps(models), models
            body = {
                "model": "d3-smoke",
                "state": "Write a Python function that merges two sorted lists.",
                "questions": {
                    "kind": {"type": "choice", "instructions": "What kind of work is this?",
                             "criteria": {"code": "Programming", "math": "Mathematics"}},
                    "reasoning": {"type": "noul", "instructions": "Does this need reasoning?"},
                    "difficulty": {"type": "score", "instructions": "How hard is this?",
                                   "criteria": ["Easy", "Hard"]},
                },
            }
            results = []
            for _ in range(2):
                request = Request(endpoint + "/v1/systemone", data=json.dumps(body).encode(),
                                  headers={"Content-Type": "application/json"})
                with urlopen(request, timeout=30) as response:
                    result = json.load(response)
                answers = result["answers"]
                assert set(answers) == set(body["questions"]), result
                for key, question in body["questions"].items():
                    assert "error" not in answers[key], result
                    assert answers[key]["type"] == question["type"], result
                    if question["type"] == "noul":
                        assert 0 <= answers[key]["noul"] <= 1, result
                        continue
                    probabilities = answers[key]["probabilities"]
                    assert all(0 <= p <= 1 for p in probabilities.values()), result
                    assert abs(sum(probabilities.values()) - 1) < 1e-5, result
                results.append(answers)
            assert results[0] == results[1], results
            print("PASS: native prefix_bidir Ultra fixture; HTTP Choice/Noul/Score; repeatable probabilities; no package-code import")
        except BaseException:
            log.flush()
            log.seek(0)
            print(log.read(), file=sys.stderr)
            raise
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            log.close()


if __name__ == "__main__":
    main()
