# Console trial on the running kernel

This route tests Domicile on the kernel already running on the physical seat.
It performs no NixOS activation, reboot, kernel replacement or boot selection.
The recorded Zenbook facts from 2026-11-04 show `uname -r` = `7.2.10`;
the current generation instead names 7.3. Use the running-kernel measurement.

**The cached engine's ABI is unsupported against the unfinished native work.**
The launcher/config/helper validation below does not qualify that engine.
Integrate the matched engine package and the apps helper's
`DOMICILE_DESKTOP_CLIENT_CONFIG` support, rebuild this trial, and use the newly
returned store path for the supervised physical round. The source-package
override flows through `programs.domicile.package` into session, recovery and
trial; the Nix evaluation test also checks this with a symlink package override.

## Build and stage

On NAS, keep the harness and SSH credentials there and run the build on compute:

```sh
fleet-exec strix-coordinator --cwd <compute-checkout> -- bash -lc '
  set -e
  df -h /
  test "$(df --output=avail -B1 / | tail -n1)" -ge 26843545600
  nix build --no-link --print-out-paths \
    .#nixosConfigurations.client.config.programs.domicilePhysical.sessionPackage \
    .#nixosConfigurations.client.config.programs.domicilePhysical.recoveryPackage \
    .#nixosConfigurations.client.config.programs.domicilePhysical.trialPackage
'
```

The third path contains `bin/domicile-console-trial`. It depends on the checked
TSX, candidate helper directory and neutral desktop-client config. It puts the candidate's immutable Home Manager profile and fish ahead of the
seat's installed profile, so Kitty, Chrome and Nautilus use the reviewed package
versions even without activation. Both the candidate Domicile share and immutable Home Manager profile share
are visible through XDG_DATA_DIRS, so the new launcher entries are available
without Home Manager activation. It carries candidate `DOMICILE_*` native
flags directly from declared system/home session variables.

After the matched candidate is reviewed, stage its closure from NAS as a
separate step. This is a store copy; it does not activate a system:

```sh
nix copy --from ssh://strix-coordinator --to ssh://client <trial-store-path>
```

No client copy was performed by this implementation task.

## Human physical sequence

With Tom present, first confirm a fresh physical console login and the password
that will be used for getty/agreety. Verify that login while Sway is still
available, then return to Sway; do not log out into an unverified login path.
Password setup is deferred to that attended step; this run never read ~/pass.
The current-kernel console trial requires no rescue-entry installation or EFI
write. The separate named rescue entry protects a later boot-based transition.

1. Save desktop work and close the old Chrome windows/profile before logging out
   of Sway; a surviving same-profile Chrome process could receive the new launch. On the Zenbook, press Meta+Shift+Return for its local
   Kitty/fish terminal. Run `hostname` and `uname -r`. Expect `client`
   and `7.2.10`; stop if they differ from the intended trial kernel.
2. From that local terminal, run `swaymsg exit` to log out of Sway.
   Do not restart greetd or stop the user manager.
3. Physically press Ctrl+Alt+F2 (or another free getty VT) and obtain a fresh
   login as Tom. Use that console's real PAM session; an SSH shell is refused.
4. Run `hostname`, `uname -r`, `tty`, and
   `printf '%s %s\\n' "$XDG_VTNR" "$XDG_SESSION_ID"`.
   Verify the same running kernel and that this is the physical getty session.
   If a getty shell was already open, exit it and log in anew first.
5. Execute the exact staged artifact:
   `exec <trial-store-path>/bin/domicile-console-trial`.
   **Do not wrap this human physical command in runtime-test.** Its isolated
   /dev and namespaces intentionally prevent acquisition of the real DRM seat.
6. The trial loads the login shell once, then re-establishes its candidate
   helper PATH. It leaves HOME and XDG_CONFIG_HOME unchanged so ordinary
   Chrome uses the usual personal profile. The exact checked TSX path goes
   to preflight and to upstream `--config`. It refuses an active Sway or
   listening Domicile desktop before changing the user-manager environment.
7. Test the physical display/input and local terminal paths at the keyboard.
   NAS attachment is a separate, explicit action in the terminal helper.
   Native-input correctness, rendered app pixels and engine ABI compatibility
   require observations from this physical round; package builds cannot prove them.

The wrapper remains an exec chain under the getty login in this route.
Upstream owns the DRM session, its component supervision and graphical targets.
The normal greetd command and Sway default stay unchanged. Copying this package
does not install PAM, systemd user units or portal configuration into the
running system. Upstream's graphical-session registration is best effort when
its targets are unavailable; this trial does not establish a fully activated
Domicile system. Preserve those diagnostics for the later integration round.

## Exit, rescue and re-entry

From a trial terminal, use `domicile-recover exit`. If the shell has no working
keys, physically switch to a separate getty VT and use the recovery package
path returned by the build:

```sh
<recovery-store-path>/bin/domicile-recover status
<recovery-store-path>/bin/domicile-recover --socket <exact-socket-from-status> rescue
# Or gracefully end that selected desktop:
<recovery-store-path>/bin/domicile-recover --socket <exact-socket-from-status> exit
```

The recovery package need not be activated to run. Ownership/executable/pidfd
checks are unchanged. Preserve the journal and any dumps. The historical cached
engine produced diagnostic dumps during shutdown and is ABI unsupported here.
Do not clear failures or restart Herdr/the user manager as a recovery step.

A getty trial ends back at the console/login; it is not greetd's child.
After it ends, return to the unchanged greetd VT1 and log into Sway normally.
To retry Domicile, obtain another fresh physical console session and execute
the same trial artifact; continue using the same running kernel.

To validate the immutable candidate from another console, take its
`DOMICILE_CONFIG_FILE` path printed at trial start and run:

```sh
DOMICILE_CONFIG_FILE=<checked-tsx-store-path> <recovery-store-path>/bin/domicile-recover check
```

An immutable candidate is corrected by a reviewed rebuild and a new store path.
A plain `domicile-recover check` without this environment variable continues to
check the ordinary XDG startup config. Rescue/status/exit do not consult it.

## Implementation validation boundary

Builds check the TSX with the actual packaged builder/config checker. The
39-test matrix retains the original 25 tests and adds actual generated trial
execution with substituted system tools, same-file forwarding, quoting,
login re-exec/PATH priority, native flag propagation, explicit-file rejection,
profile preservation, and SSH/Sway refusal. The fixture's whole generated script
is executed under runtime-test; no shell fragments or live user-manager calls.

This task did not copy to the client or run the physical command. It did not
test DRM, real input, VT restoration, PAM, the client user-manager targets,
the not-yet-integrated apps config override, or a matched native engine.
All cached-engine runtime/headless evidence remains ABI unsupported.
