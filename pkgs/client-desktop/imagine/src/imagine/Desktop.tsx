// Agency's local composition of the public Manganese desktop packages.
// Window/chrome action wiring derives from stock 67c29a9, MIT (LICENSE).
import { useDisplays } from "@domicile-desktop/component-library/DisplayProvider";
import { applyFont } from "@domicile-desktop/component-library/font";
import { createHandle } from "@domicile-desktop/component-library/Popover";
import { PortalDialogs } from "@domicile-desktop/component-library/PortalDialogs";
import { createToastManager } from "@domicile-desktop/component-library/Toaster";
import { BarContext } from "@domicile-desktop/manganese-bar/bar-context";
import { PanelKeyboardContext } from "@domicile-desktop/manganese-bar/panel-keyboard";
import { useNightLight } from "@domicile-desktop/manganese-bar-module-brightness/useNightLight";
import { maintainDisplayTemperatures } from "./display-temperatures";
import { ClockOptionsContext } from "@domicile-desktop/manganese-bar-module-clock/clock-options";
import { deskIdleInhibitor } from "@domicile-desktop/manganese-bar-module-idle-inhibitor/desk-idle-inhibitor";
import { deskKeymaps } from "@domicile-desktop/manganese-bar-module-keymap/desk-keymaps";
import { KeymapOptionsContext } from "@domicile-desktop/manganese-bar-module-keymap/keymap-options";
import { PortalSignIn } from "@domicile-desktop/manganese-bar-module-network/PortalSignIn";
import { useCaptivePortal } from "@domicile-desktop/manganese-bar-module-network/useCaptivePortal";
import { Tray } from "@domicile-desktop/manganese-bar-module-tray";
import { useExtensions } from "@domicile-desktop/manganese-bar-module-tray/extensions/useExtensions";
import { useOpenedPopup } from "@domicile-desktop/manganese-bar-module-tray/extensions/useOpenedPopup";
import { TrayContext } from "@domicile-desktop/manganese-bar-module-tray/tray-context";
import { trayEntries } from "@domicile-desktop/manganese-bar-module-tray/tray-entry";
import { useTray } from "@domicile-desktop/manganese-bar-module-tray/useTray";
import { useTrayOrder } from "@domicile-desktop/manganese-bar-module-tray/useTrayOrder";
import { Clipboard } from "@domicile-desktop/manganese-clipboard/Clipboard";
import { useClipboard } from "@domicile-desktop/manganese-clipboard/useClipboard";
import { sharedIconTheme } from "@domicile-desktop/manganese-host/followed-icon-theme";
import { useShellOptions } from "@domicile-desktop/manganese-host/useShellOptions";
import { appSearch } from "@domicile-desktop/manganese-launcher/app-search";
import type { ApplicationsConfig } from "@domicile-desktop/manganese-launcher/applications-config";
import { Launcher } from "@domicile-desktop/manganese-launcher/Launcher";
import { LaunchKind } from "@domicile-desktop/manganese-launcher/launch";
import type { Launch } from "@domicile-desktop/manganese-launcher/launch";
import { LauncherContext } from "@domicile-desktop/manganese-launcher/launcher-context";
import { OpenWith } from "@domicile-desktop/manganese-launcher/OpenWith";
import { useOpeningApps } from "@domicile-desktop/manganese-launcher/useOpeningApps";
import { Lock } from "@domicile-desktop/manganese-lock/Lock";
import { useLocked } from "@domicile-desktop/manganese-lock/useLocked";
import { NotificationDrawer } from "@domicile-desktop/manganese-notifications/NotificationDrawer";
import { NotificationToasts } from "@domicile-desktop/manganese-notifications/NotificationToasts";
import { Notifications } from "@domicile-desktop/manganese-bar-module-notifications";
import { NotificationsContext } from "@domicile-desktop/manganese-notifications/notifications-context";
import { useNotifications } from "@domicile-desktop/manganese-notifications/useNotifications";
import { useNow } from "@domicile-desktop/manganese-notifications/useNow";
import { QuickSettings } from "@domicile-desktop/manganese-quick-settings";
import { desktopClientIcons } from "@domicile-desktop/manganese-window-management/client-icons";
import type { FloatingRules } from "@domicile-desktop/manganese-window-management/floating/floating-rules";
import { useModifiers } from "@domicile-desktop/manganese-window-management/keyboard/useModifiers";
import { shownWindowsOf } from "@domicile-desktop/manganese-window-management/screens/shown-windows";
import { useScreenFollowsPointer } from "@domicile-desktop/manganese-window-management/screens/useScreenFollowsPointer";
import { useStageScreens } from "@domicile-desktop/manganese-window-management/screens/useStageScreens";
import { Stage } from "@domicile-desktop/manganese-window-management/Stage";
import { useClientIcons } from "@domicile-desktop/manganese-window-management/useClientIcons";
import { usePointerWarp } from "@domicile-desktop/manganese-window-management/usePointerWarp";
import { WindowKind } from "@domicile-desktop/manganese-window-management/window";
import { activeIsPrivate, closedBrowsersOf, screenOfApp, WindowAction, WindowActionKind } from "@domicile-desktop/manganese-window-management/window-state";
import { WorkspacesContext } from "@domicile-desktop/manganese-window-management/workspaces-context";
import { useDomicile } from "@domicile-desktop/react/domicile-provider";
import { useSharedWatch } from "@domicile-desktop/react/use-shared-watch";
import { previewFile } from "@domicile-desktop/sdk/file-preview";
import { ownedChords } from "@domicile-desktop/sdk/own-keybindings";
import type { ShellKeybindings } from "@domicile-desktop/sdk/own-keybindings";
import { opens } from "@domicile-desktop/system-apps/opens";
import { useAutoBrightness } from "@domicile-desktop/system-backlight/react";
import { options } from "./options";
import { useCallback, useEffect, useEffectEvent, useLayoutEffect, useMemo, useRef, useState } from "react";
import { outputToward, useAgencyKeys } from "./AgencyKeys";
import { Finder } from "./Finder";
import { windowsIn } from "./GaplessFrames";
import { agencyScreens } from "./layout";
import { useImagineSnapshot } from "./ipc/useImagineSnapshot";
import { chromeCommand, presentChrome, pruneChromeVisibility, roundedChromeCss } from "./ChromeVisibility";
import { NativeNotices, useCasting, useMediaNotices } from "./NativeUi";
import type { AgencyPolicy } from "./policy";
import { stageActionsOf } from "./StageActions";
import { AMBIENT_CHAT_APPS } from "./AmbientChat";
import type { AmbientChatConfig } from "./AmbientChat";
import { useAmbientChat } from "./useAmbientChat";
import { ChatComposer, useChatComposer } from "./ChatComposer";
import { isAgentDesktopId, useAgentWindows } from "./AgentWindows";
import { useSessionCatalogue } from "./useSessionCatalogue";
import { useRestartRecovery, RestartRecovery } from "./useRestartRecovery";
import { SessionCatalogue } from "./SessionCatalogueView";
import type { ChatWindowOptions } from "./ChatWindow";
import { useAgencyWindows } from "./useAgencyWindows";
import { AGENCY_RAIL_WIDTH, WorkspaceRail } from "./WorkspaceRail";
import { useWorkspaceMotion, WORKSPACE_MOTION_CSS } from "./WorkspaceMotion";

const EMPTY: readonly string[] = [];
const NO_LOCK_BAR = () => null;
const afterPaint = (then: () => void) => requestAnimationFrame(() => requestAnimationFrame(then));

export const Desktop = ({ applications, floating, keybindings, policy, ambientChat, chatWindow, webBrowser, sessionCatalogue, layoutPersistence, displayTemperatures }: {
  displayTemperatures?: import("./display-temperatures").DisplayTemperatures;
  displayTemperatures?: import("./display-temperatures").DisplayTemperatures;
  applications: ApplicationsConfig;
  floating: FloatingRules;
  keybindings: ShellKeybindings;
  policy?: AgencyPolicy | undefined;
  ambientChat?: AmbientChatConfig | undefined;
  chatWindow?: ChatWindowOptions | undefined;
  webBrowser?: import("./WebBrowser").WebBrowserOptions | undefined;
  sessionCatalogue?: import("./SessionCatalogue").CatalogueOptions | undefined;
  layoutPersistence?: import("./useLayoutPersistence").LayoutPersistenceOptions | undefined;
}) => {
  const motionRoot = useWorkspaceMotion();
  const domicile = useDomicile();
  const displays = useDisplays();
  const shellOptions = useShellOptions(domicile, options);
  const windows = useAgencyWindows(domicile, displays, floating,
    ambientChat === undefined ? EMPTY : AMBIENT_CHAT_APPS, undefined, policy, webBrowser, layoutPersistence);
  const { act } = windows;
  const [railOpen, setRailOpen] = useState(false);
  const [finderOpen, setFinderOpen] = useState(false);
  // Presentation preferences belong to this running host-window ID only.
  const [hiddenChrome, setHiddenChrome] = useState<ReadonlySet<string>>(() => new Set());
  const liveWindowIds = useMemo(() => new Set(windows.windows.map(({ id }) => id)), [windows.windows]);
  useEffect(() => setHiddenChrome((current) => pruneChromeVisibility(current, liveWindowIds)), [liveWindowIds]);
  const baseScreens = useStageScreens(windows, displays);
  const framedScreens = useMemo(() => agencyScreens(baseScreens, windows,
    railOpen ? windows.focused : undefined, AGENCY_RAIL_WIDTH),
  [baseScreens, railOpen, windows.focused, windows.workspaces]);
  const chrome = useMemo(() => presentChrome(framedScreens, hiddenChrome), [framedScreens, hiddenChrome]);
  const screens = chrome.screens;
  const snapshotCommand = useImagineSnapshot({ domicile, state: windows, screens, displays });
  const focusedScreen = screens.find(({ geometry }) => geometry.name === windows.focused);
  const bounds = focusedScreen?.geometry.screen;
  const clientIcons = useClientIcons(domicile, windows.windows.flatMap((window) =>
    window.kind === WindowKind.App ? [window.desktopId] : []), desktopClientIcons);
  const { modifiers, spendShift } = useModifiers(domicile);
  const focusedPlacement = focusedScreen?.screenful.placements.find(({ id }) => id === windows.activeId);
  const focus = useMemo(() => focusedScreen === undefined ? undefined : {
      box: focusedPlacement?.surface ?? focusedPlacement?.bar ?? focusedScreen.geometry.screen,
      frame: focusedPlacement?.frame ?? focusedScreen.geometry.screen,
      id: focusedPlacement?.id,
    }, [focusedScreen, focusedPlacement]);
  const shown = useMemo(() => screens.flatMap(({ screenful }) =>
    screenful.placements.map(({ id, frame }) => ({ id, box: frame }))), [screens]);
  const openWindows = useMemo(() => windows.windows.map(({ id }) => id), [windows.windows]);
  const pointer = usePointerWarp({ domicile, pressed: windows.pressed, focus, shown, windows: openWindows });
  useScreenFollowsPointer({ act, displays, focused: windows.focused });

  const apps = useMemo(() => appSearch(domicile, applications, sharedIconTheme(domicile)), [applications, domicile]);
  const opening = useOpeningApps(apps.opening, windows.launcherOpen || finderOpen);
  const [query, setQuery] = useState("");
  const [foundApps, setFoundApps] = useState(opening.apps);
  const [finding, setFinding] = useState(false);
  const [finderError, setFinderError] = useState<string>();
  const queryVersion = useRef(0);
  useEffect(() => {
    if (!finderOpen) return;
    const version = ++queryVersion.current;
    setFinding(true);
    setFinderError(undefined);
    apps.search(query).then(({ apps }) => {
      if (version === queryVersion.current) setFoundApps(apps);
    }).catch((error: unknown) => {
      if (version === queryVersion.current) setFinderError(String(error));
    }).finally(() => {
      if (version === queryVersion.current) setFinding(false);
    });
    return () => { queryVersion.current += 1; };
  }, [apps, finderOpen, query]);
  const showFinder = () => { setFinderOpen(true); domicile.windows.focusShell(); };
  const closeFinder = () => { setFinderOpen(false); setQuery(""); };
  const workspaceViews = useMemo(() => windows.workspaces.map((workspace) => ({
    name: workspace.name,
    windowCount: (workspace.tiling.root === undefined ? 0 : windowsIn(workspace.tiling.root).length)
      + workspace.floats.reduce((n, float) => n + windowsIn(float.root).length, 0),
  })), [windows.windows, windows.workspaces]);
  const windowViews = useMemo(() => windows.windows.flatMap((window) => {
    const workspace = windows.workspaces.find((workspace) =>
      (workspace.tiling.root !== undefined && windowsIn(workspace.tiling.root).includes(window.id)) ||
      workspace.floats.some((float) => windowsIn(float.root).includes(window.id)));
    return workspace === undefined ? [] : [{ id: window.id, title: window.title,
      appName: window.kind === WindowKind.App ? window.desktopId : undefined, workspace: workspace.name }];
  }), [windows.windows, windows.workspaces]);

  const clipboard = useClipboard(domicile);
  const extensions = useExtensions(domicile);
  const tray = useTray(domicile);
  const trayOrder = useTrayOrder(trayEntries(tray, extensions, []).map(({ key }) => key));
  const popup = useOpenedPopup(domicile, extensions, windows.focused);
  const [toasts] = useState(createToastManager);
  const notifications = useNotifications(domicile, toasts, EMPTY, EMPTY);
  const now = useNow();
  const [notificationsHandle] = useState(createHandle);
  const [notificationsOn, setNotificationsOn] = useState<string>();
  const [notificationsOpen, setNotificationsOpen] = useState(false);
  const showNotifications = (screen: string) => {
    setNotificationsOn(screen); setNotificationsOpen(true); notifications.read(); toasts.close();
  };
  const lock = useLocked(domicile);
  const casting = useCasting(domicile);
  const portal = useCaptivePortal(domicile);
  const media = useMediaNotices(domicile);
  const keymaps = useSharedWatch(deskKeymaps(domicile));
  const [keymapSwitches, setKeymapSwitches] = useState(0);
  const [heldPanels, setHeldPanels] = useState(0);
  const holdKeyboard = useCallback(() => {
    setHeldPanels((held) => held + 1);
    return () => setHeldPanels((held) => held - 1);
  }, []);
  useAutoBrightness(domicile, shellOptions.brightness.automatic);
  useEffect(() => {
    if (displayTemperatures === undefined) return;
    return maintainDisplayTemperatures(domicile.displays, displayTemperatures,
      (message) => console.error(message));
  }, [displayTemperatures, domicile]);

  useLayoutEffect(() => applyFont(shellOptions.font), [shellOptions.font]);
  const virtual = useRef<Awaited<ReturnType<typeof domicile.displays.addVirtual>>[]>([]);
  const otherPanel = !windows.layoutReady || finderOpen || windows.launcherOpen || windows.clipboardOpen ||
    popup.opened !== undefined || portal.url !== undefined || notificationsOpen || heldPanels > 0 || lock.locked;
  const composer = useChatComposer({ domicile, config: chatWindow, state: windows, blocked: otherPanel,
    place: windows.placeChat, reserve: windows.reserveChat });
  const behindPanel = otherPanel || composer.open;
  const agentCommand = useAgentWindows({ domicile, windows, blocked: behindPanel });
  const chats = useSessionCatalogue({ domicile, config: sessionCatalogue, chatLauncher: chatWindow?.launcher,
    state: windows, blocked: behindPanel, act, place: windows.placeChat, reserve: windows.reserveChat });
  const recovery = useRestartRecovery({ domicile, enabled: layoutPersistence?.restartRecovery === true,
    windows, catalogue: chats.catalogue, server: sessionCatalogue?.server, chatLauncher: chatWindow?.launcher,
    terminalLauncher: sessionCatalogue?.terminalLauncher, blocked: behindPanel });
  const ambient = useAmbientChat({ domicile, config: ambientChat, state: windows,
    blocked: behindPanel,
    transition: windows.transitionAmbient });
  const stageFocusRequest = useEffectEvent((id: string) => {
    if (!ambient.consumesFocusRequest(id) && !windows.windows.some(w =>
      w.id === id && w.kind === WindowKind.App && isAgentDesktopId(w.desktopId))) act(WindowAction.FocusRequested(id));
  });
  // Preserve stable Stage callbacks even while native frames repaint. The
  // Effect Event reads the current optional controller without re-binding.
  const stageActions = useMemo(() => ({ ...stageActionsOf(act, pointer.pointing),
    onFocusRequest: (id: string) => stageFocusRequest(id),
  }), [act, pointer.pointing]);
  const onAction = (action: WindowAction) => {
    switch (action.kind) {
      case WindowActionKind.MediaKeyPressed: media.pressKey(action.key); return;
      case WindowActionKind.KeymapSelected:
        void domicile.keyboard.selectKeymap(action.choice).then((result) => result.match({
          Err: (error) => console.error("Agency keymap refused", error),
          Ok: () => setKeymapSwitches((count) => count + 1),
        })); return;
      case WindowActionKind.NotificationsToggled:
        if (notificationsOpen) setNotificationsOpen(false); else showNotifications(windows.focused); return;
      case WindowActionKind.NotificationsCleared:
        notifications.dismiss(notifications.items.map(({ id }) => id)); return;
      case WindowActionKind.IdleInhibitorToggled: deskIdleInhibitor(domicile).toggle(); return;
      case WindowActionKind.NightLightToggled: deskNightLight(domicile).toggle(); return;
      case WindowActionKind.VirtualMonitorAdded:
        void domicile.displays.addVirtual({ ...action.size, name: "Virtual monitor", refreshMhz: 60000 })
          .then((result) => { virtual.current.push(result); result.match({ Err: console.error, Ok: () => undefined }); }); return;
      case WindowActionKind.VirtualMonitorRemoved:
        virtual.current.pop()?.match({ Err: console.error, Ok: (monitor) => { monitor.remove(); } }); return;
      default: spendShift(); act(action); act(WindowAction.KeyPressed());
    }
  };
  const keys = useAgencyKeys({ domicile, keybindings, mode: windows.mode,
    modal: windows.launcherOpen || finderOpen || composer.open, onAction, chatWindow: chatWindow?.bindAltEnter === true,
    onModeChanged: (mode) => act(WindowAction.ModeSet(mode)),
    onAgency: (args) => {
      if (snapshotCommand(args)) return;
      if (agentCommand(args)) return;
      if (composer.command(args)) return;
      if (ambient.command(args)) return;
      if (lock.locked) return;
      if (args[0] === "layout-recovery" && args.length === 2) {
        if (behindPanel) return;
        if (args[1] === "restore") void recovery.restore();
        else if (args[1] === "save") void recovery.saveForRestart();
        return;
      }
      if (args[0] === "native-app" && args.length === 3 &&
        ["focus", "focus-tag"].includes(args[1] ?? "") && args[2]) {
        const identity = args[2];
        if (args[1] === "focus-tag" && !/^agencychat[0-9a-f]{32}$/.test(identity)) return;
        const matches = windows.windows.filter((window) => window.kind === WindowKind.App &&
          (args[1] === "focus" ? window.desktopId === identity : window.desktopId.includes(identity)));
        if (matches.length === 1 && !finderOpen && !windows.launcherOpen && !composer.open) {
          act(WindowAction.WindowSelected(matches[0]!.id));
        }
        return;
      }
      const decision = chromeCommand(hiddenChrome, args, windows.activeId, liveWindowIds);
      if (decision.handled) {
        if (decision.error !== undefined) console.error(decision.error);
        else setHiddenChrome((current) => chromeCommand(current, args, windows.activeId, liveWindowIds).hidden);
        return;
      }
      if (args[0] === "output" && args.length === 2 && (args[1] === "up" || args[1] === "down")) {
        if (finderOpen || windows.launcherOpen) return;
        const target = outputToward(windows.screens, windows.focused, args[1]);
        if (target !== undefined) {
          act(WindowAction.ScreenHovered(target));
          act(WindowAction.KeyPressed());
        }
      } else if (args[0] === "brightness" && ["up", "down", "max", "toggle"].includes(args[1] ?? "") &&
        (args.length === 2 || (args.length === 3 && args[2] === "fine"))) {
        media.requestBrightness(args[1] as "up" | "down" | "max" | "toggle", args[2] === "fine");
      } else if (args[0] === "media" && args.length === 2 &&
        ["play-pause", "previous", "next"].includes(args[1] ?? "")) {
        media.requestMedia(args[1] as "play-pause" | "previous" | "next");
      } else if (args.join(" ") === "rail toggle") setRailOpen((open) => !open);
      else if (args.join(" ") === "finder toggle") {
        if (finderOpen) closeFinder(); else showFinder();
      } else console.error("Unknown Agency command", args);
    },
  });

  const [picked, setPicked] = useState<Launch>();
  const [openingWith, setOpeningWith] = useState<string>();
  const launch = (pick: Launch) => {
    switch (pick.kind) {
      case LaunchKind.Ran: act(WindowAction.AppLaunched(pick.command)); break;
      case LaunchKind.Opened: act(WindowAction.FileOpened(pick.path)); break;
      case LaunchKind.OpenedWith: setOpeningWith(pick.path); break;
      case LaunchKind.Browsed: act(WindowAction.BrowserOpened(pick.url, pick.isPrivate)); break;
    }
  };
  const current = Object.fromEntries(screens.map(({ current, geometry }) => [geometry.name, current]));
  const nativeControls = <BarContext value={{ locked: false, popsUp: true, screen: windows.focused }}>
    <div style={{ display: "flex", gap: 8, alignItems: "center" }}><Tray /><QuickSettings /><Notifications /></div>
  </BarContext>;

  return <WorkspacesContext value={{ current, focused: windows.focused, homes: windows.homes,
    mode: windows.mode, select: (name) => act(WindowAction.WorkspaceSelected(name)) }}>
    {displayTemperatures === undefined && <ScheduledNightLight options={shellOptions.nightLight} />}
    <LauncherContext value={{ toggle: () => act(WindowAction.LauncherToggled()) }}>
      <NotificationsContext value={{ handle: notificationsHandle, unread: notifications.unread,
        doNotDisturb: notifications.doNotDisturb }}>
        <TrayContext value={{ clicked: popup.clicked, extensions, items: tray, open: popup.open,
          opened: popup.opened, order: trayOrder }}>
          <PanelKeyboardContext value={holdKeyboard}>
            <ClockOptionsContext value={shellOptions.clock}><KeymapOptionsContext value={shellOptions.keymap}>
              <div className="agency-desktop" ref={motionRoot}>
                <style>{WORKSPACE_MOTION_CSS}</style>
                <style>{`:root,body{background:#000!important}.agency-desktop [data-focus-box]{box-shadow:none!important;outline:1px solid #303030;outline-offset:-1px}` + roundedChromeCss(chrome.roundedWindows)}</style>
                {screens.length > 0 && windows.layoutReady && <Stage activeId={windows.activeId} behindPanel={behindPanel}
                  clientIcons={clientIcons} domicile={domicile} draggingId={windows.draggingId}
                  focusedId={windows.focusedId} modifiers={modifiers} {...stageActions}
                  popups={windows.popups} scratchpad={windows.scratchpad} screens={screens} windows={windows.windows} />}
                <WorkspaceRail open={railOpen && !lock.locked} bounds={bounds} workspaces={workspaceViews}
                  currentWorkspace={focusedScreen?.current ?? "1"} onClose={() => setRailOpen(false)}
                  onSelectWorkspace={(name) => act(WindowAction.WorkspaceSelected(name))}
                  onOpenFinder={showFinder} onOpenNotifications={() => showNotifications(windows.focused)}
                  onNewChat={chatWindow === undefined ? undefined : () => composer.command(["chat-window", "open"])}
                  nativeChats={sessionCatalogue === undefined ? undefined : <><SessionCatalogue controller={chats} blocked={behindPanel} /><RestartRecovery recovery={recovery} blocked={behindPanel} /></>}
                  status={windows.layoutError} nativeControls={nativeControls} />
                <Finder open={finderOpen && !lock.locked} bounds={bounds} workspaces={workspaceViews}
                  windows={windowViews} apps={[{ id: "agency:settings", name: "Quick settings", detail: "Open native controls in the workspace rail" }, ...foundApps]}
                  onQueryChange={setQuery} loading={finding} status={finderError} onClose={closeFinder}
                  onLaunchApp={(id) => {
                    if (id === "agency:settings") { setRailOpen(true); return; }
                    const app = foundApps.find((app) => app.id === id);
                    if (app !== undefined) afterPaint(() => act(WindowAction.AppLaunched(app.command)));
                  }}
                  onSelectWorkspace={(name) => act(WindowAction.WorkspaceSelected(name))}
                  onSelectWindow={(id) => act(WindowAction.WindowSelected(id))} />
                <ChatComposer composer={composer} bounds={bounds} />
                <Launcher fromPrivate={activeIsPrivate(windows)} glances={new Map()} open={windows.launcherOpen}
                  opening={opening} screen={windows.focused} searchApps={apps.search}
                  search={(query) => domicile.files.search(query)} preview={(path) => previewFile(domicile, path)}
                  opens={async (path) => (await opens(domicile, path)).unwrapOrElse((error) => { throw error; })}
                  onDismiss={() => act(WindowAction.LauncherDismissed())}
                  onLaunch={(pick) => { setPicked(pick); act(WindowAction.LauncherDismissed()); }}
                  onClosed={() => { if (picked !== undefined) { const pick = picked; setPicked(undefined); afterPaint(() => launch(pick)); } }} />
                {openingWith !== undefined && <OpenWith domicile={domicile} path={openingWith}
                  screen={windows.focused} onClose={() => setOpeningWith(undefined)}
                  onOpen={(argv) => { setOpeningWith(undefined); act(WindowAction.AppLaunched(argv)); }} />}
                <PortalSignIn screen={windows.focused} url={portal.url} onDismiss={portal.dismiss} />
                <Clipboard entries={clipboard} open={windows.clipboardOpen} screen={windows.focused}
                  onCopy={(id) => domicile.clipboard.copy(id)} onDismiss={() => act(WindowAction.ClipboardDismissed())} />
                <NotificationToasts manager={toasts} now={now} onAction={notifications.invoke}
                  onReply={notifications.reply} screen={windows.focused} shown={!(lock.locked || casting)} />
                <NativeNotices screen={windows.focused} press={media.press} choice={lock.locked ? undefined : media.choice}
                  keymap={keymapSwitches === 0 || keymaps === undefined
                  ? undefined : { count: keymapSwitches, name: keymaps.active,
                    description: keymaps.keymaps.find(({ name }) => name === keymaps.active)?.description }} />
                <NotificationDrawer doNotDisturb={notifications.doNotDisturb} handle={notificationsHandle}
                  items={notifications.items} now={now} onAction={notifications.invoke}
                  onClose={() => setNotificationsOpen(false)} onDismiss={notifications.dismiss}
                  onDoNotDisturb={notifications.setDoNotDisturb} onOpen={showNotifications} onReply={notifications.reply}
                  open={notificationsOpen && !lock.locked} screen={notificationsOn} />
                <PortalDialogs closedBrowsers={closedBrowsersOf(windows)} domicile={domicile}
                  holdKeyboard={holdKeyboard} omitScreenCasts={false} screen={windows.focused}
                  screenOf={(id) => screenOfApp(windows, id)} shellChords={ownedChords(keys)}
                  shownWindows={() => shownWindowsOf(screens)} />
                <Lock bar={NO_LOCK_BAR} checking={lock.checking} locked={lock.locked} onUnlock={lock.unlock}
                  refusals={lock.refusals} refused={lock.refused} screen={windows.focused} />
              </div>
            </KeymapOptionsContext></ClockOptionsContext>
          </PanelKeyboardContext>
        </TrayContext>
      </NotificationsContext>
    </LauncherContext>
  </WorkspacesContext>;
};

// Mount the public global policy only when no fixed per-output policy is supplied.
const ScheduledNightLight = ({ options }: { options: Parameters<typeof useNightLight>[1] }) => {
  useNightLight(useDomicile(), options);
  return null;
};
