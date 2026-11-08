# What Mod+Enter actually runs

A read-only audit of the live laptop on November8 at00:33UTC verified the
actual `/proc` process ancestry and executable paths. The chain is:

```
Domicile/Imagine → Kitty0.48.0 → domicile-terminal Python launcher
                → plain OpenSSH10.4p1 -tt → NAS fish
```

The launcher waits for SSH's exit status so it can display a connection-ended
message on failure. It does not read or relay stdin/stdout. OpenSSH inherits
the Kitty terminal descriptors directly. The live route contains no Herdr,
zmx, shpool or zmosh. The SSH kitten is not being used to bootstrap these
sessions. The other small `kitten` children of Kitty are not proof of an SSH
kitten; the actual SSH parent is the `domicile-terminal` launcher. One separate
SSH connection belongs to the existing chat catalogue watcher, not the typing
stream.

The exact launcher SHA256 is recorded in
`docs/evidence/live-client-baseline.json`. Its source was copied read-only to
the separate task artifacts directory for audit, without changing the client.
The current font is AnthropicMono Nerd Font at16.0. There are no explicit
input_delay/repaint_delay/sync_to_monitor overrides in the live configuration;
the production Kitty0.48 defaults apply. No Gemini timing tuning was silently
installed. Tonight's separately built Kitty0.50 cannot explain the sensation
that began while this0.48 process was already running.

## What SSH does and does not establish

The effective live SSH policy is compression off, no connection sharing,
forced TTY, strict NAS host identity at100.65.85.114, and
`ObscureKeystrokeTiming yes`. The latter has a nominal20ms interval in this
OpenSSH release. It starts with an immediate packet, then can quantize small
interactive packets while active. It is not a mandatory20ms delay on every
first key. The exact timing depends on packet size, arrival phase, idle time
and connection state. A forwarding-only connection follows different policy
gates, so its timings need a separate label.

OpenSSH itself sets TCP_NODELAY. The SSH kitten does not uniquely introduce
that optimization. Its terminfo and shell integration improve startup and
capability correctness; they are not evidence of a faster per-character
network transport. Remote shell echo normally makes a network round trip;
Kitty does not provide general predictive local echo. A parser being fast
also does not remove scheduling, SSH timing policy, GPU/compositor or panel
presentation delay.

Source: OpenSSH10.4p1
[`obfuscate_keystroke_timing`](https://github.com/openssh/openssh-portable/blob/e8dd756725e8800fcd0b3fd71ee6b4382d1e8fab/clientloop.c#L574)
and [`interactive packet policy`](https://github.com/openssh/openssh-portable/blob/e8dd756725e8800fcd0b3fd71ee6b4382d1e8fab/packet.c#L2275).
The exact plain-SSH path and its actual policy must be the reference in the
later frozen comparison. A10ms physical key-to-pixel figure has not been
measured in this session. The earlier18ms Herdr number was also unmeasured;
the isolated Herdr busy-output experiment now provides different, explicitly
software-only evidence of its repaint cadence.
