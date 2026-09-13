# chrome-stream

Chrome runs on the coordinator without a compositor. A web page on the Client
laptop displays CDP screencast frames and forwards mouse, wheel, keyboard and
paste input. The toolbar has an address field, history, reload, a tab selector
and a new-tab button. JavaScript alerts, confirmations and prompts appear in
the viewer. One viewer controls the browser at a time.

## Control an already running graphical Chrome

In that Chrome, open `chrome://inspect/#remote-debugging` and enable remote
debugging. Then run `chrome-stream --attach` on the coordinator and accept
Chrome's connection dialog. The launcher can also be started first: it waits
up to ten minutes for authorization. The link is written to
`~/.local/share/chrome-stream/live/viewer-url`; use the same SSH tunnel and
Client Chrome command below with that path. Stop any other viewer on port
4780 first, or choose another `--port` and tunnel that port.

This attaches to the actual visible browser and its current profile. It does
not copy a profile, launch Chrome, restart Chrome, or close Chrome when the
viewer stops. Chrome displays its normal remote-control banner. Revoking
remote debugging in Chrome disconnects the viewer. The selected tab's page
viewport is set to 1440 × 900 while attached.

## Start a separate headless Chrome

Build from dotfiles:

```sh
nix build .#chrome-stream
systemd-run --user --unit=chrome-stream-nayla --collect \
  --property=TimeoutStopSec=25 \
  "$PWD/result/bin/chrome-stream" --profile 'Profile 2' \
  --url https://dash.cloudflare.com
```

The coordinator's package list also includes `chrome-stream` for the next
normal NixOS activation. A system rebuild is not needed to use the build above.

On the Client laptop:

```sh
systemd-run --user --unit=chrome-stream-tunnel --collect \
  ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
  -L 127.0.0.1:4780:127.0.0.1:4780 coordinator
google-chrome-stable --app="$(ssh coordinator cat \
  /home/tom/.local/share/chrome-stream/Profile-2/viewer-url)"
```

The link contains a per-launch access token. The viewer stores it in the tab's
session storage and removes it from the address bar. CDP and the viewer bind
only to loopback; SSH carries the connection. WebSockets require both the token
and the viewer's origin. No firewall changes or public endpoint are needed.
Reload the viewer link after restarting the coordinator process, since its
token changes. Use Reconnect after a temporary tunnel interruption.

The first launch copies the selected Chrome profile and `Local State` to
`~/.local/share/chrome-stream/Profile-2/chrome`, excluding disposable caches.
It refuses a live source profile. Later launches reuse the copy, so browser
changes persist there. They are not synchronized back to the original profile.
Chrome uses the existing user's D-Bus session and gnome-libsecret keyring.
It retains its sandbox. Cookie validity and website compatibility depend on
the profile and site; this viewer lets the person at the laptop interact with
whatever Chrome renders, including login and verification pages.

This streams the page viewport. Browser settings windows, extension UI, file
pickers, audio/video streaming, clipboard copy from remote to local, and
download transfer are not implemented. Plain-text paste into the remote page
works with Ctrl+V. Downloads remain on the coordinator.

Stop on the coordinator:

```sh
systemctl --user stop chrome-stream-nayla
```

Stop the tunnel on the Client:

```sh
systemctl --user stop chrome-stream-tunnel
```

These are transient user services and do not restart after reboot. The copied
profile persists. Chrome's log is beside it in `chrome.log`; the bridge's output
is in `journalctl --user -u chrome-stream-nayla`.

Integration check (requires Bun, Python and Chrome on PATH):

```sh
bun pkgs/chrome-stream/smoke.js
```

The check uses disposable profiles and two actual Chrome processes. It verifies
token/origin rejection, rendered frames and mouse, keyboard, wheel and new-tab
input through the actual viewer. It does not touch the user's profile.

Protocol references: [Page screencasting](https://chromedevtools.github.io/devtools-protocol/tot/Page/#method-startScreencast),
[input events](https://chromedevtools.github.io/devtools-protocol/tot/Input/),
[Chrome's dedicated debug-profile requirement](https://developer.chrome.com/blog/remote-debugging-port).
