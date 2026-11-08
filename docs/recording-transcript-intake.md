# Finished recording transcripts

Issue #488 is a completion event for finished call transcripts. After
`call-diarize-remote` successfully returns verified results to the NAS, it runs
`recording-transcript-stage CALL_DIRECTORY`. The stage command performs no
inference. Failed processing or transfer cannot publish a completion; failed
publication retains compute scratch and returns failure for an explicit retry.

The immutable local publication is
`$(utility-path recordings)/transcripts/CONTENT_ID/`. It contains the exact
`transcript.md`, `review-queue.md`, ASR `manifest.json`, and a private
`receipt.json` linking the source directory and SHA-256 hashes. The content ID
also incorporates source identity, so similarly named calls cannot collide.
Files are mode 0600 inside a mode 0700 directory. An atomic directory rename
publishes all files together. Duplicate events verify and reuse the same
snapshot; changed results create a new revision without overwriting history.

A completed transcript is not a reviewed transcript. `review_required` stays
true; the associated review queue remains visible. Publication does not send
content to cloud models, create an agent session, insert it into any active
conversation, or choose a journal/CRM destination.

For an existing finished recording or a failed publication, run
`recording-transcript-stage CALL_DIRECTORY` on the NAS. This retries staging
without rerunning ASR. The command refuses missing/empty transcripts, missing
review artifacts, unsupported/incomplete ASR manifests, symlinked artifacts,
changing source revisions and corrupt existing publications.

The existing call pipeline uses VibeVoice ASR for speech recognition and Gufo
for local text cleanup. Qwen3-TTS Base Q8 and the accepted K-2SO midway B voice
remain the speech-output path. TTS is not used as an ASR engine. This change
adds no microphone capture, wake listener, resident transcription service,
polling, systemd path unit, timer, scheduler, or new inference backend.

The NAS raw-dotfiles update carries both dispatcher and standalone publisher;
the dispatcher resolves the publisher beside its real source file, using its
current Python interpreter. This works even before Home Manager creates a PATH
link for the new file. The publisher uses the already installed utility-path
command. No profile activation is needed for that pair. Utility-storage ships the identical
publisher for the normal packaged deployment. A missing stage command is a
visible failure that retains scratch. No activation or live call processing is performed by the source
change itself; commissioning an actual call remains distinct from fixture
tests of the completion event.
