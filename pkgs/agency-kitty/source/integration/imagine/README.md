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
native-drag fixture. All130 Imagine tests passed; the full Vite production build
passed (existing large-chunk warning retained). This is source/build evidence;
no live shell refresh or client engine transition has been performed.
