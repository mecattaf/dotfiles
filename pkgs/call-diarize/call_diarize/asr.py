"""Local, GPU-only VibeVoice-ASR runtime."""

from __future__ import annotations

import os
import time
import wave
from pathlib import Path
from typing import Any

from .pipeline import Window


MODEL_ARTIFACT = Path("/etc/local-models/artifacts/vibevoice-asr-bf16")
TOKENIZER_ARTIFACT = Path("/etc/local-models/artifacts/vibevoice-qwen25-7b-tokenizer")
MODEL_FILES = [
    "config.json",
    "model.safetensors.index.json",
    *(f"model-{index:05d}-of-00008.safetensors" for index in range(1, 9)),
]
TOKENIZER_FILES = ["merges.txt", "tokenizer_config.json", "tokenizer.json", "vocab.json"]
SUPPORT_FILES = ["chat_template.jinja", "generation_config.json", "processor_config.json"]


def _ensure_link(target: Path, source: Path) -> None:
    if not source.is_file():
        raise RuntimeError(f"required local model file is missing: {source}")
    if target.is_symlink() and target.resolve() == source.resolve():
        return
    if target.exists() or target.is_symlink():
        raise RuntimeError(
            f"refusing to replace unexpected model-layout entry {target}; expected link to {source}"
        )
    target.symlink_to(source)


def ensure_model_layout(state_root: Path, support_dir: Path) -> Path:
    """Assemble the proven local snapshot/tokenizer/support symlink farm."""

    model_dir = state_root / "model"
    model_dir.mkdir(parents=True, exist_ok=True)
    for name in MODEL_FILES:
        _ensure_link(model_dir / name, MODEL_ARTIFACT / name)
    for name in TOKENIZER_FILES:
        _ensure_link(model_dir / name, TOKENIZER_ARTIFACT / name)
    for name in SUPPORT_FILES:
        _ensure_link(model_dir / name, support_dir / name)
    return model_dir


def gpu_probe() -> dict[str, Any]:
    """Refuse the known-dead CPU path before touching recording evidence."""

    import torch

    if not torch.version.hip:
        raise RuntimeError(f"installed Torch is not a ROCm build: {torch.__version__}")
    if not torch.cuda.is_available():
        raise RuntimeError("ROCm Torch cannot see a GPU; CPU fallback is forbidden")
    device = torch.cuda.current_device()
    name = torch.cuda.get_device_name(device)
    capability = torch.cuda.get_device_capability(device)
    return {
        "torch_version": torch.__version__,
        "rocm_version": torch.version.hip,
        "device_index": device,
        "device_name": name,
        "device_capability": list(capability),
    }


class VibeVoiceASR:
    """One model residency shared by every initial and recursive chunk."""

    def __init__(self, model_dir: Path, max_new_tokens: int = 1024) -> None:
        import numpy as np
        import torch
        from transformers import VibeVoiceAsrForConditionalGeneration, VibeVoiceAsrProcessor

        self.np = np
        self.torch = torch
        self.max_new_tokens = max_new_tokens
        self.gpu = gpu_probe()
        os.environ.setdefault("HF_HUB_OFFLINE", "1")
        os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
        os.environ.setdefault("HF_DATASETS_OFFLINE", "1")

        started = time.monotonic()
        self.processor = VibeVoiceAsrProcessor.from_pretrained(
            model_dir,
            local_files_only=True,
        )
        self.model = VibeVoiceAsrForConditionalGeneration.from_pretrained(
            model_dir,
            dtype=torch.bfloat16,
            device_map="cuda",
            local_files_only=True,
            low_cpu_mem_usage=True,
        ).eval()
        self.load_seconds = round(time.monotonic() - started, 3)
        parameter_device = next(self.model.parameters()).device
        if parameter_device.type != "cuda":
            raise RuntimeError(
                f"VibeVoice loaded on {parameter_device}; CPU inference is forbidden"
            )
        self.device = parameter_device

    def _read_audio(self, path: Path) -> Any:
        with wave.open(str(path), "rb") as handle:
            if (
                handle.getframerate() != 24_000
                or handle.getnchannels() != 1
                or handle.getsampwidth() != 2
            ):
                raise ValueError(f"VibeVoice input must be 24 kHz mono PCM16: {path}")
            raw = handle.readframes(handle.getnframes())
        return self.np.frombuffer(raw, dtype="<i2").astype(self.np.float32) / 32768.0

    def transcribe(self, window: Window, hotwords: str) -> dict[str, Any]:
        audio = self._read_audio(window.audio_path)
        self.torch.cuda.reset_peak_memory_stats(self.device)
        started = time.monotonic()
        inputs = self.processor.apply_transcription_request(audio=audio, prompt=hotwords)
        inputs = inputs.to(self.device, dtype=self.model.dtype)
        input_tokens = int(inputs.input_ids.shape[1])
        with self.torch.inference_mode():
            output = self.model.generate(
                **inputs,
                max_new_tokens=self.max_new_tokens,
                do_sample=False,
            )
        self.torch.cuda.synchronize(self.device)
        elapsed = time.monotonic() - started
        decoded = self.processor.batch_decode(
            output[:, input_tokens:],
            skip_special_tokens=True,
        )[0]
        try:
            extracted = self.processor.extract_speaker_dict(decoded)
        except Exception:
            extracted = None
        segments = extracted if isinstance(extracted, list) else None
        generated_tokens = int(output.shape[1] - input_tokens)
        return {
            "request": window.request_identity(hotwords),
            "raw_text": decoded,
            "segments": segments,
            "runtime": {
                **self.gpu,
                "model_load_seconds": self.load_seconds,
                "generation_seconds": round(elapsed, 3),
                "audio_seconds": round(window.actual_seconds, 6),
                "realtime_factor": round(elapsed / max(window.actual_seconds, 0.001), 3),
                "input_tokens": input_tokens,
                "generated_tokens": generated_tokens,
                "peak_gpu_memory_bytes": int(
                    self.torch.cuda.max_memory_allocated(self.device)
                ),
            },
        }

    def close(self) -> None:
        """Release ROCm allocations before llama-swap loads cleanup models."""

        del self.model
        self.torch.cuda.empty_cache()
        self.torch.cuda.synchronize(self.device)
