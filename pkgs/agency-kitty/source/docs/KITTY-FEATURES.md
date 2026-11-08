# Native Kitty feature admission

The reference is installed Kitty0.48.0. Candidate0.50.0 is pinned separately in
dotfiles `pkgs/kitty-0.50.nix`; it is not an explanation for today's change.

## Already valuable in this workflow

- Kitty's native parser, renderer, Unicode shaping, truecolor, cell-aware
  selection and soft-wrap handling stay in charge. Keep current fonts and
  monitor pacing fixed when testing transport changes.
- Stock SSH kitten supplies terminfo and shell integration for OSC7 cwd,
  OSC133 command/prompt boundaries, cursor behavior and remote-aware actions.
  It is bootstrap, not a PTY holder. An explicit remote command needs `-tt`
  and deliberate fish integration; ordinary login behavior is insufficient.
- Native KKP keyboard flags, bracketed paste, focus/mouse reporting,
  synchronized output and KGP graphics stay on the native byte path while
  attached. Protocol passthrough is distinct from reconstructing those states
  into a fresh terminal after disconnect.
- Native OSC52 clipboard writes and prompted reads preserve the existing
  clipboard contract. The image action reads the local Wayland clipboard only
  after an explicit paste gesture, then sends bytes to a fixed NAS file helper.
- Native drag selection remains native. The small qualified callback adds
  only completion feedback; it does not synthesize line breaks or reflow text.
- OSC99 is desktop notification; OSC7 is cwd. They are not interchangeable.
  OSC133 marks shell commands. OSC1337 user variables carry bounded local
  workflow metadata. No program-status escape alone proves an agent turn is
  finished; exact harness hooks/DSH events provide that semantic fact.
- Existing kitty-scrollback.nvim remains the shell history view. Exact harness
  transcript binding provides saved semantic history beyond the TUI viewport.
- Kitty owns the file-tree pane and native Nvim UI window. Ctrl+B inside Nvim
  is forwarded as one encoded key; other managed windows toggle their tree.
- Native hints, hyperlinks, diff, Unicode input, command palette and remote
  file tools remain available as explicit actions. They need no proxy renderer
  or replacement harness. Existing bindings are not gratuitously reassigned.

## Changes in the separately evaluated0.50 candidate

[Upstream changelog](https://sw.kovidgoyal.net/kitty/changelog/#id1), release
2026-11-03, and pinned source commit
`bb1aca6f279f1a5cfa3edd765a71650fe91b6472`:

-0.50 adds native window/tab docks. The file-tree helper selects a left
  window-dock there;0.48 uses a qualified left split instead.
-0.50 adds restore-after-logout. This can recreate local layout/scrollback;
  it does not keep a remote process alive. Linux support depends on a desktop
  portal, which must be qualified against Domicile rather than assumed.
-0.50 recognizes Program Status Protocol OSC7501. This can annotate a native
  window, while DSH/harness lifecycle events remain the source of agent state.
-0.49 optimized parser/scrolling/shaping/compositing throughput. Throughput is
  distinct from foreground key latency.
-0.49.2 handles small program output such as typed echoes immediately instead
  of waiting input_delay. This is relevant to a future upgrade, and cannot
  explain today's improvement while the installed terminal remains0.48.0.
-0.50 introduces shader-slang compilation and sphinx-design build dependencies;
  the candidate package explicitly adds them. Custom shader support is not
  enabled as an input-latency optimization.

## Preserve the feel

Keep managed direct SSH available even when enabling resumable sessions.
Measure both idle echo and typing during steady unrelated output. Record p50,
p95, sample count, transport version and the SSH timing policy. Reject input
loss, implicit creation on stale resume, unbounded observer queues and any
return of a frame timer to the foreground stream.

Upstream's [performance guide](https://sw.kovidgoyal.net/kitty/performance/)
provides a low-latency profile: input_delay0, repaint_delay2,
sync_to_monitor no and wayland_enable_ime no. Those trade energy, tearing and
input-method support. This pass leaves the measured production settings3/10,
sync yes and current input methods intact. A private software render benchmark
cannot justify silently changing the physical desktop's pacing or IME.

The explicit no-holder route is the strongest compatibility and latency
reference. A shadow VT holder inevitably adds parser/scheduling work and its
snapshot formatter has state limits. This package keeps the choice explicit.

The pasted tuning explanation also misnames `input_delay`: it delays processing
input **from the child program**, meaning terminal output, rather than simply
holding physical keyboard events. In0.50, small output such as typed echo has
an immediate-wakeup path with coalescing for continuous writes. The documented
`repaint_delay` is bypassed when input is pending; its default10 does not impose
an unconditional100FPS typing ceiling. See the pinned
[`option definitions`](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/options/definition.py#L1527)
and [`I/O wake policy`](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/child-monitor.c#L2068).
The local terminal uses separate child-I/O and rendering work; the earlier
description of a uniquely single-threaded Kitty path is also inaccurate.
