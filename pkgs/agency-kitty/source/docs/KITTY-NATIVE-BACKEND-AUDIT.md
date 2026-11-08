# A native Kitty shadow is feasible, but export is the missing backend

For a workflow whose only terminal frontend is Kitty, its own VT engine is a
credible candidate for the most faithful NAS state model. It understands
Kitty extensions at the same source revision as the frontend, including the
OSC66 text sizing that the pinned Ghostty model cannot reconstruct. Using
private APIs is a maintenance choice, not evidence that this cannot work.
Neither this source audit nor the earlier headless probe establishes that it
is the fastest shadow, or that a complete native backend already exists.

This audit inspected Kitty0.50.0 commit
[`bb1aca6f279f1a5cfa3edd765a71650fe91b6472`](https://github.com/kovidgoyal/kitty/tree/bb1aca6f279f1a5cfa3edd765a71650fe91b6472).
It adds documentation only: no implementation, build, runtime experiment or
timing. The existing [native probe](NATIVE-VT.md) and
[receipt](evidence/native-kitty-vt/receipt.json) prove headless parsing,
Unicode/truecolor, OSC66 text round trip, keyboard flags31, and exact decoded
PNG pixels with a retained placement. They do not prove full state export or
fresh graphics restoration. That probe's callbacks mostly record events;
they are not a complete implementation of Kitty's window behavior.

## What can already be exported

**Text, both screens and history:** `Screen.as_text_non_visual()`,
`as_text_alternate()` and `as_text_for_history_buf()` expose current-screen,
inactive-screen and history text. The
[formatter](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/line.c#L1126-L1192)
supports SGR, OSC8 hyperlinks, native OSC66 multicell text, and explicit wrap
markers. It distinguishes a soft wrap from a real newline. A replay adapter
can therefore preserve considerably more than a grid of strings. The
[history interface](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/history.c#L667-L677)
also exposes pager-history bytes separately. A design must distinguish those
bytes from ordinary bounded history and define geometry/reflow policy.

These are not immutable model snapshots. `Screen.line()` returns the
[reused Line view](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/screen.c#L5644-L5654)
retargeted by later line access. Keeping a Python reference does not freeze
its cells. `LineBuf.create_line_copy()` copies cell storage, but shares the
screen's text cache. `as_text_alternate()` temporarily changes the active
line-buffer pointer. Export needs exclusive model ownership or an explicitly
owned snapshot, not concurrent traversal while parsing continues.

**Cursor and input state:** the
[Cursor object](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/cursor.c#L345-L365)
exposes position, shape, blinking and display attributes. Screen getters expose
current bracketed-paste, focus, cursor-key and several other modes; current
keyboard flags and margins are readable. Even the public
[`get-text` command](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/rc/get_text.py#L13-L64)
can include cursor position/style and wrap markers. It is a useful text export
API, not a full terminal snapshot.

The full
[`Screen` structure](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/screen.h#L127-L232)
contains more state than the Python interface exposes: separate main/alternate
keyboard stacks, tab-stop arrays, saved modes, per-screen saved cursors and
charsets, pointer-shape stacks, extra cursors, and the last graphic character used by repeat
operations. Restoring only current keyboard flags loses what a later pop
should reveal. Restoring only the visible cursor loses what a later cursor
restore should reveal. Those are concrete inspection/export additions, not
missing parsers. They also need deliberate replay ordering across both screens.

**Colors:**
[`ColorProfile.as_dict()`](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/colors.c#L737-L835)
exports all256 effective palette values and selected dynamic/window/session
colors. It does not expose the per-index application-override mask, complete
color-layer identity, or saved color-stack entries. The
[native structure](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/data-types.h#L315-L362)
retains those distinctions. They matter: blindly replaying all256 server colors
would replace a new frontend's theme; comparing values cannot identify an
explicit application override equal to the old default. Export needs the
override mask, dynamic-color types and saved stack state. `color_stack_depth()`
alone is insufficient, and the current C
[`copy_color_profile()` helper](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/colors.c#L490-L503)
does not copy the saved stack.

**Graphics:** the model already owns decoded images, placements, animations
and chunked loading. The
[Python image accessor](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/graphics.c#L2948-L3028)
returns root pixels and coalesced animation-frame pixels for a known client
image ID/number, plus some state. This is a substantial starting point;
graphics are not locked behind the GPU. The
[zero-window-ID guard](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/graphics.c#L943-L952)
skips texture upload, which the headless probe exercised.

However, the exposed manager lacks a read-only iterator over every retained
image and every placement. `update_layers()` gives viewport rendering
rectangles, not the original placement graph. The
[internal state](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/graphics.h#L71-L188)
also contains unplaced/anonymous images, client/internal ID relationships,
virtual placements, parent/relative references, crop/cell offsets, animation
loop/frame timing, and an in-progress load. Main and alternate graphics
managers are distinct; Python exposes the active one. Exporting visible
rectangles alone would lose future placement/delete/composition semantics.

The image accessor eagerly copies whole images and all animation frames into
Python bytes. A bounded streamed export API is preferable. It must report
allocation/cache failures explicitly. Another reason not to enumerate IDs by
guessing: at this revision `image_for_client_id()` calls
[`find_or_create_image()`](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/graphics.c#L644-L661),
which creates an internal image on an unknown ID before the accessor returns
`None`. That accessor is not a safe read-only inventory primitive.

## A Screen is not the entire Kitty implementation

OSC4/104 palette changes, OSC10/11 dynamic colors, title changes, clipboard
operations and notifications are
[dispatched to callbacks](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/screen.c#L3564-L3608).
For example, actual parsing/application of color changes and responses is in
[`Window.set_dynamic_color()` / `set_color_table_color()`](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/window.py#L1744-L1849).
A backend must implement or carefully reuse those semantics. Merely feeding
`Screen` with no-op callbacks would silently miss them. Cwd is retained by
Screen; titles and other window metadata also require callback-owned state.

The shadow must not duplicate clipboard writes, desktop notifications, file
transfers or terminal query responses already handled by the attached Kitty.
Read-only frontend inspection must remain separate from input/close authority.
Filesystem graphics transports need explicit host policy too: the native
[image loader](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/graphics.c#L728-L818)
can read files/shared memory and remove protocol temporary objects under its
existing checks. A NAS shadow and a local frontend have different filesystems;
running this code twice is not automatically equivalent to native transport.

## Snapshot boundaries need an actual contract

The parser stores partial UTF-8, CSI and string input in its
[private state](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/vt-parser.c#L231-L260).
Python exposes only the state name, not a complete continuation or pending-byte
export. A reconnect halfway through a control string or image upload needs an
exact boundary plus continuation strategy, or an explicit refusal; dropping
the partial input is not faithful restoration. Native parser state can remain
in the same NAS process, but the fresh frontend still needs a valid handoff.

The
[parser header](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/vt-parser.h#L41-L60)
distinguishes main-thread lifecycle calls from locked input-buffer calls.
The production-shipped `test_*` feed helpers made the probe possible; they do
not define a supported standalone threading/lifetime interface. Global options,
Python callbacks and model ownership need a pinned adapter or small native
embedding boundary. PNG decoding remains additional server work; using Kitty's
C parser does not by itself make it asynchronous or free.

Likewise, `pause_rendering()` is a
[display snapshot](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/screen.c#L3835-L3902),
not a full terminal clone: it copies visible rows and presentation state,
shares underlying resources, and omits full history/parser/input state. A
backend must distinguish the currently displayed synchronized-output frame
from the newer logical model. Borrowed pointers, cache indices, textures,
mutexes and callbacks must never become a wire-format memory dump.

Kitty0.50's
[logout restoration](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/logout_session.py#L319-L358)
does not supply the missing complete serializer. It saves main-screen/history
text, omits pager history/current prompt/trailing blanks, rejoins wraps, and
permits only SGR/OSC8/OSC66 on restore. Child commands are relaunched. Its
[pre-child restore barrier](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/window.py#L1084-L1104)
is useful precedent: restore text before allowing new output. A retained PTY
needs that ordering at an exact byte offset, with bounded queues and input
preserved throughout, rather than pretending the old child has restarted.

## The concrete next backend boundary

A focused native candidate would add an owned, versioned Screen export API
covering both screens/history, complete current and saved input state, explicit
palette overrides/stacks, graphics inventory/placement graphs, and parser/load
continuations. It should stream bounded chunks and separate model callbacks
from host side effects. The existing PTY owner, exact UUID identity, bounded
observer queues and snapshot-offset barriers can remain; there is no reason to
add a renderer or a multiplexing UI.

There are two distinct restore designs. VT/KGP replay into stock Kitty can
reuse its existing parser, but each exported field needs a demonstrated wire
reconstruction, including future pop/delete/frame commands. A native
snapshot-import extension in matching local Kitty could preserve state that is
awkward to express as replay, but requires a maintained frontend change and
version negotiation. Neither complete import/export API exists in the inspected
interface. This is a feasibility map, not proof either design is impossible.

The model must also receive current rows/columns and cell pixel geometry, and
negotiate capabilities with the actual attaching Kitty revision. A matching
engine pin helps; `TERM=xterm-kitty` alone does not prove matching extension
versions or geometry. Reflow and image placement must be qualified when those
change.

Admission would need same-PID/draft preservation without CtrlL or injected
input; both-screen and saved-stack behavior after reconnect; theme changes with
explicit equal-to-default overrides; soft wraps/OSC8/OSC66 and changed widths;
unplaced/virtual/relative/indexed/animated graphics and future deletes; reconnect
inside UTF-8/control/image chunks; and bounded behavior under slow observers,
cache pressure and decode work. Any unsupported case must be explicit. The
existing static-image probe is not a substitute for those gates.

Compared with [libghostty's supported C boundary](LIBGHOSTTY-C-ABI.md), native
Kitty offers closer protocol alignment and a tighter dependency on the pinned
Kitty implementation. Its
[GPLv3 license](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/LICENSE)
also needs to remain part of the integration/distribution design. A small
version-pinned native export patch is a realistic research path if complete
Kitty fidelity is the deciding priority. Today's qualified subset backend and
the unchanged direct-SSH reference remain separate choices; no source audit
justifies a universal protocol-parity or zero-latency claim.
