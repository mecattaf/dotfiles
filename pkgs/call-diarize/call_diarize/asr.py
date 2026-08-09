"""Local, GPU-only VibeVoice-ASR runtime."""

from __future__ import annotations

import json
import os
import re
import time
import wave
from pathlib import Path
from typing import Any

from .pipeline import Window, normalize_asr_segments


MODEL_ARTIFACT = Path("/etc/local-models/artifacts/vibevoice-asr-bf16")
TOKENIZER_ARTIFACT = Path("/etc/local-models/artifacts/vibevoice-qwen25-7b-tokenizer")
MODEL_FILES = [
    "config.json",
    "model.safetensors.index.json",
    *(f"model-{index:05d}-of-00008.safetensors" for index in range(1, 9)),
]
TOKENIZER_FILES = [
    "merges.txt",
    "tokenizer_config.json",
    "tokenizer.json",
    "vocab.json",
]
SUPPORT_FILES = [
    "chat_template.jinja",
    "generation_config.json",
    "processor_config.json",
]


def _ensure_link(target: Path, source: Path, refresh_store_link: bool = False) -> None:
    if not source.is_file():
        raise RuntimeError(f"required local model file is missing: {source}")
    if target.is_symlink() and target.resolve() == source.resolve():
        return
    if refresh_store_link and target.is_symlink():
        existing_source = Path(os.readlink(target))
        if str(existing_source).startswith("/nix/store/"):
            temporary = target.with_name(f".{target.name}.{os.getpid()}.new")
            temporary.symlink_to(source)
            os.replace(temporary, target)
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
        _ensure_link(model_dir / name, support_dir / name, refresh_store_link=True)
    return model_dir


LEGACY_STATE_DICT_MAPPING = {
    # Qwen language model.
    r"^model\.language_model\.embed_tokens\.weight": (
        r"language_model.model.embed_tokens.weight"
    ),
    r"^model\.language_model\.layers\.(\d+)\.self_attn\.(q|k|v|o)_proj\.": (
        r"language_model.model.layers.\1.self_attn.\2_proj."
    ),
    r"^model\.language_model\.layers\.(\d+)\.mlp\.(gate|up|down)_proj\.": (
        r"language_model.model.layers.\1.mlp.\2_proj."
    ),
    r"^model\.language_model\.layers\.(\d+)\.input_layernorm\.": (
        r"language_model.model.layers.\1.input_layernorm."
    ),
    r"^model\.language_model\.layers\.(\d+)\.post_attention_layernorm\.": (
        r"language_model.model.layers.\1.post_attention_layernorm."
    ),
    r"^model\.language_model\.norm\.": r"language_model.model.norm.",
    r"^lm_head\.": r"language_model.lm_head.",
    # Acoustic and semantic tokenizer encoders.
    r"^model\.acoustic_tokenizer\.encoder\.downsample_layers\.0\.0\.conv\.": (
        r"acoustic_tokenizer_encoder.stem.conv.conv."
    ),
    r"^model\.acoustic_tokenizer\.encoder\.stages\.0\.": (
        r"acoustic_tokenizer_encoder.stem.stage."
    ),
    r"^model\.acoustic_tokenizer\.encoder\.downsample_layers\.(\d+)\.0\.conv\.": (
        r"acoustic_tokenizer_encoder.conv_layers.PLACEHOLDER.conv.conv."
    ),
    r"^model\.acoustic_tokenizer\.encoder\.stages\.(\d+)\.": (
        r"acoustic_tokenizer_encoder.conv_layers.PLACEHOLDER.stage."
    ),
    r"^model\.acoustic_tokenizer\.encoder\.head\.conv\.": (
        r"acoustic_tokenizer_encoder.head."
    ),
    r"^model\.semantic_tokenizer\.encoder\.downsample_layers\.0\.0\.conv\.": (
        r"semantic_tokenizer_encoder.stem.conv.conv."
    ),
    r"^model\.semantic_tokenizer\.encoder\.stages\.0\.": (
        r"semantic_tokenizer_encoder.stem.stage."
    ),
    r"^model\.semantic_tokenizer\.encoder\.downsample_layers\.(\d+)\.0\.conv\.": (
        r"semantic_tokenizer_encoder.conv_layers.PLACEHOLDER.conv.conv."
    ),
    r"^model\.semantic_tokenizer\.encoder\.stages\.(\d+)\.": (
        r"semantic_tokenizer_encoder.conv_layers.PLACEHOLDER.stage."
    ),
    r"^model\.semantic_tokenizer\.encoder\.head\.conv\.": (
        r"semantic_tokenizer_encoder.head."
    ),
    # Nested causal-conv wrappers were flattened in the HF model.
    r"mixer\.conv\.conv\.conv\.": r"mixer.conv.",
    r"\.conv\.conv\.conv\.": r".conv.conv.",
    # The two original connectors became one named projector.
    r"^model\.acoustic_connector\.fc1\.": (r"multi_modal_projector.acoustic_linear_1."),
    r"^model\.acoustic_connector\.fc2\.": (r"multi_modal_projector.acoustic_linear_2."),
    r"^model\.acoustic_connector\.norm\.": r"multi_modal_projector.acoustic_norm.",
    r"^model\.semantic_connector\.fc1\.": (r"multi_modal_projector.semantic_linear_1."),
    r"^model\.semantic_connector\.fc2\.": (r"multi_modal_projector.semantic_linear_2."),
    r"^model\.semantic_connector\.norm\.": r"multi_modal_projector.semantic_norm.",
}


def map_legacy_key(old_key: str) -> str:
    """Apply the official conversion's ordered, potentially chained rewrites."""

    new_key = old_key
    for pattern, target in LEGACY_STATE_DICT_MAPPING.items():
        match = re.search(pattern, new_key)
        if not match:
            continue
        replacement = target
        if "PLACEHOLDER" in replacement:
            replacement = replacement.replace(
                "PLACEHOLDER", str(int(match.group(1)) - 1)
            )
        new_key = re.sub(pattern, replacement, new_key)
    return new_key


def legacy_key_mapping(model_dir: Path) -> dict[str, str]:
    """Build exact streaming renames for every inference weight in the artifact.

    The official conversion deliberately chains regex rewrites and computes a
    shifted layer index. Precomputing each final name from the shard index keeps
    that behavior explicit without materializing a duplicate checkpoint.
    """

    index = json.loads(
        (model_dir / "model.safetensors.index.json").read_text(encoding="utf-8")
    )
    mapping: dict[str, str] = {}
    for old_key in index["weight_map"]:
        if old_key.startswith("model.acoustic_tokenizer.decoder."):
            continue
        new_key = map_legacy_key(old_key)
        if new_key != old_key:
            mapping[rf"^{re.escape(old_key)}$"] = new_key
    return mapping


def legacy_config(model_dir: Path) -> Any:
    """Convert the original compositional config without mutating the artifact."""

    from transformers import (
        Qwen2Config,
        VibeVoiceAcousticTokenizerEncoderConfig,
        VibeVoiceAsrConfig,
    )

    original = json.loads((model_dir / "config.json").read_text(encoding="utf-8"))
    remove = {
        "decoder_depths",
        "decoder_n_filters",
        "decoder_ratios",
        "std_dist_type",
        "fix_std",
        "pad_mode",
        "conv_bias",
        "causal",
        "mixer_layer",
        "layernorm",
        "disable_last_norm",
        "conv_norm",
        "corpus_normalize",
        "layernorm_elementwise_affine",
    }

    def encoder_config(source: dict[str, Any], acoustic: bool) -> Any:
        value = source.copy()
        depths = value.pop("encoder_depths")
        value["depths"] = [int(item) for item in depths.split("-")]
        value["rms_norm_eps"] = value.pop("layernorm_eps")
        value["downsampling_ratios"] = list(reversed(value.pop("encoder_ratios")))
        value["num_filters"] = value.pop("encoder_n_filters")
        value["hidden_size"] = value.pop("vae_dim")
        if acoustic:
            value["vae_std"] = value["fix_std"] / 0.8
        for key in remove:
            value.pop(key, None)
        value.pop("model_type", None)
        return VibeVoiceAcousticTokenizerEncoderConfig(**value)

    return VibeVoiceAsrConfig(
        acoustic_tokenizer_encoder_config=encoder_config(
            original["acoustic_tokenizer_config"], acoustic=True
        ),
        semantic_tokenizer_encoder_config=encoder_config(
            original["semantic_tokenizer_config"], acoustic=False
        ),
        text_config=Qwen2Config(**original["decoder_config"]),
        dtype="bfloat16",
    )


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
        from transformers import (
            VibeVoiceAsrForConditionalGeneration,
            VibeVoiceAsrProcessor,
        )

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
        # The canonical host artifact predates the Transformers-native layout.
        # Apply Microsoft's/Hugging Face's official conversion mapping while
        # streaming the original shards, and prove that every inference weight
        # (apart from the intentionally unused acoustic decoder) was consumed.
        VibeVoiceAsrForConditionalGeneration._keys_to_ignore_on_load_unexpected = [
            r"^model\.acoustic_tokenizer\.decoder\."
        ]
        loaded = VibeVoiceAsrForConditionalGeneration.from_pretrained(
            model_dir,
            config=legacy_config(model_dir),
            dtype=torch.bfloat16,
            key_mapping=legacy_key_mapping(model_dir),
            local_files_only=True,
            low_cpu_mem_usage=True,
            output_loading_info=True,
        )
        self.model, loading_info = loaded
        load_errors = {
            "missing_keys": loading_info.get("missing_keys", []),
            "unexpected_keys": loading_info.get("unexpected_keys", []),
            "mismatched_keys": loading_info.get("mismatched_keys", []),
            "error_msgs": loading_info.get("error_msgs", []),
        }
        if any(load_errors.values()):
            summary = {
                key: list(value)[:20] for key, value in load_errors.items() if value
            }
            raise RuntimeError(
                f"VibeVoice checkpoint conversion was incomplete: {summary}"
            )
        # Loading safetensors directly into GTT makes ROCm fault each mmap page
        # through the 512 MiB aperture and eventually degrades to minutes per
        # tensor on this APU. Finish mmap materialization in ordinary host RAM
        # before Module.to() performs the unified-memory transfer.
        self.model.to(device="cuda")
        self.model.eval()
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
        inputs = self.processor.apply_transcription_request(
            audio=audio, prompt=hotwords
        )
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
        segments = (
            normalize_asr_segments(extracted) if isinstance(extracted, list) else None
        )
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
                "realtime_factor": round(
                    elapsed / max(window.actual_seconds, 0.001), 3
                ),
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
