# Client audio and AirPods

F9 opens Imagine's native paired-route menu. It offers laptop audio and any
connected or paired AirPods. Both routes prefer the iContact USB camera
microphone, falling back to the laptop microphone. Selecting a disconnected
paired AirPods entry reconnects it and resolves its new PipeWire nodes before
changing either default. Selection unmutes the chosen devices and preserves
volume. INZONE and Creative routes and their device-specific rules are retired.

AirPods are found through current BlueZ pairing records and PipeWire device
identity/name, without a configured Bluetooth address, node ID or USB port.
Renamed known Apple models are recognized by their product identifier. New
models named AirPods remain discoverable even before the product table grows.
A replacement pair must first be paired normally through Bluetooth settings.

`hosts/client/airpods.nix` installs the pinned `podpower` package. It performs a
bounded BLE scan and emits JSON. Imagine requests it while F9 is open; it does
not delay output switching, add a permanent daemon, start a systemd timer,
restart Bluetooth, or change existing keyboard/trackpad bonds. Refresh updates
route availability and battery readings. While the menu remains open, battery
readings refresh every 15 seconds.

Battery values are coarse nearby BLE estimates, not exact percentages or an
authenticated per-device channel. A dynamic model filter restricts the scan to
the connected AirPods model. More than one connected pair of the same model is
reported as ambiguous; the same nearby reading is never assigned to both.
Nearby unpaired AirPods of the same model can still be indistinguishable. The
menu labels the estimate, scan time and charging state. Missing components and
failed scans remain unknown; no previous percentage is carried into a new
failed scan. Disconnected devices do not receive a nearby battery reading.
Opening the case nearby can make missing case/bud advertisements available.

The small package patch validates plaintext proximity packet headers, adds
AirPods 4 ANC and USB-C Max recognition, aligns charging flags with the
left/right orientation used by AirStatus/GNOME, and adds a model filter and
five parser tests. It keeps podpower's command-line JSON shape.

Donors and recovered notes:

- [t4t5/podpower](https://github.com/t4t5/podpower/tree/58202c955851f4517dda13c3c19bf29c21b2b828): pinned CLI/decoder base.
- [maniacx/Airpod-Battery-Monitor](https://github.com/maniacx/Airpod-Battery-Monitor/blob/GNOME45/lib/airpodService.js): frame validation, model coverage and charging/orientation comparison.
- [SleepyScribe/AirStatus](https://github.com/SleepyScribe/AirStatus/blob/master/main.py): component, unknown and charging semantics.
- [OMGUbuntu article](https://www.omgubuntu.co.uk/2024/02/see-airpods-battery-levels-in-ubuntu): Tom's original reference.
- Notes `journal/2026/11/10/design-agency-firstpass/wikis/imagine-shell/functional-map/atlas-011-bluetooth-state-and-device-visibility.md`
  and `references/devlogs/1h26/april-webshell-refs/ANNOTATED-feature-matrix.md`
  recover Bluetooth battery, codec and RSSI as earlier SHOULD features.
  This change implements the requested route/battery scope; it adds no signal
  tracker, ANC controls or separate shell application.

Shift+F9 retains the native call recorder. It captures the currently selected
output monitor and microphone, saving separate far/near tracks and their mix,
then using the existing verified NAS handoff and diarization trigger. Select
the audio pair before starting and keep it connected during the call.

Validation uses synthetic route/decoder fixtures and fake capture processes
under `runtime-test`; the agent never starts a real microphone recording.
An isolated installed Domicile builder checks the composed native menu.

## Live overlay and durable rollout

The urgent user-requested shell-only overlay is in
`~/.local/state/domicile/audio-call-20261117` on the client. Its
`previous-links.json` records the original managed links. The AirPods menu
revision is in `~/.local/state/domicile/airpods-20261117` after deployment.
The immutable battery package is copied into the client store and linked into
that overlay. The Nix source/module is in PR #774; Home Manager activation
replaces these temporary managed-link overrides. Do not activate a generation
that predates this change during a live call. No engine, Herdr, user manager,
greetd or Bluetooth restart is part of the shell update.
