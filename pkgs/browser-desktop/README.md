# Shared FARA browser desktop

The human and Microsoft's FARA agent use the same stock noVNC desktop. Sway
provides a headless 1440×900 output; WayVNC transports its pixels, keyboard,
mouse and clipboard. The target is ordinary Google Chrome, using its existing
profile directories. Playwright controls only the noVNC viewer, never that
account-bearing Chrome browser.

`browser-desktop` is Bash packaged by Nix. `fara-browser` is a CLI adapter around
the pinned upstream `Fara15Agent.run()` and `DataPointWriter`, with session
lifecycle and takeover. noVNC's complete upstream interface is retained; the
injected UI adds control status, Take control and a Chrome menu in the sidebar. There is no replacement RFB
client, framebuffer, model loop, chat application or MCP server.

The right sidebar omits the noVNC logo and uses a plain desktop favicon.
The sidebar's Chrome icon lists the same existing profile/account mappings as
`fara-browser profiles`. Select one and press **Open window**; a locked keyring
instead offers **Unlock keyring** for the native desktop prompt. Menu launches
wait until a FARA task finishes or is cancelled. Manually opened windows stay
until the human closes them and survive subsequent FARA task cleanup.
A small loopback menu service reuses the CLI's profile, unlock and display checks;
it does not expose arbitrary commands, profile paths or URLs.

## Operator commands

```bash
fara-browser profiles
fara-browser status
fara-browser keyring
fara-browser unlock
fara-browser run --profile 'Profile 2' --task-file /path/to/task.txt
fara-browser pause
fara-browser resume --message-file /path/to/correction.txt
fara-browser cancel
```

Profile listings report Chrome's directory, display name and recorded Google
account, plus the active FARA task. Run status reports the profile/account at
launch and its current recorded metadata. These do not enumerate website
sessions: verify the intended website identity visually before acting. The selected
profile/account metadata also enters FARA’s task context automatically; the CLI
opens the selected profile before delegating to the upstream agent.

The adapter uses the same Fara 1.5 agent for 4B, 9B and 27B. Select an already
served size with `--model MODEL_ID --endpoint http://127.0.0.1:PORT/v1`; the ID
must match the endpoint's `/models` response. Status and replay record both.
The default on-demand service serves 9B only. Other selections do not download
weights or change the fleet's inference services. Live validation below used 9B;
4B and 27B have not been run in this session.

The human entrance is `http://browser.internal` on BE550, using the existing
Caddy and AdGuard conventions. `modules/browser-desktop.nix` declares the
coordinator service; `modules/fara-browser-model.nix` declares loopback-only,
on-demand inference using the already-loaned FARA weights. Neither activates
model downloads. The physical Niri/greetd stack remains disabled.

Sway starts with the lingering user manager at boot. The service waits for
WayVNC readiness and restarts automatically; the human viewer reconnects after
transport interruptions. The coordinator resolves its own viewer locally,
independent of Tailscale's `.internal` split-DNS. The client uses NAS DNS.
The existing Kitty/SSH/Herdr terminal route remains separate and unchanged.

Chrome's user-data directory has one owning browser process. If its windows are
already on another display, the CLI refuses to redirect or terminate them.
Close that browser normally before moving its profiles into Sway.

## Ownership, unlock and cleanup

Opening `browser.internal` during a run is silent spectator mode: it displays
live pixels, task ID and the recorded Chrome profile/account with mouse, keyboard
and clipboard input disabled. Loading or closing the viewer does not pause FARA.
Reconnects begin with input disabled until ownership is confirmed. The stock
view-only setting follows ownership and cannot override it. **Take control** is
the explicit transition to human input.

Take control cancels inference, disconnects the agent's RFB viewer and then
allows human input. Resume supplies a fresh screenshot and the operator's
message to the same FARA conversation. This coordinates the trusted human
viewer and harness; it is not compositor-enforced isolation from arbitrary
additional VNC clients. Closing a viewer tab does not cancel the task.

The default GNOME keyring is checked without reading secrets. If locked, the
native GCR prompt is displayed on Sway; SecretStorage maintains the same D-Bus
connection until the human finishes. No password enters the CLI, model prompt
or trajectory. Unlock normally lasts until reboot or explicit relocking.
This is a keyring prompt, not a polkit authentication policy change.

Completion/cancellation closes windows opened during the task, including new
Chrome dialogs, and the helper viewer. Earlier Chrome windows survive. If a
window refuses to close, the run reports `cleanup_failed`. The Sway desktop
stays available; inference is stopped if the task started it.

Runs under `~/.local/state/fara-browser/runs/<task-id>/` retain upstream screenshots
and action records. `lifecycle.jsonl` adds takeover and cleanup events;
`replay.html` reads these existing records in time order. It is an inspection
viewer, not a command re-executor. Keep the run directory private.

## Reuse and lineage

The historical BrowserOS native LLM panel, Assistant extension, Clash window
and Bun server are separate components. The Assistant currently depends on
fork-only `chrome.browserOS` and `Browser.*` APIs, so adopting it would add a
second agent stack and require compatibility work for ordinary Chrome.

The earlier agency llm-panels port was never built end to end, and its manifest
excludes Assistant integration. The useful continuity is D10's shared human/agent
input path and explicit control handoff, rather than resurrecting that fork.

Local references:

- `~/mecattaf/notes/references/devlogs/1h26/april-webshell-refs/REVOLUTION-2/revisions-pt2/BROWSEROS-SOURCE-AUDIT.md`
- `~/agency/agency/browser-features/llm-panels/MANIFEST.md`
- `~/agency/spec/specs/010-d10-capture-remote-multiseat/spec.md`, FR-031/FR-033
- `~/Downloads/fara/src/fara/agents/fara/fara15_agent.py`

## Validation, 2026-09-12

The package and fleet home-profile invariants build. Live Sway/WayVNC/noVNC
checks verified full-desktop capture, navigation, clicking and Unicode paste.
The real local FARA 1.5 9B model completed a local form task and visibly verified
`Saved: Nayla café`; its native trajectory includes takeover/resume and the
completed task window was removed. A separate run verified the stock noVNC
Take control button, cancellation during inference, and preservation of a
pre-existing Chrome window. The tests used a disposable Chrome profile.

The existing keyring reports unlocked. The native locked-keyring prompt still
needs its first human check after reboot/relocking; the tests do not relock the
user's keyring.

Coordinator and NAS were activated on 2026-09-12. Client-side checks verified DNS,
the HTTP viewer and WebSocket upgrade. Terminating the desktop processes verified
automatic restart and viewer reconnection. A further FARA run through the deployed
`browser.internal` entrance completed the Unicode form task in nine steps, removed
its task window and stopped its on-demand model. The desktop and Herdr remain up.
An idle desktop can be empty: the task opens its selected Chrome profile.

The Chrome sidebar was validated against a disposable real Chrome profile.
Regression checks cover origin validation, unknown profiles and task-lock
exclusion. A connected spectator sent no mouse, keyboard or wheel input while
a second noVNC viewer navigated Chrome; reload preserved spectator mode and
only the explicit Take control button requested a pause. The viewer always
requests a shared VNC connection, preserving other connected viewers.
