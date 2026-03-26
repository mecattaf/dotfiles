// SessionBridge.qml -- Power actions: suspend, poweroff, reboot, logout, lock.
// Via loginctl/systemctl. Session info collection.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    default property list<QtObject> _children

    // ======================================================================
    // Public properties (os.session)
    // ======================================================================

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
        lockTime: null
    })

    // ======================================================================
    // Signals
    // ======================================================================

    signal preparingSleep()
    signal wakeUp()

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
            default:
                root._actionInProgress = false
                return
        }
        _actionGuardReset.restart()
    }

    function requestLock() {
        console.warn("SessionBridge: requestLock not yet implemented (needs WlSessionLock)")
    }

    function requestUnlock(password) {
        console.warn("SessionBridge: requestUnlock not yet implemented (needs PamContext)")
    }

    // ======================================================================
    // Private: action guard
    // ======================================================================

    property bool _actionInProgress: false

    // ======================================================================
    // Private: IPC handler for sleep/wake
    // ======================================================================

    IpcHandler {
        target: "session"
        function prepareSleep() {
            root.sleep = Object.assign({}, root.sleep, { preparing: true, wakeReady: false })
            root.preparingSleep()
        }
        function wake() {
            root.sleep = Object.assign({}, root.sleep, { preparing: false })
            root.wakeUp()
            _wakeReadyTimer.restart()
        }
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
            { action: "logout",                 label: "Log Out",                icon: "system-log-out-symbolic",           available: true,                confirmRequired: true,  holdDurationMs: 1500, shortcutKey: "l" }
        ]
    }

    Component.onCompleted: {
        _rebuildPowerActions()
    }
}
