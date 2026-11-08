# Source provenance and licenses

The capability implementation is original stdlib Python under this repository's
MIT license. It calls the installed Kitty APIs and executables; no Kitty,
Herdr, Nvim plugin or DSH plugin source is vendored into this package.

Research clones live outside the repository under
`/home/tom/.wt/kitty-consolidation/sources/`:

- [Herdr](https://github.com/herdrdev/herdr), Apache-2.0. Exact installed
  v0.9.3 is `7b116c05bfda646af39d2524c54e70c751f57ee8`; current upstream master
  observed during this run is `ee5bfb5041bb3e4a49d591c72308aae3c81ecdde`.
  Its `client/clipboard_images.rs` and `server/clipboard_image.rs` demonstrate
  that image transport is an independent bounded upload followed by a pasted
  remote path. Its `server/alt_screen_read.rs` harvests alternate-screen
  history by sending wheel events and restoring the viewport; that technique
  was deliberately not copied into a live harness.
- [Kitty](https://github.com/kovidgoyal/kitty), GPL-3.0. The v0.48.0 source
  commit is `5b4ea1bbba26a9a4ba74dc9a5bb587c9f983fec5`. Source qualification
  and0.50.0 is `bb1aca6f279f1a5cfa3edd765a71650fe91b6472`. Source qualification
  used `kittens/runner.py`, `kitty/boss.py`, `kitty/window.py`, `kitty/mouse.c`
  and `kitty/screen.c`, especially the no-UI loader, exact-window callback,
  native bracketed paste and selection-complete callsites.
- `mecattaf/herdr-kitten`, MIT, archived source retained locally at
  `2f3aa71906a55afe3bebf16f9873a6206f448f7a`. Its custom-kitten loader lessons
  were reused as knowledge: Kitty executes a custom kitten without `__file__`,
  and no-UI handlers read their gesture from bound arguments rather than main.
  Its Herdr-owned workspace/pane architecture was not revived.
- [kitty-scrollback.nvim](https://github.com/mikesmithgh/kitty-scrollback.nvim),
  Apache-2.0, observed `4994c85e0f291598d0748488653c83cb698fd281`. The existing
  installed plugin remains the native shell scrollback action.
- [smart-splits.nvim](https://github.com/mrjones2014/smart-splits.nvim), MIT,
  observed `fdd0142633ae78b175ff29043953e701215a34dd`. It was researched for
  editor/Kitty navigation; no source was copied.
- [image.nvim](https://github.com/3rd/image.nvim), MIT, installed v1.5.1 source
  `da2be65c153ba15a14a342b05591652a6df70d58`. The separate dotfiles adapter
  verifies the installed backend/helper/geometry modules against their exact
  SHA-256 before routing the original backend through Neovim's native UI.
  Upstream source is not copied or vendored. Its retained headless-server
  geometry and reconnect behavior have a separate native editor qualification.
- [dsh-herdr](https://github.com/wenhao4126/dsh-herdr), BSD-3-Clause, exact
  dotfiles v0.4.0 source `3cbea69cb89477a3ae0f9fb93d92d38618df4eab`. It wraps
  Herdr CLI tools through `execFile`; no frontend or rendering layer from it
  is required for native Kitty sidechannels.
- [Codex](https://github.com/openai/codex), Apache-2.0, exact installed version
  0.163.0 source `83086188ae0614bd882818ff1aa23f3194962012`. Its hook schemas
  and core lifecycle dispatch were inspected for exact session/transcript
  binding. No Codex source was copied or modified.

Claude Code2.1.306's installed bundled image-path implementation was inspected
locally as primary evidence, and its actual TUI was run only against a private
offline Messages fixture. Claude's proprietary implementation is not copied,
vendored, patched or distributed here.

The private Anthropic sound captures are proprietary local-use assets. They
are outside Git and are not redistributed by this package. Their archived
provenance and checksums are in `CAPABILITIES.md` and the private audio README.
The freedesktop sound files are referenced from the system's installed theme.

The test's optional `cdp_wire.py` is imported from Tom's pre-existing private
benchmark source rather than copied or packaged. It directs trusted mouse
events only at the compositor created by the test.
