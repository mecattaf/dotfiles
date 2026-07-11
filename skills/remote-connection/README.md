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

## Session naming — LLM auto-titling (with deterministic fallback)

Session names are what the fzf resume picker (`zmx-resume` / `desk-resume`)
shows. The floor is a deterministic `<cwd-basename>-<HHMMSS>` (local) or
`term-<mmdd-HHMMSS>` (remote) name. On top of that floor, `~/.local/bin/zmx-title`
makes a best-effort attempt to generate a richer, human-readable title (e.g.
`🔧 fix niri clipboard`) from the coordinator's local **FastFlowLM** task model
(NPU-backed `flm serve`, model `gemma4-it:e4b`), reached over its
OpenAI-compatible HTTP API.

The titling is a pure enrichment — it can **never** break terminal spawning:

- `zmx-title <fallback-name> [context…]` prints exactly one line: a sanitized
  title on full success, or the `<fallback-name>` **byte-for-byte** on ANY
  failure (flm absent, service down, model not pulled, HTTP error, ~2s timeout,
  junk output, `curl`/`jq` missing).
- "titling off" therefore === today's shipped deterministic naming. When flm is
  not listening (e.g. on the worker / zenbook, or before the model finishes
  downloading) the attempt fast-fails in ~15 ms, so spawn latency is unchanged.
- The title is sanitized to a single safe line: reasoning `<think>…</think>`
  blocks dropped, quotes and shell/path metacharacters (`/ ; $ \` " '` …)
  stripped, a leading emoji and non-ASCII letters kept, length capped at 48.

Wired into `new-terminal` (local, on the coordinator, where flm is local) and
`desk` (remote fresh sessions). Overridable via env:

| Var | Default | Purpose |
|-----|---------|---------|
| `ZMX_TITLE` | `1` | Set `0` to disable titling (pure deterministic naming). |
| `FLM_HOST` | `127.0.0.1` | flm host. Set `coordinator` on the worker/zenbook to title fresh **remote** sessions against the coordinator's NPU. |
| `FLM_PORT` | `52625` | flm server port (`flm port`). |
| `FLM_TITLE_MODEL` | `gemma4-it:e4b` | Task model tag. |
| `FLM_URL` | `http://$FLM_HOST:$FLM_PORT/v1/chat/completions` | Full endpoint override. |
| `ZMX_TITLE_TIMEOUT` | `2` | Hard wall-clock cap (seconds). |

Requires the npu lane's `flm serve` systemd service running on the coordinator
and the `gemma4-it:e4b` model pulled (`flm list`). Until then, every session
simply keeps its deterministic name. Titling from live scrollback via
`zmx history <name>` after first activity (rather than from the cwd at creation)
is the natural next step — see issue #38.

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
