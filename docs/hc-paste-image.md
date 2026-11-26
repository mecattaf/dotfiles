# Clipboard images in NAS hc terminals

The Zenbook owns Kitty and its Wayland clipboard. Codex, Claude Code and
OpenCode run on the headless NAS in hc terminals. Their direct clipboard
reads cannot access the Zenbook; setting DISPLAY on the NAS does not supply
that missing transport.

Kitty maps Ctrl+V in windows marked with hc_addr to hc-paste-image. The helper
reads a supported image from the local Wayland clipboard, validates its
signature and 32 MiB limit, writes it over the pinned NAS SSH connection, then
inserts the NAS path as a bracketed paste. It never sends Enter or submits a
prompt. When no image is present, the original Ctrl+V reaches the program.
Other windows retain their normal bindings.

Codex 0.169.0, Claude Code 2.1.331 and OpenCode 1.19.6 recognize pasted image
paths as attachments. The common transport is independent of their harness.
DSH's installed headless runner has no interactive image-paste handler; it
requires structured attachment input separately.

## File and window ownership

Files are staged under /tmp/hc-paste-<uid> on the NAS, in a verified 0700
user-owned directory. Image files are exclusive creations with mode 0600;
symlinked directories/files and pre-existing file names are refused. They
follow fleet /tmp retention and are not deleted when the source window closes.
Nothing is written under the source checkout or the notes journal.

hc-station writes Kitty's hc_addr user variable before attaching. The helper
checks the exact Kitty window and hc address again after the upload; it
refuses to insert into a different attachment. It does not pick a window by
focus or title after the asynchronous transfer.

## Old Herdr and the current hc path

Herdr v1's laptop-side remote client read the local clipboard, sent the image
to its server and bracket-pasted the staged path. The old projector explicitly
warned that running that client on NAS through plain SSH lost this capability.
The current hc route uses plain SSH to hc attach on NAS. hc forwards keyboard
and terminal data but does not read the Zenbook's clipboard for the harness.
This helper restores that client-side step while retaining vanilla hc.

Kitty's clipboard kitten also supports image reads across SSH, but Codex's
native Ctrl+V handler uses its local platform clipboard instead of that
protocol. No global remote clipboard-read permission is needed here.

## Verification

Run helper tests through runtime-test:

    ~/.local/bin/runtime-test -- python3 -m unittest discover -s tests/hc-station -p test_paste_image.py

They verify upload and bracketed-paste routing, unchanged no-image behavior,
failed uploads, malformed image data and attachment changes during upload.
End-to-end runtime qualification and deployment receipts belong in the
current UX investigation, with real user sessions preserved.
