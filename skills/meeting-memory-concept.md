# Meeting Memory (VNotes) - Concept Document

A browser-based meeting recorder with transcription and speaker diarization, running entirely on Cloudflare's edge infrastructure.

---

## Core Idea

Record calls/meetings directly in the browser, transcribe them with Whisper, optionally identify who said what (speaker diarization), and store everything — audio + transcript — as searchable, persistent notes. Zero backend servers. Everything runs on Cloudflare Workers, D1, R2, and Workers AI.

## Architecture Philosophy

### Edge-Native, Serverless-First

The entire stack runs on Cloudflare with no traditional server infrastructure:

- **Compute**: Cloudflare Workers (stateless, ephemeral)
- **Relational data**: D1 (SQLite at the edge) for notes and transcription metadata
- **Blob storage**: R2 (S3-compatible) for audio recordings
- **ML inference**: Workers AI for Whisper transcription and LLM post-processing
- **Deployment**: Single `wrangler deploy` command, no ops burden

### Client-Side Recording, Server-Side Processing

Audio capture happens entirely in the browser via `getUserMedia` + `MediaRecorder`. Audio never leaves the device until the user explicitly triggers transcription. This is a deliberate privacy-first choice — no always-on server listening.

### Pipeline: Record -> Transcribe -> Post-Process -> Store

```
Browser microphone (WebM via MediaRecorder)
  -> POST to Workers AI (Whisper model: @cf/openai/whisper)
  -> Optional LLM cleanup (Llama 3.1 8B: punctuation, grammar, formatting)
  -> Text returned to browser for user editing
  -> On save: audio uploaded to R2, note + R2 URLs inserted into D1
```

The post-processing step is user-configurable — toggle on/off, custom prompt stored in localStorage. This keeps it optional without server-side user state.

## Speaker Diarization — The Unsolved Problem

The original goal was to identify *who* said *what*. Three approaches were explored:

1. **WhisperX** — simultaneous transcription + diarization. Requires Python Workers (beta), PyTorch, and GPU access. Infrastructure wasn't stable enough at the time.
2. **Pyannote** — standalone speaker identification model. Same Python/GPU constraints as WhisperX.
3. **LLM-based fallback** — feed raw Whisper output to an LLM and ask it to infer speaker changes from context, tone shifts, and conversational patterns. Partially implemented (Llama used for punctuation/grammar only).

**What shipped**: Basic Whisper transcription without diarization. The pragmatic decision was to deliver a working MVP rather than wait for uncertain Python Workers GPU support.

**Key insight for revisiting**: The LLM-based approach is the most promising for a serverless context. As models improve and context windows grow, feeding a full conversation transcript to an LLM with a prompt like "identify speaker changes and label speakers" becomes increasingly viable without needing specialized ML models at all.

## Data Model

Two tables, intentionally simple:

**Notes** — the primary entity:
- `text` (the transcript / user-edited content)
- `audio_urls` (JSON array of R2 keys, e.g. `["recordings/1699200000000.webm"]`)
- `created_at`, `updated_at`

**Transcriptions** — optional, for event-driven processing:
- `file_key` (R2 object key)
- `transcription` (raw Whisper output)
- `created_at`

Audio URLs stored as a JSON text column in SQLite avoids a separate join table — good enough for a single-user tool.

## Event-Driven Infrastructure (Built but Unused)

R2 event triggers were configured in `wrangler.toml` so that uploading an audio file could automatically kick off transcription via a Worker handler. This was infrastructure for a future async pipeline (e.g., batch-process 100 recordings) but the synchronous API path was chosen for UX predictability in the MVP.

## Design Decisions Worth Preserving

| Decision | Rationale |
|----------|-----------|
| Full-stack TypeScript (Nuxt + Nitro + Workers) | Single language, shared types between frontend and backend, no serialization mismatches |
| Settings in localStorage, not server | No auth system needed, no user table, settings travel with the browser |
| Whisper over WhisperX | Ship what works in serverless today; diarization can be added later |
| No authentication | Single-user deployment assumption; add Cloudflare Access if multi-user needed |
| MediaRecorder composable (`useMediaRecorder`) | Encapsulates browser audio API complexity; provides real-time waveform data for visualization |
| Minimal dependencies (only H3) | Everything else is Cloudflare-native or framework-provided; reduces supply chain risk |

## UX Flow

1. User clicks "New Note" — full-screen two-panel modal opens
2. Left panel: textarea for transcript/notes. Right panel: recording controls
3. Hit record — real-time waveform visualization on canvas (AnalyserNode frequency data)
4. Stop recording — Whisper transcribes in ~2-5 seconds, text auto-inserts into textarea
5. User can record multiple segments (each appends to the transcript)
6. User edits text as needed, then saves
7. Audio files upload to R2, note + URLs save to D1
8. Home page shows chronological list of notes with inline audio players

## What to Carry Forward

If rebuilding this concept:

- **The edge-native approach is sound.** Cloudflare's stack (Workers + D1 + R2 + AI) is sufficient for this entire use case with zero ops.
- **Browser-side recording is the right call.** No server-side audio capture needed; `MediaRecorder` API is mature and reliable.
- **Diarization via LLM is the path of least resistance** in a serverless context. Specialized ML models (Pyannote, WhisperX) need GPU infrastructure that doesn't fit the serverless model well. An LLM with a good prompt may be "good enough" and fits the architecture perfectly.
- **The optional post-processing pattern is reusable.** Let the user configure an LLM prompt for cleanup/formatting, store it client-side, send it with the request. Simple, flexible, no server state.
- **R2 event triggers are valuable for async pipelines.** Even though they weren't used in the MVP, the pattern of "upload audio -> automatically transcribe" is the right eventual architecture for batch or background processing.

## Tech Stack Reference

- Nuxt 4 (Vue 3) + Nuxt UI + Tailwind CSS
- Nitro server engine, H3 HTTP framework
- Cloudflare Workers, D1, R2, Workers AI
- Whisper (`@cf/openai/whisper`), Llama 3.1 8B (`@cf/meta/llama-3.1-8b-instruct`)
- Wrangler v3 for dev/deploy
