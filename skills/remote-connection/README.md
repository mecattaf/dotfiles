# Remote connection — thin-client → coordinator

Reach the coordinator node (`coordinator`, tailnet IP `10.77.0.1`,
login `tom`) from another box (the `worker` node or the `zenbook-duo`
thin-client) over Tailscale, using `kitten ssh` end-to-end.

Tailscale is just the network here — it gives both machines a stable
`10.x.x.x` IP and a MagicDNS name. The actual SSH connection is plain
OpenSSH on port 22; `kitten ssh` is a thin wrapper that adds kitty
terminfo, shell integration, graphics protocol passthrough, and
clipboard.

## Daily use

```sh
sudo tailscale up                        # only if the box isn't on the tailnet
kitten ssh tom@coordinator
```

First time: type the `tom` login password when prompted. After step
"Going passwordless" below, no password.

## Attaching a session (zmx) — the primary workflow

Day to day you don't use a bare `kitten ssh` shell (it dies on
disconnect and loses state). Instead, every terminal on the
`coordinator` is a persistent **local zmx session**, and you attach
one over `kitten ssh`. zmx supersedes the old shpool setup; persistence
is entirely server-side.

```sh
kitten ssh coordinator -t zmx attach <session>   # attach an existing session
kitten ssh coordinator -t zmx a <session>        # short form
```

kitten ssh (over the tailnet) gives kitty terminfo, the graphics
protocol, and clipboard reliably while attached — unlike a raw `ssh` +
`zmx`. There is **no UDP roaming** (that was zmosh's addition, and zmosh
is unmaintained; zmx is local-only): if the network drops, the client
dies but the session keeps running on the coordinator — just re-run the
keybinding to re-attach, with full scrollback/state intact. In niri:

- **Mod+Shift+Return** → `desk`: fresh session (timestamp name; `zmx
  attach` creates it)
- **Mod+Ctrl+Shift+Return** → `desk-resume`: fzf-pick one of the
  coordinator's live sessions (`zmx list --short` over ssh), then attach
  over kitten ssh

The seam: any box on the tailnet recovers any terminal session —
terminal windows behave like browser tabs, with full session state.
`zmx` must be on `PATH` on the coordinator (it is — `home.packages`);
the client only needs `kitten ssh`.

## Going passwordless (do this once, after first login)

The coordinator has an empty `~/.ssh/authorized_keys` ready to receive
keys.

```sh
# on the client, generate a key if you don't have one:
test -f ~/.ssh/id_ed25519 || ssh-keygen -t ed25519 -C "tom@mesh"

# push it over the password-authenticated session:
ssh-copy-id tom@coordinator
# or:
cat ~/.ssh/id_ed25519.pub | kitten ssh tom@coordinator \
  "cat >> ~/.ssh/authorized_keys"
```

Reconnect — should be passwordless.

## (Optional) SSH config alias

In `~/.ssh/config` on the client:

```
Host desk
    HostName coordinator
    User tom
```

Then just `kitten ssh desk`.

## Troubleshooting

- **`ssh: Could not resolve hostname coordinator`.** The client isn't
  on the tailnet, or MagicDNS is off. `tailscale status | grep
  coordinator` should show the host with no `offline` suffix.
  Falling back to the raw IP (`kitten ssh tom@10.77.0.1`) bypasses
  MagicDNS for a quick test.
- **`Permission denied (publickey,...,password)` and no password
  prompt.** SSH gave up on password auth. Force it:
  `kitten ssh -o PreferredAuthentications=password tom@coordinator`.
- **Coordinator offline in `tailscale status`.** It rebooted, lost
  network, or someone unplugged it. Nothing on the client will fix that.
- **Garbled output, missing colours.** You're using plain `ssh` not
  `kitten ssh`, or you're SSH'ing in from a non-kitty terminal.
  `export TERM=xterm-256color` for that session.

## Coordinator state (for reference / reproducing on another box)

Already in place on `coordinator`:

- `sshd` active + enabled, listening on :22, `PasswordAuthentication`
  effectively yes (default)
- `tailscaled` active + enabled, hostname `coordinator`
- `tom` has a login password set
- `loginctl enable-linger tom` set (user processes survive logout —
  this is what keeps zmx's per-session daemons alive so they can be
  re-attached over kitten ssh later)

One change made during prep:

- Created `~/.ssh/` (mode 700) and empty `~/.ssh/authorized_keys`
  (mode 600) so `ssh-copy-id` has somewhere to append.

Tailscale SSH (`RunSSH`) is **off** and stays off — not needed for
`kitten ssh`.
