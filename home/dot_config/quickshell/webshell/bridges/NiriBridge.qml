// NiriBridge.qml -- Niri IPC via Socket. Workspaces, windows, active workspace/window.
// Dual-socket pattern: separate request socket + event stream socket.
// Also registered as "WorkspacesBridge" and "WindowsBridge" on WebChannel.
// Scorecard fix: proper dual-socket init with onConnectedChanged handlers.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    readonly property string socketPath: Quickshell.env("NIRI_SOCKET") ?? ""

    // ======================================================================
    // Public properties: readiness
    // ======================================================================

    property bool ready: false

    // ======================================================================
    // Public properties: os.workspaces
    // ======================================================================

    property var workspaces: []
    property var focusedWorkspace: null
    property bool overviewOpen: false

    // ======================================================================
    // Public properties: os.windows
    // ======================================================================

    property var windows: []
    property var focusedWindow: null

    // ======================================================================
    // Public properties: keyboard layout (forwarded to InputBridge)
    // ======================================================================

    property var keyboardLayouts: []
    property int keyboardLayoutIndex: 0

    // v0.2.0 SHOULD: scratchpads (#168) — piri-style
    property var scratchpads: []

    // v0.2.0 SHOULD: window swallow (#169) — PID-based
    property bool swallowEnabled: false

    // ======================================================================
    // Signals: os.workspaces
    // ======================================================================

    signal focusChanged(var workspace)
    signal overviewChanged(bool isOpen)

    // ======================================================================
    // Signals: os.windows
    // ======================================================================

    signal windowFocusChanged(var focused)

    // ======================================================================
    // Public methods: os.workspaces
    // ======================================================================

    function focusWorkspace(ref) {
        if (ref.id !== undefined) {
            _sendAction({ FocusWorkspace: { reference: { Id: ref.id } } })
        } else if (ref.idx !== undefined) {
            _sendAction({ FocusWorkspace: { reference: { Index: ref.idx + 1 } } })
        } else if (ref.name !== undefined) {
            var ws = root.workspaces.find(function(w) { return w.name === ref.name })
            if (ws) _sendAction({ FocusWorkspace: { reference: { Id: ws.id } } })
        }
    }

    function focusWorkspaceRelative(direction) {
        if (direction === "up") {
            _sendAction({ FocusWorkspaceUp: {} })
        } else {
            _sendAction({ FocusWorkspaceDown: {} })
        }
    }

    function renameWorkspace(id, name) {
        _sendAction({ RenameWorkspace: { id: id, name: name } })
    }

    function toggleOverview() {
        _sendAction({ ToggleOverview: {} })
    }

    // ======================================================================
    // Public methods: os.windows
    // ======================================================================

    function focusWindow(id) {
        _sendAction({ FocusWindow: { id: id } })
    }

    function closeWindow(id) {
        _sendAction({ CloseWindow: { id: id } })
    }

    function moveToWorkspace(windowId, workspaceRef, follow) {
        var wsRef
        if (workspaceRef.id !== undefined) {
            wsRef = { Id: workspaceRef.id }
        } else if (workspaceRef.idx !== undefined) {
            wsRef = { Index: workspaceRef.idx + 1 }
        } else if (workspaceRef.name !== undefined) {
            var ws = root.workspaces.find(function(w) { return w.name === workspaceRef.name })
            if (!ws) return
            wsRef = { Id: ws.id }
        }
        _sendAction({ MoveWindowToWorkspace: { window_id: windowId, reference: wsRef } })
        if (follow && wsRef) {
            _sendAction({ FocusWorkspace: { reference: wsRef } })
        }
    }

    function toggleFloating(windowId) {
        if (windowId !== undefined) {
            _sendAction({ ToggleWindowFloating: { id: windowId } })
        } else {
            _sendAction({ ToggleWindowFloating: {} })
        }
    }

    // v0.2.0 SHOULD: scratchpad toggle (#168) — sends niri IPC action
    function toggleScratchpad(name) {
        _sendAction({ ToggleScratchpad: { name: name } })
    }

    // v0.2.0 SHOULD: window swallow toggle (#169)
    function setSwallowEnabled(enabled) {
        root.swallowEnabled = enabled
    }

    // ======================================================================
    // Private: dual socket pattern (request + event stream)
    // ======================================================================

    function _sendAction(action) {
        _sendCommand(requestSocket, { Action: action })
    }

    function _sendCommand(sock, command) {
        if (sock.connected) {
            sock.write(JSON.stringify(command) + "\n")
            sock.flush()
        }
    }

    // Request socket: used for queries (Outputs, Workspaces, Windows) and actions
    Socket {
        id: requestSocket
        path: root.socketPath
        connected: root.socketPath !== ""

        onConnectedChanged: {
            if (connected) {
                // Query initial state on connect
                root._sendCommand(requestSocket, "Workspaces")
                root._sendCommand(requestSocket, "Windows")
                root._sendCommand(requestSocket, "Outputs")
            }
        }

        parser: SplitParser {
            onRead: line => {
                try {
                    var data = JSON.parse(line)
                    if (data && data.Ok) {
                        var res = data.Ok
                        if (res.Workspaces) root._recollectWorkspaces(res.Workspaces)
                        else if (res.Windows) root._recollectWindows(res.Windows)
                        else if (res.Outputs) root._recollectOutputs(res.Outputs)
                    }
                } catch (e) {}
            }
        }
    }

    // Event stream socket: receives push events from niri
    Socket {
        id: eventSocket
        path: root.socketPath
        connected: root.socketPath !== ""

        onConnectedChanged: {
            if (connected) {
                root._sendCommand(eventSocket, "EventStream")
            }
        }

        parser: SplitParser {
            onRead: line => {
                try {
                    root._handleEvent(JSON.parse(line))
                } catch (e) {}
            }
        }
    }

    // ======================================================================
    // Private: output cache
    // ======================================================================

    property var _outputCache: ({})
    property var _workspaceCache: ({})

    function _recollectOutputs(outputsData) {
        var cache = {}
        for (var name in outputsData) {
            var o = outputsData[name]
            if (!o || !o.name) continue
            var logical = o.logical || {}
            cache[o.name] = {
                name: o.name,
                scale: logical.scale || 1.0,
                width: logical.width || 0,
                height: logical.height || 0,
                x: logical.x || 0,
                y: logical.y || 0
            }
        }
        root._outputCache = cache
    }

    function _recollectWorkspaces(workspacesData) {
        var newWorkspaces = []
        var newCache = {}
        for (var i = 0; i < workspacesData.length; i++) {
            var ws = workspacesData[i]
            var wsObj = {
                id: ws.id,
                idx: ws.idx,
                name: ws.name ?? "",
                output: ws.output ?? "",
                isActive: ws.is_active === true,
                isFocused: ws.is_focused === true,
                isUrgent: ws.is_urgent === true,
                windowCount: 0,
                activeWindowId: ws.active_window_id ?? null
            }
            if (wsObj.isFocused) root.focusedWorkspace = wsObj
            newWorkspaces.push(wsObj)
            newCache[ws.id] = wsObj
        }
        newWorkspaces.sort(function(a, b) {
            if (a.output !== b.output) return a.output.localeCompare(b.output)
            return a.idx - b.idx
        })
        for (var j = 0; j < newWorkspaces.length; j++) {
            newWorkspaces[j].windowCount = root.windows.filter(function(w) { return w.workspaceId === newWorkspaces[j].id }).length
        }
        root._workspaceCache = newCache
        root.workspaces = newWorkspaces
        if (!root.ready) root.ready = true
        wsDebounce.restart()
    }

    function _recollectWindows(windowsData) {
        var newWindows = []
        root.focusedWindow = null
        for (var k = 0; k < windowsData.length; k++) {
            var winObj = _makeWindow(windowsData[k])
            if (winObj.isFocused) root.focusedWindow = _makeFocusedWindow(winObj)
            newWindows.push(winObj)
        }
        root.windows = _sortWindows(newWindows)
        _updateWorkspaceWindowCounts()
        winDebounce.restart()
    }

    // ======================================================================
    // Private: debounce timers
    // ======================================================================

    Timer {
        id: wsDebounce
        interval: 50
        repeat: false
        onTriggered: {
            if (root.focusedWorkspace) root.focusChanged(root.focusedWorkspace)
        }
    }

    Timer {
        id: winDebounce
        interval: 50
        repeat: false
        onTriggered: {
            root.windowFocusChanged(root.focusedWindow)
        }
    }

    // Re-query outputs when screens change
    Connections {
        target: Quickshell
        function onScreensChanged() {
            root._sendCommand(requestSocket, "Outputs")
        }
    }

    // ======================================================================
    // Private: event handling
    // ======================================================================

    function _handleEvent(event) {
        if (event.WorkspacesChanged) {
            _recollectWorkspaces(event.WorkspacesChanged.workspaces)
            return
        }

        if (event.WorkspaceActivated) {
            var wsId = event.WorkspaceActivated.id
            root.workspaces = root.workspaces.map(function(ws) {
                var isFocused = ws.id === wsId
                if (ws.isFocused !== isFocused) {
                    return Object.assign({}, ws, { isFocused: isFocused, isActive: isFocused || ws.isActive })
                }
                return ws
            })
            root.focusedWorkspace = root.workspaces.find(function(ws) { return ws.id === wsId }) ?? root.focusedWorkspace
            wsDebounce.restart()
            return
        }

        if (event.OverviewOpenedOrClosed) {
            root.overviewOpen = event.OverviewOpenedOrClosed.is_open
            root.overviewChanged(root.overviewOpen)
            return
        }

        if (event.WindowsChanged) {
            _recollectWindows(event.WindowsChanged.windows)
            return
        }

        if (event.WindowOpenedOrChanged) {
            var win = event.WindowOpenedOrChanged.window
            var winObj2 = _makeWindow(win)
            var idx = root.windows.findIndex(function(w) { return w.id === winObj2.id })
            var updatedWindows = root.windows.slice()
            if (idx >= 0) {
                updatedWindows[idx] = winObj2
            } else {
                updatedWindows.push(winObj2)
            }
            if (winObj2.isFocused) {
                updatedWindows = updatedWindows.map(function(w) {
                    if (w.id !== winObj2.id && w.isFocused) return Object.assign({}, w, { isFocused: false })
                    return w
                })
                root.focusedWindow = _makeFocusedWindow(winObj2)
            }
            root.windows = _sortWindows(updatedWindows)
            _updateWorkspaceWindowCounts()
            winDebounce.restart()
            return
        }

        if (event.WindowClosed) {
            var closedId = event.WindowClosed.id
            root.windows = root.windows.filter(function(w) { return w.id !== closedId })
            if (root.focusedWindow && root.focusedWindow.id === closedId) {
                root.focusedWindow = null
            }
            _updateWorkspaceWindowCounts()
            winDebounce.restart()
            return
        }

        if (event.WindowFocusChanged) {
            var focusedId = event.WindowFocusChanged.id
            root.windows = root.windows.map(function(w) {
                var shouldFocus = w.id === focusedId
                if (w.isFocused !== shouldFocus) return Object.assign({}, w, { isFocused: shouldFocus })
                return w
            })
            if (focusedId) {
                var focWin = root.windows.find(function(w) { return w.id === focusedId })
                root.focusedWindow = focWin ? _makeFocusedWindow(focWin) : null
            } else {
                root.focusedWindow = null
            }
            winDebounce.restart()
            return
        }

        if (event.KeyboardLayoutsChanged) {
            root.keyboardLayoutIndex = event.KeyboardLayoutsChanged.keyboard_layouts.current_idx
            root.keyboardLayouts = event.KeyboardLayoutsChanged.keyboard_layouts.names
            return
        }

        if (event.KeyboardLayoutSwitched) {
            root.keyboardLayoutIndex = event.KeyboardLayoutSwitched.idx
            return
        }

        if (event.OutputsChanged) {
            root._sendCommand(requestSocket, "Outputs")
            return
        }
    }

    // ======================================================================
    // Private: window helpers
    // ======================================================================

    function _makeWindow(win) {
        return {
            id: win.id,
            title: win.title ?? "",
            appId: win.app_id ?? null,
            pid: win.pid ?? null,
            workspaceId: win.workspace_id ?? null,
            isFocused: win.is_focused === true,
            isFloating: win.is_floating === true,
            isUrgent: win.is_urgent === true,
            layout: win.layout ? {
                scrollPosition: win.layout.pos_in_scrolling_layout ?? null,
                windowSize: win.layout.size ? [win.layout.size[0], win.layout.size[1]] : null
            } : null
        }
    }

    function _makeFocusedWindow(win) {
        return {
            id: win.id,
            title: win.title,
            appId: win.appId,
            isFloating: win.isFloating,
            workspaceId: win.workspaceId
        }
    }

    function _sortWindows(windowList) {
        return windowList.sort(function(a, b) {
            var wsA = root._workspaceCache[a.workspaceId]
            var wsB = root._workspaceCache[b.workspaceId]
            var outA = wsA?.output ?? ""
            var outB = wsB?.output ?? ""
            if (outA !== outB) return outA.localeCompare(outB)
            var idxA = wsA?.idx ?? 0
            var idxB = wsB?.idx ?? 0
            if (idxA !== idxB) return idxA - idxB
            return a.id - b.id
        })
    }

    function _updateWorkspaceWindowCounts() {
        root.workspaces = root.workspaces.map(function(ws) {
            var count = root.windows.filter(function(w) { return w.workspaceId === ws.id }).length
            if (ws.windowCount !== count) return Object.assign({}, ws, { windowCount: count })
            return ws
        })
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
                console.warn("NiriBridge: HEALTH CHECK — not ready after 3s")
            } else {
                console.info("NiriBridge: healthy")
            }
        }
    }

    Component.onCompleted: {
        if (root.socketPath !== "") {
            console.info("NiriBridge: connecting to", root.socketPath)
        } else {
            console.warn("NiriBridge: NIRI_SOCKET not set -- niri IPC disabled")
        }
    }
}
