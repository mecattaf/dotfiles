# Remote connection — laptop → harness-desktop

Reach the work desktop (`harness-desktop`, tailnet IP `100.80.56.77`,
login `tom`) from the home laptop (`harness-xps`) over Tailscale, using
`kitten ssh` end-to-end.

Tailscale is just the network here — it gives both machines a stable
`100.x.x.x` IP and a MagicDNS name. The actual SSH connection is plain
OpenSSH on port 22; `kitten ssh` is a thin wrapper that adds kitty
terminfo, shell integration, graphics protocol passthrough, and
clipboard.

## Daily use

```sh
sudo tailscale up                        # only if laptop isn't on the tailnet
kitten ssh tom@harness-desktop
```

First time: type the `tom` login password when prompted. After step
"Going passwordless" below, no password.

## Going passwordless (do this once, after first login)

The desktop has an empty `~/.ssh/authorized_keys` ready to receive
keys.

```sh
# on the laptop, generate a key if you don't have one:
test -f ~/.ssh/id_ed25519 || ssh-keygen -t ed25519 -C "harness-xps"

# push it over the password-authenticated session:
ssh-copy-id tom@harness-desktop
# or:
cat ~/.ssh/id_ed25519.pub | kitten ssh tom@harness-desktop \
  "cat >> ~/.ssh/authorized_keys"
```

Reconnect — should be passwordless.

## (Optional) SSH config alias

In `~/.ssh/config` on the laptop:

```
Host desk
    HostName harness-desktop
    User tom
```

Then just `kitten ssh desk`.

## Troubleshooting

- **`ssh: Could not resolve hostname harness-desktop`.** Laptop isn't
  on the tailnet, or MagicDNS is off. `tailscale status | grep
  harness-desktop` should show the host with no `offline` suffix.
  Falling back to the raw IP (`kitten ssh tom@100.80.56.77`) bypasses
  MagicDNS for a quick test.
- **`Permission denied (publickey,...,password)` and no password
  prompt.** SSH gave up on password auth. Force it:
  `kitten ssh -o PreferredAuthentications=password tom@harness-desktop`.
- **Desktop offline in `tailscale status`.** It rebooted, lost network,
  or someone unplugged it. Nothing on the laptop will fix that.
- **Garbled output, missing colours.** You're using plain `ssh` not
  `kitten ssh`, or you're SSH'ing in from a non-kitty terminal.
  `export TERM=xterm-256color` for that session.

## Desktop state (for reference / reproducing on another box)

Already in place on `harness-desktop`:

- `sshd` active + enabled, listening on :22, `PasswordAuthentication`
  effectively yes (default)
- `tailscaled` active + enabled, hostname `harness-desktop`
- `tom` has a login password set
- `loginctl enable-linger tom` set (user services survive logout —
  matters for shpool and similar)

One change made during prep:

- Created `~/.ssh/` (mode 700) and empty `~/.ssh/authorized_keys`
  (mode 600) so `ssh-copy-id` has somewhere to append.

Tailscale SSH (`RunSSH`) is **off** and stays off — not needed for
`kitten ssh`.
