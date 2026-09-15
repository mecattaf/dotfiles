#!/usr/bin/env bash
set -euo pipefail
if [[ $# -eq 1 && "$1" == --help ]]; then
  printf '%s\n' 'Usage: speech-listening-cue' 'Play the preserved Claude voice-entry cue once on the Zenbook. No microphone access.'
  exit 0
fi
if [[ $# -ne 0 ]]; then
  printf '%s\n' 'speech-listening-cue takes no playback or recording options' >&2
  exit 2
fi
if [[ "$(@uname@ -n)" != client ]]; then
  printf '%s\n' 'speech-listening-cue playback belongs on the Zenbook (client)' >&2
  exit 1
fi
exec @pwPlay@ --properties '{"node.name":"speech-listening-cue"}' --media-role Notification --latency 50ms @cue@
