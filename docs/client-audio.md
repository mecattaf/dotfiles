# Client audio and AirPods

F9 opens Imagine's native paired-route menu:

- AirPods output and their own microphone.
- Laptop speakers and the iContact USB camera microphone, when available.

Laptop speakers and the laptop microphone are the automatic fallback when
neither external option is available; this fallback is not a menu choice.
Selecting disconnected paired AirPods reconnects them and resolves their new
PipeWire nodes before changing either default. Selection unmutes the chosen
devices and preserves volume. SOF/UCM cards that publish separate headphone and speaker profiles
are switched to the advertised speaker profile, then their new nodes are
resolved before selection. INZONE and Creative routes are retired.

Connecting paired AirPods automatically selects their output and microphone,
then shows a brief confirmation in Imagine's existing media notice slot. One
BlueZ signal subscription reuses Domicile's existing D-Bus transport. There is
no connection polling, new daemon, service or timer. Unrelated Bluetooth,
volume and battery updates preserve a manual audio selection. Disconnecting
the AirPods restores laptop speakers with the camera mic when available,
otherwise the laptop microphone. WirePlumber's headset-profile autoswitch is
declared for applications that open the AirPods microphone.

AirPods are found through current BlueZ pairing records and PipeWire device
identity/name, without a configured Bluetooth address, node ID or USB port.
Renamed known Apple models are recognized by their product identifier. New
models named AirPods remain discoverable even before the product table grows.
A replacement pair must first be paired normally through Bluetooth settings.

`hosts/client/airpods.nix` installs the pinned `podpower` JSON reader. The F9
menu requests battery notifications directly from the connected AirPods over
their paired AAP L2CAP channel. It does not depend on nearby BLE case broadcasts
or opening the case. There is no Refresh control: readings update automatically
every 15 seconds while the menu is visible, and stop when it closes. Missing
components, including an unavailable case, remain “not reported”; failed reads
never reuse old percentages. The direct channel is addressed to the current
connected pair, so multiple pairs do not share a nearby estimated reading.

The small package patch adds the bounded connected-device reader and seven
parser tests while retaining podpower's CLI/JSON structure. The optional BLE
parser also receives plaintext-header, model-coverage and charging fixes from
the supplied donors; the menu uses the direct channel. Real battery reception
still requires physical verification with connected AirPods; no percentage was
received while the pair was disconnected during implementation.

Donors and recovered notes:

- [t4t5/podpower](https://github.com/t4t5/podpower/tree/58202c955851f4517dda13c3c19bf29c21b2b828): pinned CLI/decoder base.
- [maniacx/Airpod-Battery-Monitor](https://github.com/maniacx/Airpod-Battery-Monitor/blob/GNOME45/lib/airpodService.js): frame validation, model coverage and charging/orientation comparison.
- [SleepyScribe/AirStatus](https://github.com/SleepyScribe/AirStatus/blob/master/main.py): component, unknown and charging semantics.
- [LibrePods AAP definitions](https://github.com/librepods-org/librepods/blob/main/docs/AAP%20Definitions.md): connected-device channel and battery frame format.
- [Voltaic](https://github.com/jcfs/voltaic/blob/main/voltaic/airpods.py): direct battery reader comparison.
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
that overlay. The corrected native config links directly to the checked Nix
config/source pair; `corrected-links.json` in the overlay records those
links and the battery binary. The Nix source/module is in PR #774; Home Manager activation
replaces these temporary managed-link overrides. Do not activate a generation
that predates this change during a live call. No engine, Herdr, user manager,
greetd or Bluetooth restart is part of the shell update.
