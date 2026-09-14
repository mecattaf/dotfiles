#!/usr/bin/env python3
"""Fetch only pinned upstream detector source. Never fetch bundled ONNX weights."""
import hashlib,pathlib,urllib.request
url="https://raw.githubusercontent.com/scottmbaker/nuc-ai-experiments/2bddeb0fc78a1a38005747d1b638629b79dca9fe/voicechat/wakeword.py"
b=urllib.request.urlopen(url).read()
expected="373a4dd8947ed91e06ddd3ea62c0459ec7500f67b798e5f3a56077e13587698f"
if hashlib.sha256(b).hexdigest()!=expected:raise SystemExit("Source hash mismatch")
f=pathlib.Path("wakeword.py")
if f.exists() and f.read_bytes()!=b:raise SystemExit("Refusing to overwrite differing source")
f.write_bytes(b)
print(f.resolve())
