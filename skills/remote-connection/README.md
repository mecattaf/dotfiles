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

## Projecting a session (zmosh) — the primary workflow

`kitten ssh` (above) is a plain, network-fragile shell — it dies on any
IP change. Day to day you don't use it directly; you **project** a
persistent session off the coordinator with **zmosh**, which supersedes
the old shpool setup.

Every terminal on `harness-desktop` is already a persistent `zmosh`
session. From a laptop, reattach one over encrypted UDP that survives
Wi-Fi↔cellular, VPN toggles, and sleep/wake:

```sh
zmosh attach -r harness-desktop <session>   # project an existing session
zmosh a -r harness-desktop <session>        # short form
```

zmosh bootstraps over SSH (so passwordless login above still matters),
negotiates an XChaCha20 key, then switches to UDP — no reconnect, no lost
state when the network changes. In niri this is wired to keys:

- **Mod+Shift+Return** → `desk`: fresh projected session (timestamp name)
- **Mod+Ctrl+Shift+Return** → `desk-resume`: fzf-pick one of the
  coordinator's live sessions (`zmosh list --short` over ssh), then project it

The seam: any laptop on the tailnet recovers any terminal session —
terminal windows behave like browser tabs, with full session state. Note
`zmosh` must be on `PATH` on both ends (it is — `home.packages`), and
remote-session clipboard falls back to OSC52 rather than kitten ssh's
forwarding.

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
- `loginctl enable-linger tom` set (user processes survive logout —
  this is what keeps zmosh's per-session daemons alive so they can be
  reattached/projected later)

One change made during prep:

- Created `~/.ssh/` (mode 700) and empty `~/.ssh/authorized_keys`
  (mode 600) so `ssh-copy-id` has somewhere to append.

Tailscale SSH (`RunSSH`) is **off** and stays off — not needed for
`kitten ssh`.
