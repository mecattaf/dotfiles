# Stock Kitty SSH and native editor qualification

2026-11-07. This fixture uses the real stock Kitty SSH kitten, OpenSSH client
and server, patched holder, fish, Neovim TUI, Neovim native remote UI and
nvim-tree. No alternate terminal renderer is involved.

The passing full receipt is on strix-coordinator at:

`/home/tom/agent-work/kitty-consolidation/native-ssh/proof-14/receipt.json`

Its `native-ssh-editor.png`, retained screen, closed-window text and daemon
logs are alongside it. The receipt records hashes of the actual staged
launcher, transport, server, session store and editor helpers. Kitty was the
separately built 0.50.0 candidate. Holder was exactly
`1.0.1-agency.2`, SHA256
`44ea58fb4767171f786fe6a9a48972ebadea335923d3eef7fe36b5519a0f5300`.
The earlier stock Kitty 0.48 transport-only pass is in `proof-8`.

The later combined proof `proof-20/receipt.json` additionally ran the exact
installed Codex 0.163.0 TUI inside the retained remote fish. Its private
loopback Responses provider required no authentication and returned 300
explicit numbered history lines. The production image gesture staged a PNG
over SSH and became a real `[Image #1]` attachment; no model request occurred
before a separate explicit Enter. Actual SessionStart and Stop hooks bound
the exact transcript, thread and done state through the captured retained
PTY. Closing the actual Kitty/SSH client and resuming in a fresh native
window retained Codex PID 2943 and its start time. The fresh window restored
the same harness identity, exact transcript and done state without another
hook. The semantic history gesture then fetched that exact JSONL and opened
a native read-only Nvim view containing both line 000 and line 299. The test
navigated to both ends; the snapshot was 8111 bytes.

This run's editor server was 2478, and the parent SSH process was 1599. Its
`native-ssh-codex-history.png` and `native-ssh-editor.png` are retained beside
the receipt. These are actual harness/SSH/terminal executions with an offline
model fixture, rather than an imitation of the Codex screen or hook payloads.

The true **local** Nvim UI also passed in `proof-23/receipt.json`. This uses
the stock SSH client's private Unix socket forwarding to the retained NAS
editor; it does not run the TUI on NAS and carry its ANSI output over SSH.
Local TUI PID 3048 attached by RPC to retained NAS editor PID 2452, displayed
the same unsaved buffer, and sent real native keyboard input to that buffer.
An OSC 52 copy originating in the NAS editor reached Kitty's private Wayland
clipboard through the local UI. Closing that UI removed its private local
forwarding socket while leaving the NAS editor and unsaved buffer alive.
`native-local-nvim-rpc.png` is beside that receipt. This pass used the minimal
editor test configuration; full plugin/image parity is a separate gate.
The holder was the newer `1.0.1-agency.3`, SHA256
`b5bb5951c0103c7403e29dabcb11b82867d3813d097ce5ba7820233f0d0f466f`.

The complete intended local UI then passed in `proof-24/receipt.json` with
the actual user's 32-plugin configuration, all plugin sources resolved from
the installed Nix closure and external network blocked. It rendered the
Catppuccin mocha/noir theme, Markdown heading/checklist/code colors, native
NvimTree, Markdown tree-sitter and the marksman LSP. A Markdown PNG reached
the real local Kitty graphics manager. The headless image adapter received
exact native 9x19 cell geometry and sent 3171 graphics bytes; after closing
that local UI and opening a fresh one against the same retained NAS editor
PID 2396, it sent another 548 bytes, incremented retransmissions from 2 to 3,
and the fresh Kitty graphics manager contained the PNG. Unsaved text and
OSC 52 clipboard behavior also passed. The two `native-local-nvim-rpc*.png`
screenshots are retained and the first was visually inspected. An initial
headless image-discovery ordering issue is fixed by retrying only the pinned
image.nvim document integration after exact geometry arrives.

The primary `vi` lifecycle passed in `proof-28/receipt.json` with the same full
configuration and stock SSH. In the actual NAS fish, `vi notes.md; nextcommand`
opened the local native UI and kept the next command blocked until native
`:detach`, then returned status 0. An explicit local editor window close
returned status 129 and released the NAS command while preserving the editor
process. Separately, killing only the exact SSH lifecycle endpoint released
its exclusive client lease without completing the NAS `vi`. After closing
and freshly reattaching the parent Kitty/SSH view, a freshly encoded typed
request opened the same pending UI against NAS editor PID 2297, retaining its
unsaved text and actual Markdown PNG. Detaching completed the original
blocked fish command. Local fish's autoloaded `vi` also ran a local RPC UI in
that same Kitty window, reused the same NAS editor and returned status 0.
The UI owner waits on Linux pidfds for child lifecycle changes; it has no
recurring idle, keypress or terminal-output callback.

The request bridge owns no terminal stream. Its private Unix socket accepts
one exact claim and one bounded exit status, exclusive to the still-live NAS
request PID/start time and original managed PTY. Native Kitty revalidates the
actual source window/session/current directory before launching a local
client, and the client claims NAS authority before allocating an editor.
Stale/dead claims, duplicate clients, signal cancellation and disconnect lease
release also have real private PTY/socket tests. The UI/RPC forward is separate
from that lifecycle socket and carries the ordinary native Neovim protocol.

`proof-31/receipt.json` extends that gate with ordinary unmanaged SSH and a
live editor crash. Ordinary SSH fish `vi` returns actionable managed-terminal
guidance before allocating any editor, with no alternate editor fallback.
The test checkpointed dirty renamed and unnamed buffers, killed only NAS
editor 2279, and opened a fresh local native UI against replacement editor
5285. Both drafts reappeared as protected recovery buffers; the saved source
and the uncreated rename destination stayed untouched, and the parent fish
remained alive. Bare `:write` was refused. An explicit `DshRecoverySave` wrote
only its chosen private test destination, then normal marksman LSP attached.
An actual marksman crash discovered during this gate is retained in proof-29:
the plugin had treated a virtual recovery URI as a filesystem workspace.
Recovery URIs now skip that invalid root; ordinary LSP resumes on explicit
save to a real file. `native-local-recovery-after-server-kill.png` is retained.

`proof-34/receipt.json` qualifies two simultaneous true local UIs of that same
retained NAS editor, with the complete plugin configuration. Native Kitty
font cells were 9x19 and 14x30 pixels. Both actual graphics managers retained
the original 1280x640 PNG, rather than a bitmap downsampled for the first UI.
Kitty's cell-relative image placements scaled it separately at each font and
preserved its aspect ratio. Each UI's native cell query carried a bounded
nonce, so Neovim 0.12's channel-less TermResponse could not make a response
from one UI overwrite the other UI's geometry. Closing the first UI transferred
the stable shared-layout anchor to the remaining UI. Neovim intentionally
shares one logical editor grid between attached views; native Kitty performs
the final pixel scaling independently. No editor or terminal fork is needed.
The extended `proof-35/receipt.json` also created a real shared split viewport:
both native placements cropped to the same original-source rectangle, retained
aspect ratio, and restored the uncropped image when that split closed.

The final combined editor gate on 2026-11-08 is
`proof-36/receipt.json`. It used the exact activated Kitty
`/nix/store/rs4s3ggn03a65bbwj9r1ps20d4kichm1-kitty-0.50.0/bin/kitty`
and explicitly selected the official Domicile engine 63db244. The receipt
attests the actual `/proc`-loaded library in that closure, SHA256
`43f0dc75132f7ab3ae7042a75d7c19b88e89a9e10a4850a656a06bcda623c02f`.
One run passed the full configuration, simultaneous differently sized native
UIs and viewport crops, both local and NAS blocking `vi`, pending-request
resumption, explicit window-close status, unmanaged NAS refusal, and live
server-kill recovery. Its original NAS editor PID was 2359; recovery created
5781. Six native screenshots and source hashes are retained with the receipt.
Earlier proofs did not attest the native engine revision; a current Domicile
frontend wrapper can select an older engine unless this override is explicit.

The full passing proof established:

- Real public-key authentication and PTY allocation through stock SSH
  bootstrap. One raw `k` reached a remote PTY child without Enter.
- Native fish prompt integration and physical directory metadata after `cd`.
- The same fish process and its unsaved shell variable after the SSH view
  closed and resumed. Its PID was 1060 within the private namespace.
- After reconnect, an explicit editor gesture repaired directory metadata
  from the retained native OSC 7 report and opened the current nested
  directory, rather than the immutable launch directory.
- A real 28-column native Kitty left dock ran the NAS nvim-tree picker over
  another stock SSH connection. Its selected file opened a separate native
  editor OS window, preserving parent SSH process 1556.
- One Ctrl+B reached Nvim's existing mapping. Closing that actual SSH editor
  UI and reopening it retained Nvim server 2438 and the unsaved buffer. The
  source file retained its saved contents.
- An unknown resume UUID failed without allocating a replacement or changing
  the remote session inventory.

This is a functional qualification on compute with loopback SSH, private
host identity `nas`, software-rendered private Domicile and no physical
display. It does not measure the laptop's physical key-to-photon latency,
Tailscale network latency or a NAS reboot. Separate editor tests cover
checkpoint recovery after server SIGKILL, including unnamed buffers.

## Isolation and the privileged SSH supervisor

Run the actual fixture through the target's `runtime-test`. It creates
private runtime sockets, PTYs, process and IPC namespaces. A further inner
bubblewrap mount hides the real home at the *same* passwd home path, then
binds back only this staged non-secret checkout. HOME stays unchanged. The
inner fixture also gives itself a private UTS hostname `nas` and loopback-only
network namespace, masks
`/var/log`, and binds a private `/run/utmp`.

The test generates throwaway client and host keys and a private known-hosts
file. The only transport shim logs the production SSH argv and translates
its fixed NAS address to a random loopback port using OpenSSH's first-option
precedence. Production argv construction, host-key alias, host-key checking,
SSH bootstrap, PTY input and terminal bytes remain unchanged.

An unprivileged private sshd cannot qualify PTYs inside runtime-test's
single-UID/GID user namespace: stock sshd needs its privilege-separation user
and the tty group. A narrow `sudo -n` supervisor joins only the already
isolated fixture's mount, PID, IPC, UTS and network namespaces while retaining normal
UID/GID mappings. Before starting sshd it verifies the home and utmp masks.
It changes no service, system configuration, real key or real home file. It
has a bounded lifetime and terminates its own process group during teardown.

The supervisor must run outside the single-UID user namespace; the desktop
and test still run through runtime-test. Do not substitute a fake SSH server
or patched authentication implementation and call that a stock SSH proof.

## Reproduction

Stage a non-secret checkout under compute home, the pinned holder binary
inside that checkout, and these assets under `integration/editor/`:

- `bin/dsh-editor`, `bin/dsh-editor-tree`, and `bin/nvim-lua/` from dotfiles.
- `kitty/agency_editor.py` and `kitty/agency_editor_watch.py` from the same
  dotfiles revision as the candidate package.
- `lua/` from dotfiles' raw Neovim Lua configuration and `mappings.lua` from
  `home/nvim/mappings.lua.in`.
- Upstream nvim-tree at `nvim-tree/`, pinned for this run to
  `7e1da84aaffb413e1fa47b3895e5caa12501142d`.
- The managed-session PWD hook at `integration/agency-kitty.fish`.

Use a fresh output directory for each run. In one terminal, start the bounded
private SSH supervisor:

```sh
fleet-exec strix-coordinator --cwd /home/tom/agent-work/kitty-consolidation/native-ssh -- \
  sudo -n python3 tests/native_ssh_transport.py --serve-private-sshd \
  /home/tom/agent-work/kitty-consolidation/native-ssh/proof-NEXT
```

Then run the actual fixture in another terminal:

```sh
fleet-exec strix-coordinator --cwd /home/tom/agent-work/kitty-consolidation/native-ssh -- \
  /home/tom/.local/bin/runtime-test -- python3 tests/native_ssh_transport.py \
  --output /home/tom/agent-work/kitty-consolidation/native-ssh/proof-NEXT \
  --zmx /home/tom/agent-work/kitty-consolidation/native-ssh/backend/agency-zmx-v3 \
  --fish-hook /home/tom/agent-work/kitty-consolidation/native-ssh/integration/agency-kitty.fish \
  --external-sshd \
  --editor-assets /home/tom/agent-work/kitty-consolidation/native-ssh/integration/editor \
  --kitty /nix/store/rs4s3ggn03a65bbwj9r1ps20d4kichm1-kitty-0.50.0/bin/kitty \
  --engine-root /nix/store/9h4xmaqrb1w5hs8f5x4vasbzac7y966z-domicile-engine-63db244
```

Omit `--editor-assets` for the transport-only proof. The default Kitty binary
is the installed 0.48.0 baseline. A 0.48 editor run additionally needs the
existing splits layout; 0.50's native dock does not depend on that layout.

Add `--local-editor-ui` to compare a true local Nvim TUI against the same
retained NAS editor and verify real keyboard input, OSC 52 and private socket
cleanup. Stage the candidate `agency_kitty/editor_ui.py` and the local
`nvim` binary on PATH, in addition to the ordinary NAS editor assets.

For the full user configuration gate, also stage `raw-config/` from dotfiles'
raw Neovim configuration and the candidate `plugins.lua.in` in the editor
asset directory, then add `--full-editor-config --plugin-table PATH
--mappings-table PATH` using the installed generated Nix Lua files. The
fixture extracts only the plugin table and substituted executable path as
data, verifies every closure path exists, and renders the candidate template.
It does not evaluate a user's project setup or fetch missing plugins.

Add `--primary-vi` for the actual local/NAS fish lifecycle gate. Stage dotfiles'
single-function `home/dot_config/fish/functions/vi.fish` as `vi.fish` within
the editor asset directory. The fixture autoloads that exact function into
minimal isolated fish configurations; it never sources an unbounded fragment
of a user's shell configuration.

Add `--editor-crash-recovery` to run the live NAS editor SIGKILL gate, including
protected renamed/untitled drafts and LSP after explicit recovery save.

Add `--multi-ui-images` with the full-configuration gate to attach two native
UIs with different actual font cells. The fixture checks original source
pixels, each native placement's source/destination aspect ratio, a real split
viewport crop, and the remaining UI's geometry after the first one closes.

Add `--offline-codex` on Kitty 0.50 to run the combined real harness gate.
Stage `tests/offline_codex_session.py` and its sibling `codex_tui.py` from the
same candidate. The launcher uses its explicit inner mode inside this
fixture's already private home and loopback network, preserving the retained
fish's UID namespace and exact PTY context. It does not assign HOME or
CODEX_HOME. The ordinary NAS command location is emulated only within the
masked home, so image and transcript workers use the same normal command
path as production. Codex's deliberate paste-burst guard requires a native
bracketed paste followed by a separate Enter; it is not a transport delay.

Initial failures are retained, including real integration issues corrected
before the final pass: remote commands need `-tt`, tree commands must not be
given an unsupported `--`, Kitty 0.50 PID identity skips its wrapper process,
OSC 7 state is bytes, and Kitty's own cwd scheme carries raw literal paths.
Fixture-only failures included private sshd UID mapping, login PATH restoration
and an unstaged local Lua helper. No live session was repaired or restarted.
