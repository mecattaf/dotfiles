# Whisper STT - Speech-to-Text Service

## Overview

Whisper provides OpenAI-compatible speech-to-text transcription using OpenAI's Whisper models with automatic Vulkan GPU acceleration for AMD hardware.

## Architecture

```
Request Flow:
User → OpenWebUI → whisper:8000 → faster-whisper-server → Whisper models

Container Communication:
whisper (container)
    ├─ Mounted: ~/.cache/whisper.cpp (model cache)
    ├─ GPU: /dev/dri, /dev/kfd (Vulkan)
    └─ Network: llm.network (internal communication)

Host Tools:
whisper-cpp (CLI) - Uses same model cache
```

## Quick Start

### 1. Install Host Binary

```bash
# Install whisper.cpp from Fedora repos
sudo dnf install whisper-cpp

# Verify installation
whisper-cpp --help
```

### 2. Deploy Service

```bash
# Apply chezmoi configuration
chezmoi apply -v

# Reload systemd
systemctl --user daemon-reload

# Start whisper service
systemctl --user start whisper

# Check status
systemctl --user status whisper

# Enable on boot
systemctl --user enable whisper
```

### 3. Test Transcription

```bash
# Test API directly
curl -X POST http://localhost:8765/v1/audio/transcriptions \
  -H "Content-Type: multipart/form-data" \
  -F "file=@test.mp3" \
  -F "model=whisper-1"

# Test from OpenWebUI container
podman exec openwebui curl http://whisper:8000/health
```

### 4. Use in OpenWebUI

1. Open OpenWebUI: `https://ai.blueprint.tail8dd1.ts.net`
2. Click microphone icon in chat input
3. Record audio or upload file
4. Whisper automatically transcribes
5. Transcription appears in chat input

## Available Models

Models are automatically downloaded on first use and cached in `~/.cache/whisper.cpp/`

| Model | Size | RAM | Speed (RTFx) | Quality | Use Case |
|-------|------|-----|--------------|---------|----------|
| **tiny** | 75 MB | 1 GB | 32x | Basic | Quick notes, testing |
| **base** | 142 MB | 1 GB | 16x | Good | General use ✅ |
| **small** | 466 MB | 2 GB | 6x | Better | Important transcripts |
| **medium** | 1.5 GB | 5 GB | 2x | Great | High accuracy needed |
| **large-v3** | 2.9 GB | 10 GB | 1x | Best | Professional use |

**Recommended**: Start with `base` model (configured in `.chezmoi.yaml.tmpl`)

**RTFx** = Real-Time Factor (16x = 1 second of audio transcribed in 0.0625 seconds)

## Configuration

Edit `.chezmoi.yaml.tmpl`:

```yaml
whisper:
  model: "base"          # tiny, base, small, medium, large-v3
  language: "en"         # Specific language or empty for auto-detect
  beam_size: 5           # Higher = more accurate but slower
  compute_type: "auto"   # auto, int8, float16, float32
  device: "auto"         # auto for Vulkan detection
```

Then apply:

```bash
chezmoi apply
systemctl --user restart whisper
```

## CLI Usage (Host)

```bash
# Transcribe with host binary
whisper-cpp -m base -f audio.mp3 -otxt

# Translate to English
whisper-cpp -m base -f audio.mp3 -tr -otxt

# Output formats: txt, vtt, srt, json
whisper-cpp -m base -f audio.mp3 -osrt

# Specific language (faster than auto-detect)
whisper-cpp -m base -l fr -f french_audio.mp3 -otxt
```

## API Endpoints

### OpenAI-Compatible

**Transcribe Audio**
```bash
curl -X POST http://localhost:8765/v1/audio/transcriptions \
  -H "Content-Type: multipart/form-data" \
  -F "file=@audio.mp3" \
  -F "model=whisper-1" \
  -F "language=en"
```

**Translate to English**
```bash
curl -X POST http://localhost:8765/v1/audio/translations \
  -H "Content-Type: multipart/form-data" \
  -F "file=@audio.mp3" \
  -F "model=whisper-1"
```

**Health Check**
```bash
curl http://localhost:8765/health
```

## Performance Tuning

### For Speed (Real-time Transcription)
```yaml
whisper:
  model: "tiny"         # Fastest model
  beam_size: 1          # Greedy decoding
  compute_type: "int8"  # Quantized
```

### For Accuracy (Batch Processing)
```yaml
whisper:
  model: "large-v3"     # Best quality
  beam_size: 10         # More thorough search
  compute_type: "float16"
```

### For Balance (Recommended)
```yaml
whisper:
  model: "base"         # Good quality
  beam_size: 5          # Standard search
  compute_type: "auto"  # Automatic optimization
```

## GPU Acceleration

The container automatically detects and uses AMD GPU via Vulkan:
- `/dev/dri` - Direct Rendering Infrastructure
- `/dev/kfd` - Kernel Fusion Driver
- Vulkan backend in faster-whisper-server

On AMD Strix Halo, expect:
- **base model**: ~16x real-time (6 seconds audio in 0.375 seconds)
- **small model**: ~6x real-time
- **large-v3**: ~1x real-time

## Model Management

### Pre-download Models

```bash
# Models auto-download on first use, or pre-download:
mkdir -p ~/.cache/whisper.cpp
cd ~/.cache/whisper.cpp

# Download base model
curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin" \
  -o ggml-base.en.bin

# Download multilingual base
curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin" \
  -o ggml-base.bin
```

### List Cached Models

```bash
ls -lh ~/.cache/whisper.cpp/
```

### Remove Models

```bash
rm ~/.cache/whisper.cpp/ggml-*.bin
```

## Service Management

```bash
# Start
systemctl --user start whisper

# Stop
systemctl --user stop whisper

# Restart
systemctl --user restart whisper

# Status
systemctl --user status whisper

# Logs (follow)
journalctl --user -u whisper -f

# Logs (last 100 lines)
journalctl --user -u whisper -n 100

# Enable on boot
systemctl --user enable whisper

# Disable
systemctl --user disable whisper
```

## Troubleshooting

### Service Won't Start

```bash
# Check logs
journalctl --user -u whisper -f

# Verify GPU access
podman exec whisper ls -la /dev/dri /dev/kfd

# Test container manually
podman run -it --rm \
  --device=/dev/dri --device=/dev/kfd \
  docker.io/fedirz/faster-whisper-server:latest-cpu
```

### Transcription Too Slow

1. Use smaller model (`tiny` or `base`)
2. Reduce `beam_size` to 1
3. Set `compute_type` to `int8`
4. Check GPU is being used: `podman exec whisper env | grep DEVICE`

### Wrong Language Detected

Set specific language in `.chezmoi.yaml.tmpl`:
```yaml
whisper:
  language: "fr"  # French
```

Or specify in API call:
```bash
curl -X POST http://localhost:8765/v1/audio/transcriptions \
  -F "file=@audio.mp3" -F "language=es"
```

### OpenWebUI Can't Connect

```bash
# Verify service running
systemctl --user status whisper

# Test network from OpenWebUI
podman exec openwebui curl http://whisper:8000/health

# Check OpenWebUI environment
podman exec openwebui env | grep AUDIO_STT
```

### Model Download Fails

```bash
# Check logs for download errors
journalctl --user -u whisper -n 100

# Pre-download models manually (see Model Management)

# Verify cache directory permissions
ls -ld ~/.cache/whisper.cpp
```

## Integration with Other Services

### OpenWebUI
Configured automatically via `openwebui.env.tmpl`:
```bash
AUDIO_STT_ENGINE=openai
AUDIO_STT_OPENAI_API_BASE_URL=http://whisper:8000/v1
AUDIO_STT_OPENAI_API_KEY=sk-whisper-local
```

### Caddy (Optional External Access)
Route configured in `caddy/whisper.caddy.tmpl`:
```
https://whisper.blueprint.tail8dd1.ts.net
```

## Advanced Features

### Speaker Diarization
For "who spoke when" analysis, consider:
- Parakeet v3 (faster, European languages)
- pyannote.audio (more accurate)

See `sst/additional-investigation.md` for details.

### Custom Vocabulary
Not directly supported in Whisper. For technical terms:
1. Use large-v3 model (better at acronyms)
2. Post-process with LLM to fix domain-specific terms

### Batch Processing

```bash
# Process multiple files
for file in *.mp3; do
  whisper-cpp -m base -f "$file" -osrt
done
```

## File Structure

```
~/.config/containers/systemd/whisper/
├── whisper.container.tmpl    # Quadlet container definition
├── whisper-cache.volume       # Volume definition
└── README.md                  # This file

~/.cache/whisper.cpp/
└── ggml-*.bin                # Downloaded models

~/.config/caddy/
└── whisper.caddy.tmpl        # Optional Caddy route
```

## Resources

- [faster-whisper-server](https://github.com/fedirz/faster-whisper-server)
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
- [OpenAI Whisper](https://github.com/openai/whisper)
- [OpenWebUI Audio Docs](https://docs.openwebui.com)

## Performance Expectations

On AMD Strix Halo (128GB unified memory, Vulkan):

| Model | RTFx | Use Case |
|-------|------|----------|
| tiny | 32x | Quick dictation |
| base | 16x | General chat ✅ |
| small | 6x | Accurate transcripts |
| medium | 2x | Professional work |
| large-v3 | 1x | Best quality |

Your system can comfortably run `medium` or even `large-v3` in real-time!

## Next Steps

1. **Basic Usage**: Start with `base` model for chat
2. **Optimization**: Profile your workload and adjust model/settings
3. **Advanced**: Add speaker diarization for meeting transcripts
4. **Integration**: Build custom apps using the OpenAI-compatible API

Questions? Check logs: `journalctl --user -u whisper -f`
