# asr-rs Dictation Notch Integration

Reactive notch indicator for asr-rs (streaming speech-to-text daemon).
When dictation is active, a green mic icon appears in the notch; when inactive, it disappears.

## How it works

asr-rs writes `active` or `inactive` to `$XDG_RUNTIME_DIR/asr-rs/state` on every
state transition. Quickshell watches this file via inotify (`FileView` + `watchChanges`)
and launches/closes a notch indicator instance accordingly.

Signal flow:
```
Mod+Space → niri spawns pkill -USR1 asr-rs → asr-rs toggles state
  → writes $XDG_RUNTIME_DIR/asr-rs/state → inotify fires
  → quickshell FileView onFileChanged → launch/close Dictation notch instance
```

Latency is ~10ms end-to-end (all kernel-level, no polling).

## Affected files

### Quickshell
- `ui/components/notch/instances/Dictation.qml` — **new** notch app (indicator with green mic icon)
- `ui/components/notch/Notch.qml` — added `"dictation"` to `notchRegistry`, added `FileView` watcher for asr-rs state file

### Niri
- `niri/startup.kdl` — added `spawn-at-startup "asr-rs"` (daemon starts inactive)
- `niri/binds.kdl` — added `Mod+Space` (SIGUSR1 toggle) and `Mod+Shift+Space` (SIGUSR2 force-stop)

### asr-rs (separate repo, not in dotfiles)
- `src/main.rs` — writes `active`/`inactive` to `$XDG_RUNTIME_DIR/asr-rs/state` on every state transition

## Dependencies

- asr-rs must be installed and in `$PATH` (packaged via Fedora COPR, baked into bootc image)
- WhisperLiveKit server must be running for actual transcription (asr-rs starts fine without it, just can't activate)
- `mic.svg` icon already exists in `media/icons/notch/`
