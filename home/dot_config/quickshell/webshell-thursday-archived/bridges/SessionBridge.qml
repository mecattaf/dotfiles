// SessionBridge.qml -- Power actions: suspend, poweroff, reboot, logout, lock.
// Via loginctl/systemctl. Session info collection.
//
// Lock/unlock are implemented via WlSessionLock + PamContext in Lockscreen.qml.
// SessionBridge drives the lock state and forwards unlock requests.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    // ======================================================================
    // Public properties (os.session)
    // ======================================================================

    property bool ready: false

    property var info: ({
        user: Quickshell.env("USER") ?? "",
        uid: -1,
        seat: "seat0",
        sessionId: "",
        sessionType: "wayland",
        hostname: ""
    })

    property var powerActions: []

    property var sleep: ({
        preparing: false,
        wakeReady: true
    })

    property var lock: ({
        locked: false,
        secure: false,
        lockTime: null,
        error: "",
        message: "",
        authActive: false
    })

    // ======================================================================
    // Required property: reference to Lockscreen surface
    // Set by shell.qml: SessionBridge { lockscreen: lockscreenSurface }
    // ======================================================================

    property var lockscreen: null

    // ======================================================================
    // Signals
    // ======================================================================

    signal preparingSleep()
    signal wakeUp()
    signal lockStateChanged()
    signal lockError(string message)
    signal lockSuccess()

    // ======================================================================
    // Public methods (os.session)
    // ======================================================================

    function executeAction(action) {
        if (root._actionInProgress) return
        var actionInfo = root.powerActions.find(function(a) { return a.action === action })
        if (!actionInfo || !actionInfo.available) return

        root._actionInProgress = true

        switch (action) {
            case "shutdown":
                Quickshell.execDetached(["systemctl", "poweroff"])
                break
            case "reboot":
                Quickshell.execDetached(["systemctl", "reboot"])
                break
            case "suspend":
                Quickshell.execDetached(["systemctl", "suspend"])
                break
            case "hibernate":
                Quickshell.execDetached(["systemctl", "hibernate"])
                break
            case "suspend-then-hibernate":
                Quickshell.execDetached(["systemctl", "suspend-then-hibernate"])
                break
            case "logout":
                Quickshell.execDetached(["niri", "msg", "action", "quit", "--skip-confirmation"])
                break
            case "lock":
                requestLock()
                root._actionInProgress = false
                return
            default:
                root._actionInProgress = false
                return
        }
        _actionGuardReset.restart()
    }

    // requestLock: Acquire the Wayland session lock.
    // This causes the Lockscreen's WlSessionLock to cover all screens.
    function requestLock() {
        if (!root.lockscreen) {
            console.warn("SessionBridge: lockscreen reference not set -- cannot lock")
            return
        }
        if (root.lockscreen.isLocked) {
            console.info("SessionBridge: already locked")
            return
        }
        root.lockscreen.lockRequested = true
        root.lock = Object.assign({}, root.lock, {
            locked: true,
            lockTime: new Date().toISOString(),
            error: "",
            message: ""
        })
        root.lockStateChanged()
    }

    // requestUnlock: Attempt to authenticate and release the session lock.
    // The password is forwarded to PamContext inside Lockscreen.qml.
    function requestUnlock(password) {
        if (!root.lockscreen) {
            console.warn("SessionBridge: lockscreen reference not set -- cannot unlock")
            return
        }
        if (!root.lockscreen.isLocked) {
            console.info("SessionBridge: not locked, nothing to unlock")
            return
        }
        if (!password || password === "") {
            root.lock = Object.assign({}, root.lock, {
                error: "Password required"
            })
            root.lockError("Password required")
            return
        }
        root.lock = Object.assign({}, root.lock, {
            authActive: true,
            error: "",
            message: ""
        })
        root.lockscreen.tryUnlock(password)
    }

    // ======================================================================
    // Private: Lockscreen signal connections
    // ======================================================================

    Connections {
        target: root.lockscreen ?? null

        function onLockAcquired() {
            root.lock = Object.assign({}, root.lock, {
                locked: true,
                secure: true,
                lockTime: root.lock.lockTime || new Date().toISOString()
            })
            root.lockStateChanged()
        }

        function onLockReleased() {
            root.lock = {
                locked: false,
                secure: false,
                lockTime: null,
                error: "",
                message: "",
                authActive: false
            }
            root.lockStateChanged()
        }

        function onAuthSucceeded() {
            root.lock = Object.assign({}, root.lock, {
                authActive: false,
                error: "",
                message: ""
            })
            root.lockSuccess()
        }

        function onAuthFailed(message) {
            root.lock = Object.assign({}, root.lock, {
                authActive: false,
                error: message,
                message: message
            })
            root.lockError(message)
        }

        function onAuthErrorChanged() {
            if (root.lockscreen && root.lockscreen.authError !== "") {
                root.lock = Object.assign({}, root.lock, {
                    error: root.lockscreen.authError
                })
            }
        }

        function onAuthMessageChanged() {
            if (root.lockscreen && root.lockscreen.authMessage !== "") {
                root.lock = Object.assign({}, root.lock, {
                    message: root.lockscreen.authMessage
                })
            }
        }

        function onAuthActiveChanged() {
            if (root.lockscreen) {
                root.lock = Object.assign({}, root.lock, {
                    authActive: root.lockscreen.authActive
                })
            }
        }
    }

    // ======================================================================
    // Private: action guard
    // ======================================================================

    property bool _actionInProgress: false

    // ======================================================================
    // Private: IPC handler for sleep/wake/lock
    // ======================================================================

    IpcHandler {
        target: "session"
        function prepareSleep(): void {
            root.sleep = Object.assign({}, root.sleep, { preparing: true, wakeReady: false })
            root.preparingSleep()
        }
        function wake(): void {
            root.sleep = Object.assign({}, root.sleep, { preparing: false })
            root.wakeUp()
            _wakeReadyTimer.restart()
        }
        function shutdown(): void { root.executeAction("shutdown") }
        function reboot(): void { root.executeAction("reboot") }
        function suspend(): void { root.executeAction("suspend") }
        function logout(): void { root.executeAction("logout") }
        function lock(): void { root.requestLock() }
    }

    Timer {
        id: _wakeReadyTimer
        interval: 3000
        repeat: false
        onTriggered: root.sleep = Object.assign({}, root.sleep, { wakeReady: true })
    }

    Timer {
        id: _actionGuardReset
        interval: 3000
        repeat: false
        onTriggered: root._actionInProgress = false
    }

    // ======================================================================
    // Private: session info collection
    // ======================================================================

    Process {
        command: ["hostname"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                root.info = Object.assign({}, root.info, { hostname: data.trim() })
            }
        }
    }

    Process {
        command: ["id", "-u"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                root.info = Object.assign({}, root.info, { uid: parseInt(data.trim()) || -1 })
            }
        }
    }

    // ======================================================================
    // Private: power action availability probing
    // ======================================================================

    property bool _canSuspend: false
    property bool _canHibernate: false

    Process {
        command: ["loginctl", "can-suspend"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                root._canSuspend = data.trim() === "yes"
                root._rebuildPowerActions()
            }
        }
    }

    Process {
        command: ["loginctl", "can-hibernate"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                root._canHibernate = data.trim() === "yes"
                root._rebuildPowerActions()
            }
        }
    }

    function _rebuildPowerActions() {
        var canSuspendHibernate = root._canSuspend && root._canHibernate
        root.powerActions = [
            { action: "shutdown",               label: "Shut Down",              icon: "system-shutdown-symbolic",          available: true,                confirmRequired: true,  holdDurationMs: 1500, shortcutKey: "s" },
            { action: "reboot",                 label: "Reboot",                 icon: "system-reboot-symbolic",            available: true,                confirmRequired: true,  holdDurationMs: 1500, shortcutKey: "r" },
            { action: "suspend",                label: "Suspend",                icon: "system-suspend-symbolic",           available: root._canSuspend,    confirmRequired: false, holdDurationMs: 0,    shortcutKey: "u" },
            { action: "hibernate",              label: "Hibernate",              icon: "system-hibernate-symbolic",         available: root._canHibernate,  confirmRequired: true,  holdDurationMs: 1500, shortcutKey: "h" },
            { action: "suspend-then-hibernate", label: "Suspend then Hibernate", icon: "system-suspend-hibernate-symbolic", available: canSuspendHibernate, confirmRequired: false, holdDurationMs: 0,    shortcutKey: null },
            { action: "logout",                 label: "Log Out",                icon: "system-log-out-symbolic",           available: true,                confirmRequired: true,  holdDurationMs: 1500, shortcutKey: "l" },
            { action: "lock",                   label: "Lock Screen",            icon: "system-lock-screen-symbolic",       available: true,                confirmRequired: false, holdDurationMs: 0,    shortcutKey: "k" }
        ]
    }

    // ======================================================================
    // Health check timer
    // ======================================================================

    Timer {
        interval: 3000
        running: true
        repeat: false
        onTriggered: {
            if (!root.ready) {
                console.warn("SessionBridge: HEALTH CHECK -- not ready after 3s")
            } else {
                console.info("SessionBridge: healthy")
            }
        }
    }

    Component.onCompleted: {
        _rebuildPowerActions()
        root.ready = true
    }
}
