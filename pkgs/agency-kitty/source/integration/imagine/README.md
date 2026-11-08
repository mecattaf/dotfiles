# Native terminal catalogue in Imagine

Apply `native-catalogue.patch` after the native-drag source commit
`8affac9b705f7af18b603dc1ba793389b72c1590`.
It extends the existing SessionCatalogue model, controller and buttons, keeping
DSH terminals and native terminals as distinct providers. It does not edit
Desktop, AgencyKeys, the engine or Nix deployment configuration.

The existing configuration accepts `nativeTerminalLauncher`, an absolute path
to the installed agency-kitty executable. Only an explicit human resume click
invokes its fixed `desktop-resume-request` action. Existing windows focus through
the current reducer. Pending windows retain existing reservations and respect
lock, modal state and later navigation. Native classes match exactly. Duplicate
matches refuse both movement and a new launch. Direct terminal rows focus an
existing OS window but never resume, and their metadata is removed when the NAS
PTY owner ends. See ../agency-chat-window for the NAS metadata patch.

Qualification used the exact pinned SDK workspace dependency donor from the
native-drag fixture. All135 Imagine tests passed; the full Vite production build
passed (existing large-chunk warning retained). This is source/build evidence;
no live shell refresh or client engine transition has been performed.

The existing reservation owner now requires exact native classes and a validated
helper receipt before placement. A pre-receipt appearance preserves previous
focus; closed previous windows retain the reducer's valid fallback. A newer
focus choice within the same workspace cancels late reveal too. The production
TS check has zero new diagnostics versus the exact drag-qualified base: both
retain18 dependency diagnostics, so a full-project type-check pass is not claimed.

Native terminal resume also works when all numbered chat slots are occupied: it
can join the chosen chat workspace or the current workspace as an ordinary
split. This removes a per-slot terminal restriction; it does not redesign the
existing desktop workspace inventory or change its global numbering policy.
