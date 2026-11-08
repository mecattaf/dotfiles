# Published Core0.1.18: live bytes and fresh restoration

The published Herdr Core0.1.18 binary passed attached native protocol handling
but failed this workflow's complete fresh-display restoration gate. This is a
functional result, separate from the frozen software latency comparisons and
from historical Herdr0.9.3's presentation path.

`backend/herdr_core_native_fidelity.py` ran on Strix through `runtime-test` and
the exact activated Kitty0.50 native C `Screen`, without a GUI, GPU, compositor
or new build. The real home filesystem was masked while `HOME` retained its
value. It used the published Core binary SHA256
`baa9d208d6400556a6e379152455fe1301e0e1acdbc114ff60b79d64425179cf`, release
source tag [`3965a46c`](https://github.com/herdrdev/herdr-core/tree/3965a46caae095a3ead01de237fa13955e52b8c6),
and Kitty SHA256
`d0565fa5f55341068f2354e0c4444a16cfa268e1c08701f3c59b2bfc8fefa918`.

Four independent private application PTYs each emitted one explicit state
payload, then continued without redrawing. An independently initialized native
Kitty Screen fed the same bytes supplied the state oracle. After inspecting
attached output, the fixture closed the client and attached two fresh clients,
each with a new blank native Screen. The application PID, process start and
single-emission record stayed identical. Fresh attachment never requested an
application redraw or sent an application command.

- **Keyboard/text:** attached and both fresh clients retained KKP flags31,
  combining Unicode, CJK, joined emoji and the tested truecolor text.
- **Cursor:** all phases retained position21,14, visibility and blinking.
  The explicit bar shape was correct while attached; both fresh clients fell
  back to the terminal's default shape.
- **Colors:** attached output applied explicit OSC4 palette index17
  `#123456`, OSC10 foreground `#112233` and OSC11 background `#445566`.
  Both fresh clients lost those application overrides. This checks explicit
  program changes; it does not claim that an arbitrary user's configured theme
  is overwritten, nor does it certify every palette operation.
- **Static graphics:** attached output decoded the exact2×2 PNG RGBA pixels
  (SHA256 `50c3618d17fcb4251513a0f4eb6b344bb600b903d284a5f5324dba8fd35b56cb`)
  with one placement and the same source/destination rectangles as the oracle.
  Both fresh clients had no image, so neither pixels nor placement survived.
- **OSC66:** attached native state retained the tested double-size `WIDE`
  multicell text. Both fresh clients lost that sizing state and differed from
  the oracle's native lines. A successful attach did not refuse this incomplete
  restoration.

The full [receipt](evidence/herdr-core-native/receipt.json) has
`completed: true`, `attached_oracle_pass: true`, `same_process_pass: true` and
`full_fresh_restore_pass: false`. It records every expected/attached/fresh
state, exact source/interpreter hashes and an empty owned-process cleanup
inventory; the private server stopped successfully. Its SHA256 is
`77321694b3af87d6d1d70decbf88648cc9e7307eada7d27361a1077cda7eade0`.
The [stderr log](evidence/herdr-core-native/stderr.log) preserves native parser
warnings for Core's reset sequences, including unsupported modes9/1001/66.
No warnings or failed fixture attempts were suppressed. Earlier fixtures
remain on compute; one corrected a missing fixture import path and another
corrected its cleanup audit of the deliberately nondumpable namespace init.

The final compute proof root is
`/home/tom/.wt/kitty-consolidation/core-native-fidelity/proof-final-2`.
It retains raw attached/reconnect byte captures, payloads, application owner
records and command outcomes. These tested gaps do not mean the live carrier
has old Herdr's frame cadence. They do mean that attached passthrough and
same-PID persistence are insufficient grounds for adopting Core as a fully
faithful Kitty restoration backend.

The pinned source provides relevant mechanisms: its
[paint formatter](https://github.com/herdrdev/herdr-core/blob/3965a46caae095a3ead01de237fa13955e52b8c6/crates/ghostty-vt/src/lib.rs)
omits palette serialization, and
[first-paint composition](https://github.com/herdrdev/herdr-core/blob/3965a46caae095a3ead01de237fa13955e52b8c6/crates/herdr-core/src/viewers.rs)
uses that VT screen paint. The native observations above establish the actual
binary behavior; they do not assume that source comments prove complete
graphics or cursor replay.

## Historical attach timing has a narrower attribution

The frozen old0.9.3 terminal-attach idle distribution near19ms must remain a
measured result, not an invented universal20ms timer. A bounded audit of the
exact [`7b116c05`](https://github.com/herdrdev/herdr/tree/7b116c05bfda646af39d2524c54e70c751f57ee8)
source did not establish such an attach timer. The shared
[render gate](https://github.com/herdrdev/herdr/blob/7b116c05bfda646af39d2524c54e70c751f57ee8/src/app/runtime.rs#L74)
has a16ms recent-render interval; idle first presentation can be immediate.
[`render_terminal_virtual`](https://github.com/herdrdev/herdr/blob/7b116c05bfda646af39d2524c54e70c751f57ee8/src/server/render_stream.rs#L578)
still constructs Ratatui frames. The client's100ms maintenance timer is woken
independently by input/socket events. Its10ms raw-input idle flush follows
immediate forwarding of complete ordinary chunks. The20ms cursor-position
settle policy is Windows-only in
[`pane/terminal.rs`](https://github.com/herdrdev/herdr/blob/7b116c05bfda646af39d2524c54e70c751f57ee8/src/pane/terminal.rs#L45),
so it cannot explain these Linux cases. Isolating that remaining old-path
mechanism would require further tracing, not another speculative floor claim.
