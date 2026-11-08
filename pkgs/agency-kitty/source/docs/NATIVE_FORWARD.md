# Explicit native forwarding prototype

Ordinary managed direct and durable SSH attachments default to plain OpenSSH
`-tt`, with NAS-owned Kitty terminfo and fish integration. They preserve early
commands without a terminal-byte relay. The separately selectable stock SSH
kitten (`AGENCY_KITTY_SSH_TRANSPORT=kitten`) has a bootstrap data protocol that
consumes complete pre-data lines; this is distinct from Go's exit-time
`TCSAFLUSH`. See `native-ssh-qualification.md` for the focused startup gate.

`agency-kitty-native-forward` is an installed opt-in experiment. Desktop
launching and ordinary `agency-kitty` actions keep their existing behavior.
Kitty renders locally; the compiled local holder client frames input/output
through an ordinary OpenSSH Unix-socket forward to the exact retained NAS
application PTY. Python handles validation, startup and process lifetime.

This path changes SSH timing protection. OpenSSH's interactive keystroke
timing padding does not apply to Unix-forwarding traffic, even with
`ObscureKeystrokeTiming=yes` or another TTY on that connection. Encryption and
NAS host authentication remain. It is not a policy-equivalent replacement for
an interactive SSH terminal, and no latency advantage is claimed here.

Attach an explicitly identified, live NAS holder from an interactive Kitty:

```sh
agency-kitty-native-forward --session EXACT_UUID
```

An unknown, closed, direct-only or unavailable identity fails without
allocating a replacement. The local compiled client and canonical NAS holder
must have the same qualified version. The Nix package's `holderPackage`
argument supplies that binary; without one, an explicitly supplied `--client`
must name a qualified matching client. There is no fallback to another holder
or terminal transport.

Fresh provisioning is a separate explicit action. Generate a new UUID, then
choose its canonical NAS directory:

```sh
agency-kitty-native-forward --session NEW_UUID --provision-directory /home/tom/project
```

Both fleet roles must install this package and its selected holder. The NAS
command `agency-kitty-native-control` must be available to noninteractive SSH.
The wrapper declares `AGENCY_KITTY_FISH_INTEGRATION_DIR` and `TERMINFO` from its
exact Kitty package. Provisioning validates those NAS assets, sets
`TERM=xterm-kitty`, and creates the sole application PTY without a resident
sshd session PTY. Control subprocesses receive `/dev/null` as stdin so complete
commands typed during startup remain queued for the native client.

The wrapper selects `AGENCY_NATIVE_FORWARD_CONTROL=agency-kitty-native-control`.
`--control-program` can explicitly override that NAS executable for isolated
qualification; it is a remote command name, not a local store path.

The installed control entry accepts only:

```sh
agency-kitty-native-control provision --session EXACT_UUID --fleet-assets
```

It requires an already-created canonical record. It has no arbitrary command,
terminal-input, selection, session-switching or window-management endpoint.
Normal users invoke it through the native-forward command rather than typing
it into their NAS application PTY. Metadata rebind uses the existing bounded
`agency-kitty remote rebind` action and restores only typed state belonging to
the exact live session, including pending primary `vi` requests.

Closing the local view leaves its NAS application alive. NAS reboot survival
requires separate harness/editor recovery; this forwarding experiment does
not turn an in-memory PTY into persistent disk state.
