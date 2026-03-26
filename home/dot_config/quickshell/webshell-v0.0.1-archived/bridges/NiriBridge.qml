// NiriBridge.qml -- Niri IPC via Socket. Workspaces, windows, active workspace/window.
// Event stream. Dual-socket pattern: request socket + event socket.
// Also registered as "WorkspacesBridge" and "WindowsBridge" on WebChannel.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    readonly property string socketPath: Quickshell.env("NIRI_SOCKET") ?? ""

    // ======================================================================
    // os.workspaces reactive properties
    // ======================================================================

    property var workspaces: []
    property var focusedWorkspace: null
    property bool overviewOpen: false

    // ======================================================================
    // os.windows reactive properties
    // ======================================================================

    property var windows: []
    property var focusedWindow: null

    // ======================================================================
    // Keyboard layout (forwarded to InputBridge)
    // ======================================================================

    property var keyboardLayouts: []
    property int keyboardLayoutIndex: 0

    // ======================================================================
    // os.workspaces signals
    // ======================================================================

    signal focusChanged(var workspace)
    signal overviewChanged(bool isOpen)

    // ======================================================================
    // os.windows signals
    // ======================================================================

    signal windowFocusChanged(var focused)

    // ======================================================================
    // os.workspaces methods
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
    // os.windows methods
    // ======================================================================

    function focusWindow(id) {
        Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", id.toString()])
    }

    function closeWindow(id) {
        Quickshell.execDetached(["niri", "msg", "action", "close-window", "--id", id.toString()])
    }

    function moveToWorkspace(windowId, workspaceRef, follow) {
        var wsIdx
        if (workspaceRef.id !== undefined) {
            var ws = root.workspaces.find(function(w) { return w.id === workspaceRef.id })
            wsIdx = ws ? ws.idx + 1 : workspaceRef.id
        } else if (workspaceRef.idx !== undefined) {
            wsIdx = workspaceRef.idx + 1
        } else if (workspaceRef.name !== undefined) {
            var ws2 = root.workspaces.find(function(w) { return w.name === workspaceRef.name })
            if (!ws2) return
            wsIdx = ws2.idx + 1
        }
        Quickshell.execDetached(["niri", "msg", "action", "move-window-to-workspace", "--window-id", windowId.toString(), wsIdx.toString()])
        if (follow) {
            Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", wsIdx.toString()])
        }
    }

    function toggleFloating(windowId) {
        if (windowId !== undefined) {
            Quickshell.execDetached(["niri", "msg", "action", "toggle-window-floating", "--id", windowId.toString()])
        } else {
            Quickshell.execDetached(["niri", "msg", "action", "toggle-window-floating"])
        }
    }

    // ======================================================================
    // Internal: dual socket pattern
    // ======================================================================

    function _sendAction(action) {
        if (requestSocket.connected) {
            requestSocket.write(JSON.stringify({ Action: action }) + "\n")
            requestSocket.flush()
        }
    }

    Socket {
        id: requestSocket
        path: root.socketPath
        connected: root.socketPath !== ""
    }

    Socket {
        id: eventSocket
        path: root.socketPath
        connected: root.socketPath !== ""

        onConnectedChanged: {
            if (connected) {
                write('"EventStream"\n')
                flush()
            }
        }

        parser: SplitParser {
            onRead: line => {
                try {
                    root._handleEvent(JSON.parse(line))
                } catch (e) {
                    // Ignore parse errors on partial lines
                }
            }
        }
    }

    // Output info polled via niri msg -j outputs
    property var _outputCache: ({})

    Process {
        id: outputProc
        command: ["niri", "msg", "-j", "outputs"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    var parsed = JSON.parse(data)
                    var cache = {}
                    for (var name in parsed) {
                        var o = parsed[name]
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
                } catch (e) {}
            }
        }
    }

    onWorkspacesChanged: outputProc.running = true

    Connections {
        target: Quickshell
        function onScreensChanged() { outputProc.running = true }
    }

    // Debounce timers
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

    // ======================================================================
    // Event handling
    // ======================================================================

    function _handleEvent(event) {
        // Workspace events
        if (event.WorkspacesChanged) {
            var wsData = event.WorkspacesChanged.workspaces
            var newWorkspaces = []
            for (var i = 0; i < wsData.length; i++) {
                var ws = wsData[i]
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
            }
            newWorkspaces.sort(function(a, b) {
                if (a.output !== b.output) return a.output.localeCompare(b.output)
                return a.idx - b.idx
            })
            for (var j = 0; j < newWorkspaces.length; j++) {
                newWorkspaces[j].windowCount = root.windows.filter(function(w) { return w.workspaceId === newWorkspaces[j].id }).length
            }
            root.workspaces = newWorkspaces
            wsDebounce.restart()
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

        // Window events
        if (event.WindowsChanged) {
            var winData = event.WindowsChanged.windows
            var newWindows = []
            root.focusedWindow = null
            for (var k = 0; k < winData.length; k++) {
                var winObj = _makeWindow(winData[k])
                if (winObj.isFocused) root.focusedWindow = _makeFocusedWindow(winObj)
                newWindows.push(winObj)
            }
            root.windows = _sortWindows(newWindows)
            _updateWorkspaceWindowCounts()
            winDebounce.restart()
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

        // Keyboard layout events (forwarded to InputBridge)
        if (event.KeyboardLayoutsChanged) {
            root.keyboardLayoutIndex = event.KeyboardLayoutsChanged.keyboard_layouts.current_idx
            root.keyboardLayouts = event.KeyboardLayoutsChanged.keyboard_layouts.names
            return
        }

        if (event.KeyboardLayoutSwitched) {
            root.keyboardLayoutIndex = event.KeyboardLayoutSwitched.idx
            return
        }
    }

    // ======================================================================
    // Window helpers
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
            var wsA = root.workspaces.find(function(ws) { return ws.id === a.workspaceId })
            var wsB = root.workspaces.find(function(ws) { return ws.id === b.workspaceId })
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

    Component.onCompleted: {
        if (root.socketPath !== "") {
            outputProc.running = true
            console.info("NiriBridge: connected to", root.socketPath)
        } else {
            console.warn("NiriBridge: NIRI_SOCKET not set -- niri IPC disabled")
        }
    }
}
