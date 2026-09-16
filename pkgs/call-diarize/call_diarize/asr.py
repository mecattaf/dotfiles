"""Local, GPU-only VibeVoice-ASR-Streaming-7B runtime."""

from __future__ import annotations

import json
import os
import time
import wave
from pathlib import Path
from typing import Any

from .pipeline import (
    CHUNK_FRAMES,
    CHUNK_SAMPLES,
    CHUNK_SECONDS,
    FRAME_SAMPLES,
    LOOKAHEAD_FRAMES,
    LOOKAHEAD_SAMPLES,
    SAMPLE_RATE,
    SESSION_CHUNKS,
    Window,
)


MODEL_ID = "vibevoice-asr-streaming-7b-bf16"
MODEL_ARTIFACT = Path("/var/lib/local-models") / MODEL_ID
# The loaned directory is the complete Hugging Face snapshot, including the
# streaming tokenizer. Its <|text_chunk_end|> token ends every chunk; the base
# Qwen2.5 vocabulary does not have it and must never be substituted.
TEXT_CHUNK_END_ID = 151665
MODEL_FILES = [
    "added_tokens.json",
    "config.json",
    "merges.txt",
    "model.safetensors.index.json",
    *(f"model-{index:05d}-of-00008.safetensors" for index in range(1, 9)),
    "preprocessor_config.json",
    "special_tokens_map.json",
    "tokenizer.json",
    "tokenizer_config.json",
    "vocab.json",
]
# The upstream acoustic encoder samples Gaussian latents even under greedy
# decoding. Reseeding per session keeps resumed runs reproducible.
SEED = 42
ASR_MODEL = {
    "id": MODEL_ID,
    "hf_repo": "microsoft/VibeVoice-ASR-Streaming-7B",
    "hf_revision": "60d858b518b4e19d404af3737f848fc185b30177",
    "source_revision": "1541f590c7099820f10ea012f48d2399282df69f",
    "dtype": "bfloat16",
    "attention": "sdpa",
    "decoding": "greedy",
    "seed_per_session": SEED,
    "chunk_samples": CHUNK_SAMPLES,
    "lookahead_samples": LOOKAHEAD_SAMPLES,
    "session_chunks": SESSION_CHUNKS,
    "time_resolution_seconds": round(CHUNK_SECONDS, 4),
}


def verify_checkpoint(model_dir: Path = MODEL_ARTIFACT) -> dict[str, Any]:
    """Refuse a missing loan or a checkpoint with different frame geometry."""

    missing = [name for name in MODEL_FILES if not (model_dir / name).is_file()]
    if missing:
        raise RuntimeError(
            f"streaming ASR checkpoint is incomplete at {model_dir}: missing {missing}; "
            f"borrow {MODEL_ID} with local-models-borrow"
        )
    config = json.loads(
        (model_dir / "preprocessor_config.json").read_text(encoding="utf-8")
    )
    expected = {
        "chunk_frames": CHUNK_FRAMES,
        "lookahead_frames": LOOKAHEAD_FRAMES,
        "speech_tok_compress_ratio": FRAME_SAMPLES,
        "target_sample_rate": SAMPLE_RATE,
    }
    actual = {key: config.get(key) for key in expected}
    if actual != expected:
        raise RuntimeError(
            f"{model_dir} is not the expected streaming checkpoint: "
            f"frame geometry {actual}, expected {expected}"
        )
    return config


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
    """One model residency shared by every streaming session."""

    def __init__(self, model_dir: Path, max_new_tokens: int = 256) -> None:
        import numpy as np
        import torch
        import transformers
        from vibevoice.modular.modeling_vibevoice_asr import (
            VibeVoiceASRForConditionalGeneration,
        )
        from vibevoice.processor.vibevoice_asr_processor import (
            VibeVoiceASRProcessor,
        )

        self.np = np
        self.torch = torch
        self.max_new_tokens = max_new_tokens
        self.gpu = gpu_probe()
        verify_checkpoint(model_dir)
        os.environ.setdefault("HF_HUB_OFFLINE", "1")
        os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
        os.environ.setdefault("HF_DATASETS_OFFLINE", "1")

        started = time.monotonic()
        self.tokenizer = VibeVoiceASRProcessor.from_pretrained(
            str(model_dir), local_files_only=True
        ).tokenizer
        if self.tokenizer.text_chunk_end_id != TEXT_CHUNK_END_ID:
            raise RuntimeError(
                f"tokenizer at {model_dir} has <|text_chunk_end|> id "
                f"{self.tokenizer.text_chunk_end_id}, expected {TEXT_CHUNK_END_ID}"
            )
        loaded = VibeVoiceASRForConditionalGeneration.from_pretrained(
            str(model_dir),
            dtype=torch.bfloat16,
            attn_implementation="sdpa",
            local_files_only=True,
            output_loading_info=True,
        )
        self.model, loading_info = loaded
        load_errors = {
            key: list(loading_info.get(key, []))[:20]
            for key in ("missing_keys", "mismatched_keys", "error_msgs")
            if loading_info.get(key)
        }
        if load_errors:
            raise RuntimeError(f"streaming ASR checkpoint did not load cleanly: {load_errors}")
        # Materialize the weights in host RAM first; Module.to() then performs
        # one transfer into Strix Halo's unified GTT allocation.
        self.model.to(device="cuda")
        self.model.eval()
        self.torch.cuda.synchronize()
        self.load_seconds = round(time.monotonic() - started, 3)
        parameter_device = next(self.model.parameters()).device
        if parameter_device.type != "cuda":
            raise RuntimeError(
                f"VibeVoice loaded on {parameter_device}; CPU inference is forbidden"
            )
        self.device = parameter_device
        self.versions = {
            "transformers": transformers.__version__,
            "unexpected_checkpoint_keys": len(loading_info.get("unexpected_keys", [])),
        }

    def _chunk_audio(self, handle: wave.Wave_read, chunk: int) -> Any:
        """One chunk plus its lookahead, zero-padded past the end of the track."""

        window_samples = CHUNK_SAMPLES + LOOKAHEAD_SAMPLES
        start = chunk * CHUNK_SAMPLES
        handle.setpos(start)
        raw = handle.readframes(min(window_samples, handle.getnframes() - start))
        audio = self.np.zeros(window_samples, dtype=self.np.float32)
        values = self.np.frombuffer(raw, dtype="<i2").astype(self.np.float32)
        audio[: len(values)] = values / 32768.0
        return audio

    def transcribe(self, window: Window, hotwords: str) -> dict[str, Any]:
        """Decode one session exactly as upstream's live streaming path does:
        prompt once, then encode_speech and streaming_generate_step per chunk."""

        torch = self.torch
        torch.manual_seed(SEED)
        torch.cuda.reset_peak_memory_stats(self.device)
        started = time.monotonic()
        state = self.model.init_streaming_state(
            self.tokenizer, context_info=hotwords or None
        )
        torch.cuda.synchronize(self.device)
        prompt_seconds = time.monotonic() - started
        chunks: list[dict[str, Any]] = []
        with wave.open(str(window.audio_path), "rb") as handle:
            if (
                handle.getframerate() != SAMPLE_RATE
                or handle.getnchannels() != 1
                or handle.getsampwidth() != 2
            ):
                raise ValueError(
                    f"VibeVoice input must be 24 kHz mono PCM16: {window.audio_path}"
                )
            for offset in range(window.chunk_count):
                index = window.first_chunk + offset
                chunk_started = time.monotonic()
                audio = torch.from_numpy(self._chunk_audio(handle, index)).to(
                    self.device
                )
                features = self.model.encode_speech(audio.unsqueeze(0))
                torch.cuda.synchronize(self.device)
                encoded = time.monotonic()
                text, state = self.model.streaming_generate_step(
                    audio_features=features,
                    streaming_state=state,
                    tokenizer=self.tokenizer,
                    max_new_tokens=self.max_new_tokens,
                    temperature=0.0,
                )
                torch.cuda.synchronize(self.device)
                chunks.append(
                    {
                        "index": index,
                        "text": text,
                        "encode_seconds": round(encoded - chunk_started, 4),
                        "compute_seconds": round(time.monotonic() - chunk_started, 4),
                        # Re-encoded from the decoded text: the upstream step
                        # does not report its count. Used to flag exhaustion.
                        "decoded_token_count": len(
                            self.tokenizer.encode(text, add_special_tokens=False)
                        ),
                    }
                )
        del state
        elapsed = time.monotonic() - started
        return {
            "request": window.request_identity(hotwords),
            "raw_text": "".join(chunk["text"] for chunk in chunks),
            "chunks": chunks,
            "runtime": {
                **self.gpu,
                **self.versions,
                "model_load_seconds": self.load_seconds,
                "prompt_seconds": round(prompt_seconds, 3),
                "generation_seconds": round(elapsed, 3),
                "audio_seconds": round(window.actual_seconds, 6),
                "realtime_factor": round(
                    elapsed / max(window.actual_seconds, 0.001), 3
                ),
                "chunk_count": len(chunks),
                "max_new_tokens_per_chunk": self.max_new_tokens,
                "peak_gpu_memory_bytes": int(
                    torch.cuda.max_memory_allocated(self.device)
                ),
                "peak_gpu_reserved_bytes": int(
                    torch.cuda.max_memory_reserved(self.device)
                ),
            },
        }

    def close(self) -> None:
        """Release ROCm allocations once transcription is complete."""

        del self.model
        self.torch.cuda.empty_cache()
        self.torch.cuda.synchronize(self.device)
