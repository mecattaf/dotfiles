# USB4/PD wedge incident — runbook and lore (2026-08-21)

The config half of this story lives in `hosts/coordinator/tb-fleet.nix`
(doctrine + automated cure) and `hosts/coordinator/eth-fleet.nix` (the
fallback rail). This doc keeps the operational knowledge that is not config:
how to recognize the states, the manual commands, and the boot behaviors
that look like failures but aren't. Recon for the project that motivated the
hardening: `docs/local-ai/ds4-vllm-recon-2026-08-21.md`.

## Recognizing the PD-blind wedge (60 seconds)

Symptoms, all at once: TB link dark, physical cable replug produces ZERO
kernel events on the affected end, rear USB-C peripherals missing from the
USB tree, `/sys/bus/thunderbolt/devices/` shows only `0-0 1-0 domain0
domain1` (no `*:2.*` retimers). Confirm with either:

    sudo framework_tool --pdports
    # wedged: every port reads "PD Contract: No / Sink / Ufp", no CC Polarity
    # healthy: the live port shows CC Polarity + a real role

or the raw PPM interrogation (UCSI debugfs):

    D=/sys/kernel/debug/usb/ucsi/USBC000:00
    for c in 0x10012 0x20012; do
      echo $c | sudo tee $D/command >/dev/null && sudo cat $D/response
    done
    # all-zeros on both connectors + 0 mV vbus_voltage = PPM alive but blind
    # = CCGx wedged. Non-zero with bit3 set = connector genuinely attached.

`sudo framework_tool --pd-info` printing "Back / Silicon ID 0x30A0 / MainFw"
proves the EC→CCGx I2C path works — the fault is state, not a dead chip.

## The cure (automated; manual form here)

    sudo framework_tool --pd-reset 2     # 2 = "Back", the only PD controller
    sleep 5
    echo USBC000:00 | sudo tee /sys/bus/platform/drivers/ucsi_acpi/unbind
    sleep 2
    echo USBC000:00 | sudo tee /sys/bus/platform/drivers/ucsi_acpi/bind

tb-link-heal runs exactly this on the PD-blind signature (rate-limited).
Gentler first try: `--pd-disable 2; sleep 3; --pd-enable 2` (bounces both
rear ports without restarting the controller). Things that provably do NOT
work: NHI unbind/rebind, PCI remove+rescan, ucsi rebind alone (its PPM_RESET
resets the mailbox, not the chip), UCSI CONNECTOR_RESET, warm reboots, and
soft power-off — the CCGx sits on standby power.

Hardware-path cure, when software is unreachable: poweroff, PULL THE MAINS
CORD, wait 60 s, boot. (The worker was healed this way.) Last resort: the
white CMOS RESET button next to the APU fan connector, held 10 s, mains out
— resets BIOS settings too (iFixit guide #193895).

## Wedge trigger and prevention

Trigger: one box power-cycling while the peer's PD stack is mid-cable-
transaction (the Vconn-source side is the vulnerable one). Practical rule:
never reboot/power-off both boxes at overlapping times; reboot one, let the
link retrain, then the other. If both must go down, expect the heal loop to
pd-reset within ~2 min per box afterward.

## Boot behaviors that LOOK like failures but are normal

- **Memory training**: after any unclean power event (forced power-off,
  mains pull), POST retrains 128 GB of LPDDR5X: LED on, fans OFF, screen
  dark, sometimes one or two SELF power-cycles, up to ~14 minutes. The
  coordinator's "14-minute dark gap" and the worker's scary LED-no-fan boot
  were both exactly this. Leave it alone for 15 minutes before touching.
- **UCSI noise**: `GET_CABLE_PROPERTY failed (-5)`, `unknown error 256`,
  `con2: failed to register partner alt modes (-5)` are BENIGN on this
  platform — present in every healthy host-to-host attach since Aug 8. The
  AMD PPM simply can't describe this cable. Error 256 = UCSI
  GET_ERROR_STATUS 0x0100 (vendor-undefined); the -5 is the same event.
- **Domain shift**: after the worker's mains-drain boot the cable enumerates
  on its domain 1 (was domain 0 pre-incident). Firmware port-role roulette;
  harmless; heal/tripwire patterns are domain-agnostic. Coordinator side is
  connector 2 = `typec/port1` = domain 0.
- **The GS3 speaker** powers itself off when VBUS blips and stays off until
  its physical power button is pressed. Not a USB problem.
- The worker auto-powers-on when AC returns (deliberate BIOS setting, for
  building power cuts). Plugging in mains IS booting it.

## Imperative state not yet declarative (recreate-by-hand list)

The `tb-fleet` NM profile itself is imperative, and the metric-50 fleet
routes were added to it by hand on BOTH boxes. If the profile is ever
recreated, re-add them:

    # coordinator
    sudo nmcli connection modify tb-fleet +ipv4.routes "10.99.9.2/32 10.99.0.2 50"
    # worker
    sudo nmcli connection modify tb-fleet +ipv4.routes "10.99.9.1/32 10.99.0.1 50"
    # then: nmcli connection up tb-fleet

(eth-fleet and the fleet /32s are fully declarative; only tb-fleet remains
imperative. Migrating it to ensureProfiles is an open, deliberate deferral —
remember the keyfile dialect: `route1=dest,hop,metric`, not `routes=`.)

## Fleet addressing quick reference

| Net | What | Coordinator | Worker |
|---|---|---|---|
| 10.99.0.0/30 | tb-fleet (thunderbolt0), fast rail | .1 | .2 |
| 10.99.1.0/30 | eth-fleet (enp191s0), fallback rail | .1 | .2 |
| 10.99.9.x/32 | fleet identity (lo), auto-failover | 9.1 | 9.2 |
| 10.42.0.x/24 | house LAN (wifi) | .2 | .5 |

SSH `Host worker` still points at 10.99.0.2; the fleet IP 10.99.9.2 is the
never-dies address (rides TB, falls to eth in <1 s, connections survive).
