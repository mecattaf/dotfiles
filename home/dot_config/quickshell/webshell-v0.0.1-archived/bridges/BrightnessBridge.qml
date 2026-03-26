// BrightnessBridge.qml -- Port of current-dotfiles Brightness.qml
// Handles DDC monitors via ddcutil, internal backlight via sysfs/brightnessctl,
// Apple Display via asdbctl. FileView watcher for external brightness changes.
// Debounced setBrightness with queued updates. IPC handler for display brighter/dimmer.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    // ======================================================================
    // Reactive properties (os.brightness)
    // ======================================================================

    // Flattened array of all monitors with brightness state
    property var monitors: []

    // DDC monitor info detected via ddcutil
    property var _ddcMonitors: []

    // Whether Apple Display support is available
    property bool _appleDisplayPresent: false

    // ======================================================================
    // Signals
    // ======================================================================

    signal brightnessOsd(var event)

    // ======================================================================
    // Methods (os.brightness)
    // ======================================================================

    function setBrightness(monitorIndex, value) {
        var instance = _monitorVariants.instances[monitorIndex]
        if (instance) instance.setBrightness(value)
    }

    function setBrightnessAll(value) {
        for (var i = 0; i < _monitorVariants.instances.length; i++) {
            _monitorVariants.instances[i].setBrightness(value)
        }
    }

    function increaseBrightness(monitorIndex) {
        if (monitorIndex !== undefined && monitorIndex !== null) {
            var instance = _monitorVariants.instances[monitorIndex]
            if (instance) instance.increaseBrightness()
        } else {
            for (var i = 0; i < _monitorVariants.instances.length; i++) {
                _monitorVariants.instances[i].increaseBrightness()
            }
        }
    }

    function decreaseBrightness(monitorIndex) {
        if (monitorIndex !== undefined && monitorIndex !== null) {
            var instance = _monitorVariants.instances[monitorIndex]
            if (instance) instance.decreaseBrightness()
        } else {
            for (var i = 0; i < _monitorVariants.instances.length; i++) {
                _monitorVariants.instances[i].decreaseBrightness()
            }
        }
    }

    // ======================================================================
    // IPC handler (from current dotfiles)
    // ======================================================================

    IpcHandler {
        target: "display"
        function brighter(by) {
            for (var i = 0; i < _monitorVariants.instances.length; i++) {
                var m = _monitorVariants.instances[i]
                m.setBrightness(m.brightness + (by || 0.01))
            }
        }
        function dimmer(by) {
            for (var i = 0; i < _monitorVariants.instances.length; i++) {
                var m = _monitorVariants.instances[i]
                m.setBrightness(m.brightness - (by || 0.01))
            }
        }
    }

    // ======================================================================
    // Detect Apple Display support
    // ======================================================================

    Process {
        running: true
        command: ["sh", "-c", "which asdbctl >/dev/null 2>&1 && asdbctl get || echo ''"]
        stdout: SplitParser {
            onRead: data => {
                root._appleDisplayPresent = data.trim().length > 0
            }
        }
    }

    // ======================================================================
    // Detect DDC monitors via ddcutil
    // ======================================================================

    Process {
        id: ddcProc
        command: ["ddcutil", "detect", "--sleep-multiplier=0.5"]
        stdout: SplitParser {
            splitMarker: "\n\n"
            onRead: data => {
                var displays = data.trim().split("\n\n")
                var detected = []
                for (var i = 0; i < displays.length; i++) {
                    var d = displays[i]
                    var ddcModelMatch = d.match(/This monitor does not support DDC\/CI/)
                    var modelMatch = d.match(/Model:\s*(.*)/)
                    var busMatch = d.match(/I2C bus:[ ]*\/dev\/i2c-([0-9]+)/)
                    var isDdc = ddcModelMatch ? false : true
                    var model = modelMatch ? modelMatch[1] : "Unknown"
                    var bus = busMatch ? busMatch[1] : "Unknown"
                    if (isDdc) {
                        detected.push({ model: model, busNum: bus, isDdc: true })
                    }
                }
                root._ddcMonitors = detected
            }
        }
    }

    // Redetect DDC when screens change
    Connections {
        target: Quickshell
        function onScreensChanged() {
            ddcProc.running = true
        }
    }

    // ======================================================================
    // Per-monitor Variants (from current dotfiles pattern)
    // ======================================================================

    Variants {
        id: _monitorVariants
        model: Quickshell.screens

        QtObject {
            id: monitor

            required property ShellScreen modelData
            property int monitorIndex: -1

            readonly property bool isDdc: root._ddcMonitors.some(function(m) { return m.model === modelData.model })
            readonly property string busNum: {
                var found = root._ddcMonitors.find(function(m) { return m.model === modelData.model })
                return found ? found.busNum : ""
            }
            readonly property bool isAppleDisplay: root._appleDisplayPresent && modelData.model.startsWith("StudioDisplay")
            readonly property string method: isAppleDisplay ? "apple" : (isDdc ? "ddcutil" : "internal")

            property real brightness: 0
            property real queuedBrightness: NaN
            readonly property real stepSize: 1 / 100.0

            // Internal backlight paths
            property string backlightDevice: ""
            property string brightnessPath: ""
            property string maxBrightnessPath: ""
            property int maxBrightness: 100

            // Debounce timer for rapid changes
            readonly property Timer timer: Timer {
                interval: 100
                onTriggered: {
                    if (!isNaN(monitor.queuedBrightness)) {
                        monitor.setBrightness(monitor.queuedBrightness)
                        monitor.queuedBrightness = NaN
                    }
                }
            }

            function setBrightnessDebounced(value) {
                monitor.queuedBrightness = value
                timer.start()
            }

            function increaseBrightness() {
                var value = !isNaN(monitor.queuedBrightness) ? monitor.queuedBrightness : monitor.brightness
                setBrightnessDebounced(value + stepSize)
            }

            function decreaseBrightness() {
                var value = !isNaN(monitor.queuedBrightness) ? monitor.queuedBrightness : monitor.brightness
                setBrightnessDebounced(value - stepSize)
            }

            function setBrightness(value) {
                value = Math.max(0, Math.min(1, value))
                var rounded = Math.round(value * 100)

                if (timer.running) {
                    monitor.queuedBrightness = value
                    return
                }

                monitor.brightness = value
                _emitUpdate()

                if (isAppleDisplay) {
                    Quickshell.execDetached(["asdbctl", "set", rounded.toString()])
                } else if (isDdc) {
                    Quickshell.execDetached(["ddcutil", "-b", busNum, "setvcp", "10", rounded.toString()])
                } else {
                    Quickshell.execDetached(["brightnessctl", "s", rounded + "%"])
                }

                if (isDdc) {
                    timer.restart()
                }
            }

            function _emitUpdate() {
                root._rebuildMonitors()
                root.brightnessOsd({
                    monitorIndex: monitor.monitorIndex,
                    monitorName: monitor.modelData.name,
                    brightness: monitor.brightness,
                    method: monitor.method
                })
            }

            // Initialize brightness on creation
            readonly property Process initProc: Process {
                stdout: SplitParser {
                    onRead: data => {
                        var dataText = data.trim()
                        if (dataText === "") return

                        if (monitor.isAppleDisplay) {
                            var val = parseInt(dataText)
                            if (!isNaN(val)) {
                                monitor.brightness = val / 101
                            }
                        } else if (monitor.isDdc) {
                            var parts = dataText.split(" ")
                            if (parts.length >= 5) {
                                var current = parseInt(parts[3])
                                var max = parseInt(parts[4])
                                if (!isNaN(current) && !isNaN(max) && max > 0) {
                                    monitor.brightness = current / max
                                }
                            }
                        } else {
                            var lines = dataText.split("\n")
                            if (lines.length >= 3) {
                                monitor.backlightDevice = lines[0]
                                monitor.brightnessPath = monitor.backlightDevice + "/brightness"
                                monitor.maxBrightnessPath = monitor.backlightDevice + "/max_brightness"

                                var current = parseInt(lines[1])
                                var max = parseInt(lines[2])
                                if (!isNaN(current) && !isNaN(max) && max > 0) {
                                    monitor.maxBrightness = max
                                    monitor.brightness = current / max
                                }
                            }
                        }
                        root._rebuildMonitors()
                    }
                }
            }

            // Refresh brightness from system (for external changes)
            readonly property Process refreshProc: Process {
                stdout: SplitParser {
                    onRead: data => {
                        var dataText = data.trim()
                        if (dataText === "") return

                        var lines = dataText.split("\n")
                        if (lines.length >= 2) {
                            var current = parseInt(lines[0].trim())
                            var max = parseInt(lines[1].trim())
                            if (!isNaN(current) && !isNaN(max) && max > 0) {
                                var newBrightness = current / max
                                if (Math.abs(newBrightness - monitor.brightness) > 0.01) {
                                    monitor.brightness = newBrightness
                                    root._rebuildMonitors()
                                }
                            }
                        }
                    }
                }
            }

            function refreshBrightnessFromSystem() {
                if (!monitor.isDdc && !monitor.isAppleDisplay && monitor.brightnessPath !== "") {
                    refreshProc.command = ["sh", "-c",
                        "cat " + monitor.brightnessPath + " && " +
                        "cat " + monitor.maxBrightnessPath]
                    refreshProc.running = true
                } else if (monitor.isDdc) {
                    refreshProc.command = ["ddcutil", "-b", monitor.busNum, "getvcp", "10", "--brief"]
                    refreshProc.running = true
                } else if (monitor.isAppleDisplay) {
                    refreshProc.command = ["asdbctl", "get"]
                    refreshProc.running = true
                }
            }

            // FileView watcher for internal displays
            readonly property FileView brightnessWatcher: FileView {
                path: (!monitor.isDdc && !monitor.isAppleDisplay && monitor.brightnessPath !== "") ? monitor.brightnessPath : ""
                watchChanges: path !== ""
                onFileChanged: {
                    Qt.callLater(function() {
                        monitor.refreshBrightnessFromSystem()
                    })
                }
            }

            function initBrightness() {
                if (isAppleDisplay) {
                    initProc.command = ["asdbctl", "get"]
                } else if (isDdc) {
                    initProc.command = ["ddcutil", "-b", busNum, "getvcp", "10", "--brief"]
                } else {
                    initProc.command = ["sh", "-c",
                        "for dev in /sys/class/backlight/*; do " +
                        "  if [ -f \"$dev/brightness\" ] && [ -f \"$dev/max_brightness\" ]; then " +
                        "    echo \"$dev\"; " +
                        "    cat \"$dev/brightness\"; " +
                        "    cat \"$dev/max_brightness\"; " +
                        "    break; " +
                        "  fi; " +
                        "done"]
                }
                initProc.running = true
            }

            onBusNumChanged: initBrightness()
            Component.onCompleted: initBrightness()
        }
    }

    // ======================================================================
    // Flatten monitor state for WebChannel
    // ======================================================================

    function _rebuildMonitors() {
        var result = []
        for (var i = 0; i < _monitorVariants.instances.length; i++) {
            var m = _monitorVariants.instances[i]
            m.monitorIndex = i
            result.push({
                index: i,
                name: m.modelData.name,
                model: m.modelData.model,
                brightness: m.brightness,
                method: m.method,
                isDdc: m.isDdc,
                isAppleDisplay: m.isAppleDisplay
            })
        }
        root.monitors = result
    }

    Component.onCompleted: {
        ddcProc.running = true
        // Defer initial rebuild to let Variants populate
        Qt.callLater(root._rebuildMonitors)
    }
}
