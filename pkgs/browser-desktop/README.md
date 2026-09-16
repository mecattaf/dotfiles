# Shared browser desktop

A human-operated Google Chrome desktop on the coordinator, reached through stock
noVNC. Sway provides a headless 1440×900 output; WayVNC transports its pixels,
keyboard, mouse and clipboard. The target is ordinary Google Chrome, using its
existing profile directories.

FARA was retired on 2026-09-16 per Tom; its agent loop (`fara-browser`, takeover
controls, trajectories) was removed from this desktop and is recoverable from git history.

`browser-desktop` is Bash packaged by Nix. noVNC's complete upstream interface is
retained; the injected UI adds session start and a Chrome menu in the sidebar.
There is no replacement RFB client, framebuffer, chat application or MCP server.

The right sidebar omits the noVNC logo and uses a plain desktop favicon.
The sidebar's Chrome icon lists Chrome's recorded profile directories, display
names and Google accounts. Select one and press **Open window**; a locked
keyring instead offers **Unlock keyring** for the native desktop prompt. The
listing does not enumerate website sessions: verify the intended website
identity visually before acting.

`browser-desktop-menu` is a small loopback service (port 4784, reached as
`/desktop/*`) behind that menu. It accepts changes only from the
`https://browser.internal` origin with the `X-Desktop-Control` header, runs one
desktop action at a time, and does not expose arbitrary commands, profile paths
or URLs.

The human entrance is `https://browser.internal` on BE550, using the existing
Caddy and AdGuard conventions. `modules/browser-desktop.nix` declares the
coordinator service. The physical Niri/greetd stack remains disabled.

The lightweight menu service starts at boot. Sway and WayVNC start only when the
human opens the viewer or uses the Chrome menu. The service waits for WayVNC
readiness and restarts automatically; the viewer reconnects after transport
interruptions. The coordinator resolves its own viewer locally, independent of
Tailscale's `.internal` split-DNS. The client uses NAS DNS. The existing
Kitty/SSH/Herdr terminal route remains separate and unchanged.

Chrome's user-data directory has one owning browser process. If its windows are
already on another display, the menu refuses to redirect or terminate them.
Close that browser normally before moving its profiles into Sway.

The viewer always requests a shared VNC connection, preserving other connected
viewers. Additional viewers are not isolated from each other: any of them can
send input.

## Keyring unlock

The default GNOME keyring is checked without reading secrets. If locked, the
native GCR prompt is displayed on Sway; SecretStorage maintains the same D-Bus
connection until the human finishes. No password passes through the menu
service. Unlock normally lasts until reboot or explicit relocking. This is a
keyring prompt, not a polkit authentication policy change.

## HTTPS and session lifetime

Caddy terminates HTTPS/WSS at `https://browser.internal`; HTTP redirects there.
WayVNC stays on loopback. Only the public Caddy root is versioned in
`certs/browser-root.crt`. NixOS trusts it on client/coordinator, and Home Manager
imports it into the Chrome NSS database. Preserve the private CA in coordinator's
`/var/lib/caddy/.local/share/caddy/pki/authorities/local`; replacing that CA requires
updating the pinned public certificate and rebuilding both machines.

The Chrome panel has **End session** for immediate graceful closure. After the
last WayVNC client disconnects, a session gets five minutes to reconnect, then
systemd stops its Chrome processes, WayVNC and Sway. The menu service checks
every five seconds; contract tests cover the 300-second boundary. Profiles survive.

Chrome launchers are separate systemd units tied to the desktop using PartOf,
with background mode disabled. There is no compositor/WayVNC boot dependency.
The remote seat uses Bibata Modern Amber at 24px.

## Validation

Coordinator and NAS were activated on 2026-09-12. Client-side checks verified DNS,
the HTTPS viewer and WebSocket upgrade, in Chrome on both client and coordinator
without certificate bypasses. Terminating the desktop processes verified
automatic restart and viewer reconnection. Live checks covered End session, cold
restart, two viewers, reconnect resetting the grace period, and actual shutdown
at an expired test deadline. The Chrome sidebar was validated against a
disposable real Chrome profile. Regression checks cover origin validation,
unknown profiles, the one-action-at-a-time lock and the idle boundary.

The native locked-keyring prompt still needs its first human check after
reboot/relocking; the tests do not relock the user's keyring.
