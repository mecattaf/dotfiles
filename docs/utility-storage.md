# Utility storage

Paper, speech and recording paths are host-local data. Set their absolute roots
in `$XDG_CONFIG_HOME/utility-storage/paths.json` (normally
`~/.config/utility-storage/paths.json`) with the keys `paper`, `speech` and
`recordings`. Keep this file private and outside the checkout. Missing entries
default to `$XDG_DATA_HOME/utility-data/<kind>`.

`utility-path paper`, `utility-path speech` and `utility-path recordings` resolve
those settings. The environment variables `PAPER_ROOT`, `SPEECH_ROOT` and
`RECORDINGS_ROOT` override individual values for a process. `UTILITY_STORAGE_CONFIG`
selects a different configuration file for isolated tests.

The NAS owns durable inputs and receipts. Print rendering, speech synthesis and
recording diarization run on compute. Audio capture and playback remain on the
physical seat. Producers on another host resolve the NAS setting over SSH;
they must not resolve their own local path and assume it matches the NAS.

Home Manager prepares private watcher drop-ins for the NAS. After changing
settings by hand, wait for active utility jobs to finish, stop only the two
utility path units, move the complete storage trees, then run:

```sh
utility-path --prepare --watch paper --watch speech
systemctl --user daemon-reload
systemctl --user start paper-daemon.path speech-queue.path
```

The drop-ins reset the packaged path before adding the configured intake, so
there is only one watched root per queue. Existing jobs, receipts and queue
states move together; changing the configuration does not migrate them.
Do not restart an active print or speech job during migration. Speech's existing
06:05 quiet-hours release now belongs to the NAS along with its queue; compute
keeps synthesis and model state.

Closed call recordings are uploaded to the NAS and checked by SHA-256 before
the client spool is removed. The NAS starts a detached dispatch unit. Its worker
uses private compute scratch, returns outputs while preserving source audio,
and removes scratch after a successful return. Failures preserve the durable
NAS input and report the retained compute scratch in the recording's log.
