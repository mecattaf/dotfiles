# music-acquire

`acquire` is the durable front door for the music-consolidation acquisition
cascade. It writes an immutable worklist, an append-only evidence ledger, and a
separate archive resume gate under `~/.local/state/music-acquire/<batch>/`.

```text
acquire tracklist worklist.jsonl [--source goldcast|synapson|vent-2024]
acquire soundcloud ARTIST [--likes] [--reposts] [--sets]
acquire bandcamp ARTIST [--alias "Project Pablo"]
acquire ytmusic ARTIST
acquire status [--batch NAME] [--json]
acquire resume --batch NAME
```

Global controls are `--batch`, `--dry-run`, `--limit`, `--no-capture`, and
`--out`. Final downloads always retain the source audio stream; no extraction,
format coercion, or recoding option is used. SoundCloud and YouTube cookies are
copied from agenix into the batch's mode-0600 cookie directory before use.

The calibrated fingerprint and capture engines remain in
`~/mecattaf/music-consolidation/scripts/`; set `MUSIC_CONSOLIDATION_REPO` if that
checkout lives elsewhere. Capture is dispatched to `worker` by default and can
be changed with `MUSIC_ACQUIRE_CAPTURE_HOST`.
