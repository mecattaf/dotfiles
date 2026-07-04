# First things to do on new device setup

```
        sign in with google chrome
        signin with gh
        signin with tailscale
        signin with cloudflare
        curl -fsSL https://claude.ai/install.sh | bash
```
possibly use flatpak manager to enable from the start


Then setting up the whisperlivekit:
```
  # should be already done automatically
  # loginctl enable-linger $USER
  systemctl --user daemon-reload
  systemctl --user enable --now asr-toolbox


```

## USB cam-mic capture gain at boot

The iContact Camera Pro USB webcam (`lsusb` ID `1bcf:2d3e`) doubles as the
default mic. On cold-plug the device's hardware **Mic Capture Volume** comes
up at `0/4096` even though the capture switch is `on` and PipeWire makes it
the default source. Result: every app records pure silence and Claude Code's
hold-space voice input reports "no audio detected, check microphone access".

Diagnose:
```
arecord -l                                  # find iContact card number
amixer -c <card> cget numid=3               # values=0 → that's it
```

Fix at runtime:
```
amixer -c <card> cset numid=3 1024          # 25% / ~4dB; tune to taste
```

Persistence is unsolved on Silverblue: `sudo alsactl store` fails because
`/var/lib/alsa/` doesn't exist in the immutable image. If the gain doesn't
survive reboot, the robust fix is a WirePlumber rule keyed on the device
name that sets capture volume on appearance — works across reboots and USB
re-plug, no writable host state needed.



Below find instructions for navidrome and immich quadlets

  # Reload so systemd picks up the new quadlet files
  systemctl --user daemon-reload

  # Navidrome
  systemctl --user start navidrome

  # Immich (starting immich-server pulls in postgres, redis, network automatically; ml
  is a soft dep)
  systemctl --user start immich-server

  # Optional: enable so they start on login
  systemctl --user enable navidrome
  systemctl --user enable immich-server

  Before first start, change DB_PASSWORD=changeme to a real password in both
  immich-postgres.container and immich-server.container (they must match).

  You can check status with:
  systemctl --user status navidrome
  systemctl --user status immich-server immich-postgres immich-redis immich-ml

  And the web UIs will be at:
  - Navidrome: http://localhost:4533
  - Immich: http://localhost:2283

