# Tacit Kit on the Zenbook

Open **http://localhost:8765** on the Zenbook. The controller binds only to
127.0.0.1. Its four examples are actual Quickshell windows importing Tacit.Kit:

- **Controls:** text entry, switch, slider, checkbox and choices.
- **Lists and search:** search, keyboard selection and inline rename.
- **Actions and feedback:** add/remove sample items, Undo, confirmation and progress.
- **Tabs, menus and panels:** tabs, selection, menu and animated details panel.

Use the numbered walkthrough or Spawn/Close beside each example. Closing inside
a window is also supported. The expandable native-values section shows changes
reported by the QML windows. Sample names and actions never touch real files.
Dusk/Moss and reduced motion affect these examples only.

## Running it

The initial trial was built on strix-coordinator and installed into Tom's Nix
profile on client on 2026-11-03, together with Quickshell 0.3.0. The installed
package is `/nix/store/yh7hccj1nilawgmchjic40ga7s9lwpnq-tacit-kit-trial-0.1.0`.
Its dependencies include Qt 6.11.2, the Tacit fonts and symbols, the QML module,
sample palettes and Python. TacitOS itself is not required.

The initial controller is a manually started transient user service:

```sh
systemctl --user status tacit-kit-trial
systemctl --user stop tacit-kit-trial
```

Stopping it closes only the native examples it owns. To run it again, use a
terminal in the Zenbook's desktop session:

```sh
tacit-kit-trial
# Optional alternate port:
tacit-kit-trial --port 8766
```

Then open the address it prints. `tacit-qs -p /path/to/app.qml` launches other
Tacit apps with the packaged import path. `qs` is also installed directly.
No boot service, timer, compositor change, reboot or full system switch is
part of this trial.

`home/client-apps.nix` includes Quickshell and the trial for future display-host
deployments. The current profile installation is already usable independently.
After that declaration is deployed, remove the temporary profile entries by
their names from `nix profile list` so they do not override later system versions.

## Source and licence

Upstream is [ciscobugger/tacit-kit](https://github.com/ciscobugger/tacit-kit), pinned
to `f34574dae85aec2eb9e8835cc1dfece87cdfdf2d`. The kit is LGPL-3.0-or-later,
its bundled fonts are OFL-1.1, and its documentation is CC BY 4.0; see the
[upstream licence section](https://github.com/ciscobugger/tacit-kit#licence).
The package preserves upstream code, fonts, notices and licences.

The stdlib HTTP controller runs only four fixed QML paths. Mutations require a
per-run token, JSON and a local Host/Origin. It tracks its own child processes
and targets their exact PIDs for Quickshell IPC. It exposes no shell-command or
arbitrary-file API. It makes no changes to the live Tacit wallpaper state.

## Verification

On 2026-11-03 the package built on strix-coordinator. The installed runtime test
passed under `runtime-test`, using Qt offscreen rendering. It covers four real
Quickshell startups, native IPC, live palette propagation, reduced motion,
close/respawn, and rejection of foreign or invalid requests:

```sh
runtime-test -- env TACIT_TRIAL_PACKAGE=/nix/store/…-tacit-kit-trial-0.1.0 \
  python3 tests/tacit-kit-trial/test_runtime.py
```

An isolated headless Chromium run exercised the page's actual Spawn, Close all,
walkthrough, palette and reduced-motion controls, with no JavaScript exceptions.
All four QML examples rendered on Dusk and Moss, with no QML errors, and passed
upstream's component/style lint. Client Home Manager evaluates with both new
packages, and its derivation matches the built package. On the physical Zenbook,
Sway and native IPC confirmed the walkthrough and Controls window running.
The first dedicated workspace was hidden after switching workspaces; both
windows were moved into Tom's visible workspace 6 at his report.

QA screenshots and the one-off browser harness are on the NAS under
`~/.cache/tacit-kit-trial/qa/`; test inputs and build output are on compute under
`/var/tmp/tacit-kit-trial/`. No live session was restarted.
