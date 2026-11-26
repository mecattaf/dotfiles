# hc-paste-image: images into a NAS station (design, unqualified)

2026-11-26. Script: `home/dot_local/bin/hc-paste-image`. Tests:
`tests/hc-station/test_paste_image.py` (fakes only).

## Why

Mod+Enter opens a Kitty window on the seat that is `ssh nas` running
`hc-station`, so the station and Claude Code in it run on the NAS while the
clipboard is on the seat ("transport A"). The NAS has no clipboard to paste
from. Claude Code does turn a pasted path of an image file into
"[Image #1]" (measured 21 Nov, with the path as a bracketed paste).

## How

1. `hc-station` marks its window with the Kitty user variable `hc_addr`
   (OSC 1337 `SetUserVar`) before it attaches.
2. `hc-paste-image <window id>` reads it with `kitten @ ls` (Kitty has
   `allow_remote_control yes` and `listen_on unix:@kitty-{kitty_pid}`).
3. With an image on the clipboard (`wl-paste --list-types`: png, jpeg, gif,
   webp; at most 32 MiB), one pinned ssh, using domicile-terminal's transport
   options without `-tt`, writes it as `/tmp/hc-paste-<uid>/clipboard-<time>-<hex>.<ext>`
   on the NAS: 0700 dir, 0600 file, one connection (scp could not make the dir).
4. It pastes that path into the window with `kitten @ send-text --bracketed-paste auto`.
5. Outside a station window, or without an image, ctrl+v is passed through
   unchanged (`kitten @ send-key ctrl+v`). A failed upload pastes nothing.

## Where the files go

`/tmp` on the NAS: aged out after 10 days and emptied at every boot. The files
are not removed with the station, unlike transport B's `hc put`, which puts the
file beside the station.

## To try it (not installed tonight)

No kitty map is added. To try it on the seat, add to `~/.config/kitty/kitty.conf`
(syntax not checked on Kitty 0.50.0):

```
map ctrl+v launch --type=background --allow-remote-control hc-paste-image @active-kitty-window-id
```

## Unverified

- the real clipboard on the seat (`wl-paste` under Domicile);
- `kitten @` from a background launch;
- the bracketed paste reaching Claude Code through ssh and `hc attach`;
- Claude Code turning a NAS path into an image inside a station;
- the latency of one ssh connection per paste.

## Transport B

When the seat gets its own hc with the NAS as a machine, `hc put <addr> <file>`
replaces the ssh upload, as in the 21 Nov draft
(`holder-eval/configs/hc-fresh/hc-paste-image`).
