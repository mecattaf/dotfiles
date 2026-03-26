//@ pragma UseWebEngine
//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env QT_WAYLAND_DISABLE_WINDOWDECORATION=1
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

import QtQuick
import Quickshell
import QtWebEngine
import QtWebChannel
import "bridges"
import "surfaces"

ShellRoot {
    id: root

    // Feature flags
    readonly property bool disableHotReload: Quickshell.env("WEBSHELL_DISABLE_HOT_RELOAD") === "1"
    readonly property string baseUrl: {
        var envUrl = Quickshell.env("WEBSHELL_URL")
        if (envUrl) return envUrl
        // Production: load from dist/ alongside this QML file
        return "file://" + Quickshell.shellDir + "/dist/index.html"
    }

    Component.onCompleted: {
        Quickshell.watchFiles = !disableHotReload

        // Register bridges on the WebChannel.
        // Names must match bridge.ts BRIDGE_SPECS[*].qobjectName exactly.
        try { channel.registerObject("AudioBridge", audioBridge) } catch (e) { console.warn("shell: failed to register AudioBridge:", e) }
        try { channel.registerObject("MprisBridge", mprisBridge) } catch (e) { console.warn("shell: failed to register MprisBridge:", e) }
        try { channel.registerObject("PowerBridge", powerBridge) } catch (e) { console.warn("shell: failed to register PowerBridge:", e) }
        try { channel.registerObject("NotificationBridge", notificationBridge) } catch (e) { console.warn("shell: failed to register NotificationBridge:", e) }
        try { channel.registerObject("TrayBridge", trayBridge) } catch (e) { console.warn("shell: failed to register TrayBridge:", e) }
        try { channel.registerObject("PolkitBridge", polkitBridge) } catch (e) { console.warn("shell: failed to register PolkitBridge:", e) }
        try { channel.registerObject("SessionBridge", sessionBridge) } catch (e) { console.warn("shell: failed to register SessionBridge:", e) }
        try { channel.registerObject("BluetoothBridge", bluetoothBridge) } catch (e) { console.warn("shell: failed to register BluetoothBridge:", e) }
        try { channel.registerObject("NetworkBridge", networkBridge) } catch (e) { console.warn("shell: failed to register NetworkBridge:", e) }
        try { channel.registerObject("ShellBridge", shellBridge) } catch (e) { console.warn("shell: failed to register ShellBridge:", e) }
        try { channel.registerObject("InputBridge", inputBridge) } catch (e) { console.warn("shell: failed to register InputBridge:", e) }
        try { channel.registerObject("BrightnessBridge", brightnessBridge) } catch (e) { console.warn("shell: failed to register BrightnessBridge:", e) }
        try { channel.registerObject("WallpaperBridge", wallpaperBridge) } catch (e) { console.warn("shell: failed to register WallpaperBridge:", e) }
        try { channel.registerObject("CommandBridge", commandBridge) } catch (e) { console.warn("shell: failed to register CommandBridge:", e) }

        // NiriBridge is registered as both WorkspacesBridge and WindowsBridge so
        // bridge.ts can hydrate os.workspaces and os.windows from the same QObject.
        try {
            channel.registerObject("WorkspacesBridge", niriBridge)
            channel.registerObject("WindowsBridge", niriBridge)
        } catch (e) {
            console.warn("shell: failed to register NiriBridge as WorkspacesBridge/WindowsBridge:", e)
        }

        console.info("shell: all bridges registered on WebChannel")
    }

    // -- WebChannel: single integration surface for all bridges --
    WebChannel {
        id: channel
    }

    // -- Bridge instances --
    AudioBridge        { id: audioBridge }
    MprisBridge        { id: mprisBridge }
    PowerBridge        { id: powerBridge }
    NotificationBridge { id: notificationBridge }
    TrayBridge         { id: trayBridge; menuParentWindow: barSurface }
    PolkitBridge       { id: polkitBridge }
    SessionBridge      { id: sessionBridge; lockscreen: lockscreenSurface }
    BluetoothBridge    { id: bluetoothBridge }
    NetworkBridge      { id: networkBridge }
    ShellBridge        { id: shellBridge; audioBridge: audioBridge }
    InputBridge        { id: inputBridge; niriBridge: niriBridge }
    NiriBridge         { id: niriBridge }
    BrightnessBridge   { id: brightnessBridge }
    WallpaperBridge    { id: wallpaperBridge }
    CommandBridge      { id: commandBridge }

    // -- Surfaces --
    // Each surface is a PanelWindow + WebEngineView loading a SolidJS route.
    // Required properties are passed explicitly (QML id scoping does NOT cross file boundaries).

    Bar {
        id: barSurface
        channel: channel
        shellBridge: shellBridge
        baseUrl: root.baseUrl
    }

    Dock {
        channel: channel
        shellBridge: shellBridge
        baseUrl: root.baseUrl
    }

    Notifications {
        channel: channel
        shellBridge: shellBridge
        notificationBridge: notificationBridge
        baseUrl: root.baseUrl
    }

    Osd {
        channel: channel
        audioBridge: audioBridge
        brightnessBridge: brightnessBridge
        shellBridge: shellBridge
        baseUrl: root.baseUrl
    }

    // -- Lockscreen: permanent instance (NOT in a Loader).
    // WlSessionLock MUST exist for the lifetime of the shell. Destroying it
    // while locked leaves the screen permanently locked by the compositor.
    // The lock surfaces are only created when lockRequested is true.
    Lockscreen {
        id: lockscreenSurface
        channel: channel
        baseUrl: root.baseUrl
    }

    // -- LazyLoaded surfaces: only instantiated when visible --

    Loader {
        active: shellBridge.ccdVisible
        sourceComponent: Component {
            CcdSidebar {
                channel: channel
                shellBridge: shellBridge
                baseUrl: root.baseUrl
            }
        }
    }

    Loader {
        active: shellBridge.overlayVisible
        sourceComponent: Component {
            Overlay {
                channel: channel
                shellBridge: shellBridge
                baseUrl: root.baseUrl
            }
        }
    }

    // v0.2.0 SHOULD: new surfaces
    Loader {
        active: shellBridge.settingsVisible
        sourceComponent: Component {
            Settings {
                channel: channel
                shellBridge: shellBridge
                baseUrl: root.baseUrl
            }
        }
    }

    Loader {
        active: shellBridge.wallpaperVisible
        sourceComponent: Component {
            Wallpaper {
                channel: channel
                shellBridge: shellBridge
                baseUrl: root.baseUrl
            }
        }
    }

    Loader {
        active: shellBridge.wizardVisible
        sourceComponent: Component {
            Wizard {
                channel: channel
                shellBridge: shellBridge
                baseUrl: root.baseUrl
            }
        }
    }
}
