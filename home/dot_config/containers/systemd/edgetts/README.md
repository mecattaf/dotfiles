# Edge-TTS - Text-to-Speech Service

## Overview

Edge-TTS provides OpenAI-compatible text-to-speech using Microsoft Edge's neural voices. It's integrated with OpenWebUI for natural-sounding speech output.

## Architecture

```
Request Flow:
User → OpenWebUI → edgetts:5050 → Microsoft Edge API → Audio

Container Communication:
edgetts (container)
    ├─ Port: 5050 (internal), 5050 (published)
    ├─ Volume: edgetts-cache (voice model caching)
    └─ Network: llm.network (internal communication)
```

## Quick Start

### 1. Enable in Configuration

Edit `.chezmoi.yaml.tmpl`:
```yaml
openwebui:
  features:
    text_to_speech: true    # Enable TTS
```

### 2. Deploy Service

```bash
# Apply configuration
chezmoi apply -v

# Reload systemd
systemctl --user daemon-reload

# Start service
systemctl --user start edgetts

# Check status
systemctl --user status edgetts

# Enable on boot
systemctl --user enable edgetts
```

### 3. Test TTS

```bash
# Test API directly
curl -X POST http://localhost:5050/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "model": "tts-1",
    "input": "Hello, this is a test of Edge TTS.",
    "voice": "alloy"
  }' \
  --output test.mp3

# Play the result
mpv test.mp3
```

### 4. Use in OpenWebUI

1. Open OpenWebUI: `https://ai.blueprint.tail8dd1.ts.net`
2. Start a chat
3. Click the speaker icon next to messages
4. Audio will be generated automatically

## Available Voices

### English (US)
- **alloy** - `en-US-AriaNeural` (Neutral, balanced)
- **echo** - `en-US-GuyNeural` (Male, confident)
- **nova** - `en-US-JennyNeural` (Female, friendly)
- **onyx** - `en-US-DavisNeural` (Male, deep)
- **shimmer** - `en-US-AmberNeural` (Female, warm)

### English (UK)
- **fable** - `en-GB-RyanNeural` (Male, British)

### English (Australia)
- **Default** - `en-AU-NatashaNeural` (Female, Australian)

### Other Languages
Microsoft Edge supports 100+ languages. Full list:
https://speech.microsoft.com/portal/voicegallery

## Configuration

Edit `.chezmoi.yaml.tmpl`:

```yaml
edgetts:
  response_format: "mp3"     # mp3, opus, aac, flac, wav
  speed: "1.0"               # 0.5 - 2.0
  voice: "en-AU-NatashaNeural"
  
  models:
    tts-1:
      alloy: "en-US-AriaNeural"
      echo: "en-US-GuyNeural"
      # ... customize voice mappings
```

Then apply:
```bash
chezmoi apply
systemctl --user restart edgetts
```

## API Endpoints

### OpenAI-Compatible

**Generate Speech**
```bash
curl -X POST http://localhost:5050/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "model": "tts-1",
    "input": "Your text here",
    "voice": "alloy",
    "response_format": "mp3",
    "speed": 1.0
  }' \
  --output output.mp3
```

**Health Check**
```bash
curl http://localhost:5050/health
```

**List Available Voices**
```bash
curl http://localhost:5050/v1/voices
```

## Performance

Edge-TTS is **extremely fast** because it uses Microsoft's cloud API:
- Near-instant response (< 1 second for short text)
- No GPU needed
- No model downloads
- High-quality neural voices

**Trade-offs:**
- ✅ Fast and high-quality
- ✅ 100+ languages
- ✅ No local resources needed
- ⚠️ Requires internet connection
- ⚠️ Uses Microsoft's API (not fully private)

**For offline TTS:** Consider Coqui TTS or Piper TTS instead.

## Troubleshooting

### Service Won't Start

```bash
# Check logs
journalctl --user -u edgetts -f

# Test container manually
podman run -it --rm -p 5050:5050 \
  ghcr.io/traefik/parakeet:latest
```

### No Audio Generated

```bash
# Verify service is running
systemctl --user status edgetts

# Test network from OpenWebUI
podman exec openwebui curl http://edgetts:5050/health

# Check OpenWebUI environment
podman exec openwebui env | grep AUDIO_TTS
```

### Wrong Voice or Accent

Edit voice mapping in `.chezmoi.yaml.tmpl`:
```yaml
edgetts:
  models:
    tts-1:
      alloy: "en-GB-SoniaNeural"  # British female
```

### Rate Limiting

If you hit Microsoft's rate limits:
- Reduce TTS usage
- Implement caching (store generated audio)
- Consider self-hosted TTS (Coqui, Piper)

## Integration with OpenWebUI

Configured automatically via `openwebui.env.tmpl`:
```bash
AUDIO_TTS_ENGINE=openai
AUDIO_TTS_OPENAI_API_BASE_URL=http://edgetts:5050/v1
AUDIO_TTS_OPENAI_API_KEY=sk-edgetts-local
AUDIO_TTS_MODEL=tts-1
AUDIO_TTS_VOICE=alloy
```

## Service Management

```bash
# Start
systemctl --user start edgetts

# Stop
systemctl --user stop edgetts

# Restart
systemctl --user restart edgetts

# Status
systemctl --user status edgetts

# Logs
journalctl --user -u edgetts -f

# Enable on boot
systemctl --user enable edgetts
```

## Advanced Features

### Custom Voice Samples

To use your own voice (if supported by the container):
1. Record a clean voice sample (10-30 seconds)
2. Convert to WAV: `ffmpeg -i input.mp3 -ar 22050 -ac 1 voice.wav`
3. Mount in container and configure

### Language-Specific Configuration

For non-English content:
```yaml
edgetts:
  voice: "fr-FR-DeniseNeural"  # French
  # or
  voice: "es-ES-ElviraNeural"  # Spanish
```

## File Structure

```
~/.config/containers/systemd/edgetts/
├── edgetts.container.tmpl    # Quadlet container definition
├── edgetts.volume            # Volume for cache
└── README.md                 # This file
```

## Resources

- [Microsoft Azure TTS Voices](https://speech.microsoft.com/portal/voicegallery)
- [Edge-TTS GitHub](https://github.com/rany2/edge-tts)
- [OpenWebUI Audio Docs](https://docs.openwebui.com)

## Performance Expectations

Edge-TTS is **cloud-based**, so performance depends on:
- Internet connection speed
- Microsoft API availability
- Text length

Typical latency:
- **Short text** (< 100 chars): < 1 second
- **Medium text** (100-500 chars): 1-3 seconds
- **Long text** (> 500 chars): 3-10 seconds

All processing happens on Microsoft's servers, so **no local GPU/CPU load**.

## Privacy Considerations

Edge-TTS sends text to Microsoft's servers for processing.

**If privacy is critical:**
- Use self-hosted TTS (Coqui TTS, Piper)
- Don't enable TTS for sensitive content
- Review Microsoft's privacy policy

**For general use:** Edge-TTS is convenient and high-quality.

## Next Steps

1. **Basic Usage**: Test with OpenWebUI's speaker button
2. **Voice Selection**: Try different voices to find preferred
3. **Integration**: Build custom apps using OpenAI-compatible API
4. **Advanced**: Consider self-hosted TTS if privacy needed

Questions? Check logs: `journalctl --user -u edgetts -f`
```
