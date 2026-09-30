# Speech operations

**2026-09-30: speech-wake (the Alexa/openWakeWord listener), Parakeet, native
Herdr hold-Space dictation and the wake toggle were removed** (Tom, sweep
2026-09-30 §E). What remains is output only: the Markdown speech queue and
on-demand Qwen synthesis on the coordinator, played on either seat. The wake
and dictation history is in `mykonos-overnight-integration.md`, git history
and the NAS research archive.

## Responsibilities

The coordinator owns the Markdown speech queue (`speech-queue.{service,path,timer}`:
a path unit on `~/Speech/intake` and a 06:05 silent-hours release) and on-demand
Vulkan Qwen synthesis (`modules/qwen-tts.nix`). Either seat plays the returned
audio; the client performs no inference.

Qwen uses the accepted single midway B K2SO reference: 44.02 seconds of identity
material from six scenes, with a matched 25.20-second prefix. It is still Qwen3-TTS
1.7B Base Q8, not a fine-tuned CustomVoice checkpoint. The accepted derived profile
and its enrollment evidence are a NAS artifact, separate from model weights.
No personality instructions or tone switching are part of this deployment.

## Restore model loans

The canonical Library is on the NAS. Run `library-fetch` there to restore missing
published artifacts, then explicitly run `sudo local-models-borrow --yes` on the
coordinator, whose Library path is the existing NAS mount. This never happens
inside activation or a service startup. Locally imported K2SO material cannot be
re-downloaded: restore it from the NAS archive or backup if missing.

The K-2SO voice (`qwen-k2so-midway-b`, eight files, about 3.3 MB) is Tom's
production voice and is kept (Tom, 2026-09-16). Its canonical copy is
`/mnt/nas/models/weights/qwen-k2so-midway-b/`. The backup copy is
`/mnt/nas/documents/voice-references/qwen-k2so-midway-b/`, and its `README.txt`
records where it came from. On 2026-09-17, the canonical copy, the coordinator
loan and the backup were all checked against the sha256 `oid` pins in
`lib/speech-intake-models.json`, and every file matched. Check the backup with
`sha256sum -c SHA256SUMS` in that directory. Its `sources/` subdirectory holds
the inputs that `provenance.json` names: the six unmodified segment WAVs whose
hashes match `provenance.json`, their transcripts, the segment manifest, and
the original montage MP3 with its download provenance. Check those with their
own `SHA256SUMS`. Before this, the inputs were only in
`~/tts-reference-refinement-20260914` and the evidence tarball under
`models/research`, a tree whose fate is undecided. The `documents` tree gets a
monthly btrbk snapshot, and it is copied to the LaCie when Tom plugs that drive
in; the mirror has no timer. Mirroring alone does not make a second copy, because
the mirror also copies deletions.

## Speech output

The shared `/speak` skill asks the assistant to atomically publish Markdown in
`~/Speech/intake`. The daemon owns synthesis and playback. Hidden temporary names
must become visible `.md` names when finalized. Working hours are 06:00–24:00,
matching the paper workflow. Outside those hours jobs wait for the 06:05 release.
Receipts, rather than an assistant's queue-write claim, establish whether
playback completed. Niri Shift+F9 call recording holds playback while a call is
being recorded.

## Evidence and history

NAS listening-evidence archive (cleaned 2026-09-15):
`models/research/mykonos/2026-09-14/voice-evidence.tar.gz`, 2,661 files,
SHA256 `423d14f9346d9b6868bece7aa95842c3e8809beb24a48df90152c9590439fd95`.
The original supplied MP3 is archived beside it with its own hash manifest.
`code-cleanup-receipt.json` records removal of 3,676 code/non-evidence members
from the former archive and deletion of local experimental code and environments.
The old code-bearing archive was deleted after verifying the evidence replacement.
Earlier deployment receipts describe the archive as it existed then; this is the
current archive. Model weights have separate manifests and canonical Library paths.

Earlier Gemma, VibeVoice, CustomVoice, character and Intel NPU documents record
experiments, not active architecture. Their model weights were deleted from the
NAS Library on 2026-09-16 (Tom); VibeVoice-ASR-Streaming-7B is the one kept
diarization model.

## Commands

Operational commands: `speech-session`, `speech-projector`, `speech-play`,
`speech-queue`. Superseded NAS speech models were deleted on 2026-09-16, with a
receipt in `/mnt/nas/models/weights/RETIRED-2026-09-16.tsv`; the Parakeet and
openWakeWord rows leave the catalogue on 2026-09-30 (their Library bytes are
retired separately). The accepted K-2SO voice has a second verified copy in
`/mnt/nas/documents/voice-references/qwen-k2so-midway-b/`. CustomVoice, tone
banks and character/personality work were explicitly dropped.
