# Remote access + device mesh (wayvnc / Remmina / SSH)

Supersedes the abandoned Sunshine/Moonlight design. Decision (2026-07-05): drop
game-streaming entirely in favour of **wayvnc** (VNC server) + **Remmina** (VNC
client), which niri supports first-class in mainline — no unmerged niri PR needed.
Any device can view/reach any other; the whole thing is declarative.

## wayvnc (server, all hosts)
- Runs as a **home-manager systemd *user* service** bound to the niri
  `graphical-session.target` (no NixOS module exists). See `home/remote.nix`.
- niri mainline implements the protocols wayvnc needs (wlr-screencopy capture,
  wlr-virtual-pointer + virtual-keyboard input, wlr-data-control clipboard).
  ⚠️ Keys injected over VNC do **not** trigger niri's own compositor keybinds
  (Smithay virtual-keyboard limitation) — drive apps directly.
- **No auth on wayvnc itself.** Access is gated at the network layer: port 5900 is
  firewalled to the **tailnet only** (`networking.firewall.interfaces.tailscale0`
  in `modules/common.nix`) plus the trusted **Thunderbolt** link
  (`trustedInterfaces` in `modules/strix.nix`). Never exposed to LAN/wifi.

### Headless worker
wayvnc captures a wlr output, but a headless box lights no connector. Solved in
`hosts/worker/headless-display.nix` with **kernel EDID injection**
(`hardware.display.edid.modelines` → a 1080p blob built at eval time +
`hardware.display.outputs."DP-1"` forcing the connector). Plus greetd **autologin**
tom→niri so the session (and wayvnc) actually starts on a box nobody sits at.
wayvnc is pointed at that connector (`--output DP-1` in `home/remote.nix`).
⚠️ Verify the real connector name on first boot (`ls /sys/class/drm/`).

## Remmina (client, all hosts)
- `pkgs.remmina` (VNC built in). `home/remote.nix` generates a `.remmina` profile
  for every *other* host from the mesh registry → any box reaches any box.
- Passwords left blank (Remmina's per-user key isn't reproducible declaratively);
  first connect prompts once and can save into gnome-keyring.
- Launch: `remmina -c ~/.config/remmina/<host>.remmina`.

## GTK theming (Remmina + Nautilus, no nwg-look)
The old pain: on niri there is no XSettings/settings daemon, so GTK3 apps (Remmina)
and GTK4/libadwaita apps (Nautilus) ignored the home-manager theme until nwg-look
poked them. Fixed deterministically:
- **`GTK_THEME=MacTahoe-Dark-grey`** exported **system-wide** in `modules/common.nix`
  (`environment.sessionVariables`, so it reaches GUI apps via the PAM session) —
  the highest-priority GTK3 mechanism.
- **gtk-4.0 CSS symlinks** in `home/home.nix`: MacTahoe's `gtk-4.0/{gtk.css,
  gtk-dark.css,assets}` linked into `~/.config/gtk-4.0/` — the only override
  libadwaita/Nautilus honor. home-manager's `gtk` module does not do this.
- dconf `org.gnome.desktop.interface` keys as belt-and-suspenders.

## SSH mesh
Single source of truth: `modules/mesh-registry.nix` (per-host aliases + public
host key + tom's public user key). `modules/mesh.nix` derives
`programs.ssh.knownHosts` (zero-TOFU) + `users.tom.openssh.authorizedKeys` from it.
Deterministic host *identity* (so known_hosts is trustworthy before first boot)
comes from the **agenix** layer wiring the private host keys — see the secrets
design. Registry keys are filled per host as they are flashed; empty entries are
skipped so the config stays valid meanwhile.

## Files
- `home/remote.nix` — wayvnc service + Remmina package/profiles
- `hosts/worker/headless-display.nix` — EDID injection + autologin
- `modules/mesh-registry.nix` / `modules/mesh.nix` — the mesh + SSH trust
- `modules/common.nix` — GTK_THEME, dconf, VNC firewall
- `home/home.nix` — gtk-4.0 libadwaita symlinks + dconf theme keys
