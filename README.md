# Dots-Zen Configuration

This repository contains my personal configuration files (dotfiles) organized for a minimal and efficient setup, managed with chezmoi. Each section below displays the contents of the corresponding configuration files, making it easy to browse the settings while maintaining a clean directory structure.

## Fish Shell

<details>
<summary>View Fish Shell Configuration</summary>

[View Fish Configuration File](shortcuts/fish.md)

</details>

## Neovim

<details>
<summary>View Neovim Configuration</summary>

[View Neovim Configuration File](shortcuts/nvim.md)

</details>

## Sway Window Manager

<details>
<summary>View Sway Configuration</summary>

[View Sway Configuration File](shortcuts/sway.md)

</details>

## Terminal

<details>
<summary>View Terminal Configuration</summary>

[View Terminal Configuration File](shortcuts/terminal.md)

</details>

## Vim

<details>
<summary>View Vim Configuration</summary>

[View Vim Configuration File](shortcuts/vim.md)

</details>

---

## Installation Instructions

1. Create all service files in ~/.config/systemd/user/
2. Reload systemd daemon:
   ```bash
   systemctl --user daemon-reload
   ```

3. Enable the scroll-session.target and all services:
   ```bash
   systemctl --user enable scroll-session.target
   systemctl --user enable gnome-keyring.service
   systemctl --user enable polkit-agents.service
   systemctl --user enable wl-gammarelay.service
   systemctl --user enable kanshi.service
   systemctl --user enable swaybg.service
   systemctl --user enable cliphist-text.service
   systemctl --user enable cliphist-image.service
   systemctl --user enable gtk-settings.service
   systemctl --user enable mako.service
   ```

4. Remove the corresponding exec lines from ~/.config/scroll/config:
   - Lines 54-57 (authentication agents)
   - Line 59 (wl-gammarelay-rs)
   - Line 60 (mako)
   - Lines 61-62 (clipboard management)
   - Line 63 (kanshi)
   - Line 64 (swaybg)
   - Lines 28-38 (gsettings - now handled by gtk-settings.service)

## Notes

- All services use `PartOf=scroll-session.target` to ensure they stop when the session ends
- Services are distributed across appropriate slices:
  - `session-graphical.slice`: Core session services (auth, keyring, settings)
  - `background-graphical.slice`: Background daemons (kanshi, mako, clipboard, etc.)
  - `app-graphical.slice`: Would be used for user-facing applications
- The `PassEnvironment=WAYLAND_DISPLAY` ensures services get the Wayland display from UWSM
- Services that need to start early use `After=graphical-session-pre.target`
- Services that need Wayland use `After=wayland-session@scroll.desktop.target`
- Restart policies ensure services recover from crashes
- The polkit-agents service tries multiple agents in order of preference
