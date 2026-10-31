# Browser downloads on the agent host

`downloads-mirror` runs on the NAS and pulls completed downloads from the client
over the existing OpenSSH connection. Both ends resolve `XDG_DOWNLOAD_DIR` from
their own `user-dirs.dirs`; the file is parsed as data, never sourced. The helper
refuses an unset location, the home directory and the filesystem root.

```
downloads-mirror --dry-run
downloads-mirror
downloads-mirror --background
downloads-mirror --status
```

The source is the SSH alias `client`, overridable with `--source`. Batch mode,
existing host keys and no agent forwarding are required. Browser temporary files
(`.crdownload`, `.part`, `.partial`, `.tmp` and Chromium temporary entries) are
excluded. Symlinks escaping the source tree are skipped.

Transfers use rsync with protected arguments, resumable partials and atomic final
replacement. This uses rsync instead of rclone because rclone's failed local
temporary downloads are deleted; rsync can retain and resume their bytes. The
copy never deletes NAS-only files. An existing destination file replaced by the
source is saved under the private state directory before replacement.

The client has a reactive directory watcher. Its path is resolved from the local
XDG file during activation and stored in a private systemd drop-in, rather than
hardcoding a desktop path in the unit. A completed browser download normally
renames its temporary file, raising the directory event. The client notifies the
NAS over SSH; the NAS starts a detached pull. Multiple events during a transfer
coalesce into another pass. This is event handling, with no timer or polling
schedule. An offline receiver leaves client files intact; the next directory
event or the Substrate routine catches up.

Receipts and transfer logs live below `$XDG_STATE_HOME/downloads-mirror` (normally
the standard local state directory). `status.json` is the latest receipt, while
`runs/` retains each attempt. A lock prevents overlaps. An offline client,
vanished source file or bounded transfer timeout is a recorded deferral; other
errors fail the command. A later invocation retries retained partials. Nothing
deletes retained versions, logs or partials automatically.

## Substrate recurrence

Substrate owns the clock. There is no timer, cron entry, login loop or new
scheduler in dotfiles. Register a routine against a dedicated Projects session
using the existing Floor trigger API, with this five-field schedule:

```
*/5 * * * *
```

The narrow routine prompt is:

> Read `downloads-mirror --status` on the NAS, then run
> `downloads-mirror --background` once. Record the previous receipt and the launch
> result. A launch is accepted work, not a completed copy; completion is proved
> only by a later transfer receipt. A deferral or busy lock ends this turn; do not
> bypass it or start a second transfer. Do not edit code,
> download files from the browser, delete material, create another schedule,
> change credentials, deploy or restart services.

Choose an available supported runner through the current model catalog. The
routine's metadata belongs to Substrate's runtime state, so its registration
survives the scheduler's hosting move without adding another clock. Before
claiming recurrence works, verify an actual scheduled turn and its matching
completed or deferred transfer receipt. A registered trigger or a merged PR
alone is insufficient when the executor or capacity publisher is unavailable.

Both hosts need the helper from the same generation before the first run.
The Nix package pins Python, SSH and rsync; activation and the notification unit
invoke the packaged executable directly. Peer commands use the stable NixOS
per-user profile, so they do not depend on the remote shell's PATH. Detached
workers retain the same pinned interpreter and transport paths.
The receiver and source use the existing fleet SSH keys; no key is copied or
embedded in the Nix store.

References: [rsync transfer options](https://download.samba.org/pub/rsync/rsync.1),
[rclone temporary downloads](https://rclone.org/docs/#inplace).
