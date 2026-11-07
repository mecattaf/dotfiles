# Native Kitty editors and the Neovim remote-SSH opening

Research and candidate implementation, 2026-11-07. Nothing here activates a
generation, changes a live Kitty instance, or restarts an editor or Herdr.

The useful Neovim boundary is already available in installed Neovim 0.12.4:
one NAS editor server per canonical directory, with a native terminal UI that
can close and reattach. The candidate adds no terminal emulator, rendering
frame interval, multiplexer prefix or browser terminal. Fish waits while its
editor runs; it does not parse and redraw the editor's keystrokes.

## What the 0.13 demo actually does

The user's exact source revision,
[`893d90f`](https://github.com/neovim/neovim/blob/893d90fced480d234e8eb1c3922c2ee5f898d3e4/runtime/doc/gui.txt#L143),
supports `:connect ssh://host`. It chooses a suitable remote Nvim or installs a
release, starts an editor with the reserved `nvim-remote` app name, forwards a
Unix socket over SSH, and attaches the local UI. It does not expose a stable
per-directory server identity. Its documentation says the remote editor stops
when the connection drops. The implementation's
[`serve()` cleanup](https://github.com/neovim/neovim/blob/893d90fced480d234e8eb1c3922c2ee5f898d3e4/runtime/lua/vim/net/_ssh.lua#L651)
sends SIGTERM to the server; swap files are retained for recovery. Preserving
an editor process through disconnect is a different behavior.

The current inspected master revision is `864f78836499f8b1c7317a1b8d3762c5c4935141`.
It additionally copies the local config into `~/.config/nvim-remote` on
connection, replacing that reserved config directory. It delegates plugin
installation to the config. The cited demo revision's docs do not yet describe
that copy step. See the pinned
[current GUI lifecycle documentation](https://github.com/neovim/neovim/blob/864f78836499f8b1c7317a1b8d3762c5c4935141/runtime/doc/gui.txt#L143).

This is useful for an unfamiliar remote host or a local UI that changes remote
targets. The daily workflow already starts in a NAS shell through Kitty SSH,
with NAS files, tools and editor configuration present. Replacing that with a
second local Nvim server and an autoinstalling SSH tunnel does not itself solve
WIP persistence. No global Neovim upgrade or auto-installing `vi` redirect is
needed for this candidate. The release page currently presents 0.13 as a
[development build](https://github.com/neovim/neovim/releases); NAS and compute
were measured running 0.12.4.

The native `:detach`, `--listen`, and `--remote-ui` lifecycle is the smaller
fit. A deliberately independent headless server keeps buffers, undo history,
window layout and unnamed drafts in memory after a UI disappears. Attaching a
new terminal UI avoids replaying a terminal recording to reconstruct Nvim.

## Candidate commands and state

Run `dsh-editor --directory /absolute/NAS/directory -- file.md` inside the NAS
shell. The default directory is the current directory. Canonical directories
are separate identities, including separate git worktrees. A symlink to an
existing directory resolves to the same identity.

- `dsh-editor --socket-only --directory DIR` ensures the server and prints its
  private Unix socket.
- `dsh-editor --no-attach --json --directory DIR -- FILE...` opens files without
  attaching a UI and returns metadata for a control sidechannel.
- `dsh-editor --list --json` lists known directory identities and live status.
- Native `:detach` closes the UI while retaining the server. Native `:qall`
  intentionally stops that editor; no task kills other directory servers.

The launcher uses an independent POSIX session with no inherited terminal or
stdio pipes. The NAS was read-only verified with `KillUserProcesses=false`
and user lingering enabled. The live process still ends on a NAS reboot,
explicit termination, or a crash. Persistence of a process and recovery from
its loss are distinct claims.

Private state lives in `$XDG_STATE_HOME/dsh/editor/<directory-hash>` (default
`~/.local/state/dsh/editor/...`), not in the repository. Runtime sockets are
below `$XDG_RUNTIME_DIR/dsh-editor`. Directories are mode 0700; WIP snapshots
are mode 0600. Changed buffers, including unnamed drafts, are checkpointed
after two seconds of typing inactivity and on insert/buffer/UI transitions.
The typing callback only rearms an in-memory timer. Native swap recovery is
also enabled for these durable editors. A checkpoint is not a promise that
the last keystroke survives an immediate SIGKILL or power loss.

Each snapshot is written, fsynced and atomically renamed, then indexed. A
fresh server opens indexed WIP as protected recovery buffers. It never
overwrites source files with those checkpoints. `:DshRecoverySave PATH`
explicitly chooses a destination; its `!` form is the deliberate overwrite
case. `:DshCheckpoint` and `:DshRecover` are available for inspection. Disk
write failures produce an error notification and remain in the server log.
The existing OSC 52 copy-only clipboard provider also applies when a durable
server has no SSH TTY. Clipboard reads retain the existing Kitty ask policy.

`programs.agencyEditor.enable` is an inactive Home Manager option.
`viAlias` defaults to false. Opting in on the NAS maps `vi` to its directory
editor. `$EDITOR` and ordinary `nvim` keep their transient command behavior;
commit-message and harness `$EDITOR` subprocesses must still wait for editing
to finish. No default alias redirects a local terminal into remote installs.

## Ctrl+B and the left file tree

Dotfiles commit `d4bfa5ef79e5b80f8b4b670d794c451033cfce94` introduced the
universal Ctrl+B picker on 2026-07-15. It was a right split, used zmx, wrote a
pick file shared with a Kitty close watcher, then opened the selected file in
a new compositor window. Commit `20dfc9bc` removed those kittens. Its useful
gesture can be restored without restoring zmx, Herdr or the old workspace
model.

The new `agency_editor.py` helper toggles a left picker for the exact parent
Kitty window and session. Kitty 0.50 uses its native
[`window-dock`](https://sw.kovidgoyal.net/kitty/launch/#cmdoption-launch-type),
with a 28-column left edge. Installed 0.48 uses the existing splits layout's
horizontal axis and a split before the parent. The version gate is explicit;
0.50 flags are never sent to 0.48.

The NAS `dsh-editor-tree` payload uses the existing nvim-tree plugin. Selecting
a file emits one Kitty user variable containing a JSON directory/path result,
then exits. The local close watcher checks parent window id, child pid, NAS
host, session and directory before sending the result through `agency-kitty
edit`. That callback is checked again inside Kitty before a separate native
editor window is launched. There is no cross-host pick file or shell command
constructed from unquoted path text. The parent harness keeps its process and
terminal.

When Nvim is focused, a single Ctrl+B reaches its existing NvimTreeFocus
mapping. The helper uses Kitty's negotiated key encoder, including the
distinct Ctrl+Shift+B chord, instead of inventing raw escape encodings. Native
Nvim marks its window through `nvim_ui_send`, so the marker also crosses SSH
and native remote-UI channels. The UI wrapper clears its own marker on exit;
fish clears stale editor identity at the next prompt after an editor crash.

Kitty's built-in
[`choose_files`](https://sw.kovidgoyal.net/kitty/kittens/choose-files/)
is a useful fuzzy-picker alternative with JSON output and file previews. It
does not reproduce a persistent nvim-tree sidebar. The inspected
[`kitty-projects.nvim`](https://github.com/morgsmccauley/kitty-projects.nvim/tree/0570b5b748f1598e4fa8f5e8a21b0b6fad5193ec)
coordinates named windows and Vim session files; it is useful precedent for
editor identities but does not by itself preserve unnamed modified buffers
or supply the NAS transport boundary.

## Full harness history is a separate source

The existing
[`kitty-scrollback.nvim`](https://github.com/mikesmithgh/kitty-scrollback.nvim/tree/4994c85e0f291598d0748488653c83cb698fd281)
integration remains the direct terminal text reader. Kitty cannot reconstruct
semantic conversation turns after a full-screen TUI has overwritten them.
Native terminal history and Claude/Codex transcript exports therefore serve
different reading tasks. Reading an explicit harness transcript in Nvim can
go beyond the rendered viewport while leaving the live terminal renderer
untouched. That bridge is implemented by the parallel capabilities work, not
by adding an alternate screen renderer here.

## Verification and its bounds

All experiments ran on staged non-secret source on strix-coordinator through
the target's `runtime-test`. HOME was unchanged in the passing native proof;
private XDG config/data/cache/state and a test command PATH were used. No live
runtime, editor, physical display or credentials were accessed.

The ten-test integration/identity suite uses real installed Nvim for daemon
launches, concurrent canonical-directory identity, literal path arguments,
native UI death and reattachment, named and unnamed WIP after daemon SIGKILL,
explicit recovery save, and failure reporting. Identity checks and both Kitty
version branches have bounded control tests.

The real native proof used Kitty 0.48.0, a private headless Domicile desktop,
installed Nvim 0.12.4, upstream nvim-tree revision
`7e1da84aaffb413e1fa47b3895e5caa12501142d`, and the repository's actual Nvim
mapping template. It measured a 27-column left tree (the parent was its right
neighbor), selected a file into a new editor window, verified single-press
Ctrl+B without another Kitty pane, closed and reopened the editor UI, and saw
the same server pid and unsaved text with the original source file unchanged.
The SSH command boundary was explicitly replaced by a local command fixture;
this does not claim an end-to-end SSH deployment or physical key-to-photon
latency measurement. Kitty 0.50 docking is source-checked and unit-tested,
not native-tested on this installed 0.48 binary.

Passing native receipt and screenshot on compute:
`/home/tom/agent-work/kitty-consolidation/nvim-editor/native-proof-20261107-231113/`.
The fixture's Domicile teardown return code 1 is retained in its receipt, as
the private desktop is deliberately interrupted at the end. Initial fixture
failures and logs remain alongside it; they exposed actual unsupported
launch flags, temporary `sys.path` restoration, and interactive Nvim control
client startup. The fixed RPC clients are explicitly headless with no init;
the native UI attaches with `-u NONE` because the server already owns config.

Reproduction from the staged directory:

```sh
fleet-exec strix-coordinator --cwd /home/tom/agent-work/kitty-consolidation/nvim-editor -- \
  /home/tom/.local/bin/runtime-test -- python3 -m unittest discover \
  -s tests/dsh-editor -p 'test_*.py' -v

fleet-exec strix-coordinator --cwd /home/tom/agent-work/kitty-consolidation/nvim-editor -- \
  /home/tom/.local/bin/runtime-test -- env \
  KITTY_EDITOR_NVIM_TREE=/home/tom/agent-work/kitty-consolidation/nvim-editor/nvim-tree.lua \
  python3 tests/dsh-editor/native_editor_ui.py
```

The branch is a reviewable candidate. Home Manager activation and the
combined Agency Kitty fragment remain root integration steps; no running
terminal config was reloaded here.
