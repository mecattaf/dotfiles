# Kitty on Domicile, with NAS shells

Meta+Return creates a fresh Kitty OS window and an independent NAS fish shell.
Meta+Shift+Return opens the local rescue shell. Neither path attaches to a
Herdr pane or uses a picker, Sway IPC, Kitty control socket or synthetic input.
The normal Kitty font, theme, clipboard and Neovim scrollback settings apply.
Kitty's own new-window/new-tab actions also start fresh NAS shells, through an
instance-local `shell` override. Local rescue instances retain local fish.

The client uses its existing SSH identity, the explicit NAS Tailnet address
and NAS known-host identity. It forwards no agent or ports. Credentials and
harness processes stay on NAS. Invalid project directories fail on NAS;
connection failure remains visible and never reconnects or changes host.
Closing this shell ends it: this is ordinary SSH, without DSH-owned PTY
retention. It does not restore a DSH terminal ID, resume a conversation, or
create a server session. Existing Herdr windows retain a separate reconnect
adapter so changing the default does not strand those views.

## Open in a NAS project

On the desktop:

```sh
domicile-apps terminal --cwd /home/tom/project
```

A NAS-side DSH shell action can invoke the fixed `domicile-open-terminal`
launcher. Its explicit registry extends the existing dsh-domicile desktop
record with one trusted path:

```json
{
  "desktops": {
    "zenbook": {
      "tailnetIp": "100.121.160.100",
      "sshAlias": "client",
      "hostKeyAlias": "client",
      "terminalLauncher": "/home/tom/.local/bin/domicile-terminal-open"
    }
  }
}
```

An existing owner-only `sshConfig` may also be retained in that record; it
names the NAS SSH configuration, never copied client credentials.

```sh
domicile-open-terminal --registry /absolute/desktops.json \
  --desktop zenbook --cwd /home/tom/project
```

The client helper verifies the selected desktop against its installed
`.config/dsh-domicile/client.json`, discovers exactly one owned native IPC
socket, checks its peer UID, and calls the configured Domicile CLI with
`send-shell exec domicile-apps terminal --cwd PATH`. It starts no service or
HTTP listener. Model arguments choose neither executable nor transport route.
`launch-queued` means native delivery was acknowledged; inspect the existing
dsh-domicile snapshot to observe the resulting native window. A timeout can
leave an unknown outcome, so the launcher never retries automatically.
Window IDs and DSH session/terminal IDs remain separate.

## Validation and current limit

Run routing and launcher tests through target `runtime-test`, using
`fleet-exec strix-coordinator` and a staged checkout. All endpoints in those
unit checks are private doubles; actual desktop launches are recorded
separately. The live Mod+Return binding already points at `domicile-apps
terminal`; changing these helpers does not require a shell refresh or engine
restart. `practice.sh` and `prove_herdr.py` describe the historical Herdr menu
and do not qualify this implementation.

Kitty 0.48.0 on the current Domicile engine was observed to abort on ordinary
window teardown, with an output-list count of -1. The fleet overlay backports
upstream Kitty commit 2dbe5df2d8a7590213d76aa4ce112024602eb57d: a leave for
an absent output must not decrement the count. Retain the original dumps;
a successful fresh launch alone is not clean-close qualification. Physical
keyboard/clipboard acceptance and DSH-owned terminal attachment are separate
from this SSH-shell integration.
