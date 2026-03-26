// NetworkBridge.qml -- Network status and control.
// Uses Quickshell.Networking (native NM module) if available, falls back to nmcli.
// Scorecard Gap 7: no more process-only -- use native module when present.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    // ======================================================================
    // Public properties (os.network)
    // ======================================================================

    property var networks: []
    property var networksKnown: []
    property var active: null
    property bool wifiEnabled: true
    property bool scanning: false
    property string backend: "none"

    // ======================================================================
    // Signals
    // ======================================================================

    signal networkStatusChanged()

    // ======================================================================
    // Public methods (os.network)
    // ======================================================================

    function enableWifi(enabled) {
        if (_nativeAvailable && _nativeObj) {
            _nativeObj.wifiEnabled = enabled
        } else {
            _enableWifiProc.command = ["nmcli", "radio", "wifi", enabled ? "on" : "off"]
            _enableWifiProc.running = true
        }
    }

    function toggleWifi() {
        enableWifi(!root.wifiEnabled)
    }

    function rescanWifi() {
        if (_nativeAvailable) {
            _triggerNativeScan()
        } else {
            _rescanProc.running = true
        }
    }

    function connectToNetwork(ssid, password) {
        if (_nativeAvailable) {
            _nativeConnect(ssid)
        } else {
            if (!password || password === "") {
                _connectProc.command = ["nmcli", "conn", "up", ssid]
            } else {
                _connectProc.command = ["nmcli", "--ask", "device", "wifi", "connect", ssid, "password", password]
            }
            _connectProc.running = true
        }
    }

    function disconnectFromNetwork() {
        if (_nativeAvailable) {
            _nativeDisconnect()
        } else if (root.active) {
            _disconnectProc.command = ["nmcli", "connection", "down", root.active.ssid]
            _disconnectProc.running = true
        }
    }

    function getWifiStatus() {
        if (!_nativeAvailable) {
            _wifiStatusProc.running = true
        }
    }

    // ======================================================================
    // Private: native Quickshell.Networking module (try/catch)
    // ======================================================================

    property bool _nativeAvailable: false
    property var _nativeObj: null
    property var _nativeDevices: null

    function _initNativeNetworking() {
        try {
            var qmlString = 'import QtQuick; import Quickshell.Networking; QtObject { '
                + 'property var networking: Networking; '
                + 'property var devices: Networking.devices; '
                + 'property bool wifiEnabled: Networking.wifiEnabled; '
                + 'property bool wifiHardwareEnabled: Networking.wifiHardwareEnabled '
                + '}'
            _nativeObj = Qt.createQmlObject(qmlString, root, "NetworkBridge.Native")
            _nativeAvailable = true
            root.backend = "native"

            root.wifiEnabled = Qt.binding(function() { return _nativeObj.wifiEnabled })

            _rebuildFromNative()
            console.info("NetworkBridge: using native Quickshell.Networking module")
        } catch (e) {
            _nativeAvailable = false
            root.backend = "nmcli"
            console.info("NetworkBridge: Quickshell.Networking not available, falling back to nmcli:", e)
            _initNmcliFallback()
        }
    }

    function _rebuildFromNative() {
        if (!_nativeObj || !_nativeObj.devices?.values) return

        var allNetworks = []
        var activeNetwork = null

        var devs = _nativeObj.devices.values
        for (var i = 0; i < devs.length; i++) {
            var dev = devs[i]
            if (dev.type !== 1) continue // DeviceType.Wifi = 1 (from device.hpp enum)

            if (dev.networks?.values) {
                var nets = dev.networks.values
                for (var j = 0; j < nets.length; j++) {
                    var net = nets[j]
                    var flat = {
                        ssid: net.name ?? "",
                        bssid: "",
                        strength: Math.round((net.signalStrength ?? 0) * 100),
                        frequency: 0,
                        active: net.connected ?? false,
                        security: net.security !== undefined ? net.security.toString() : "",
                        isSecure: (net.security ?? 10) !== 10, // WifiSecurityType.Open = 10
                        known: net.known ?? false
                    }
                    allNetworks.push(flat)
                    if (flat.active) activeNetwork = flat
                }
            }
        }

        allNetworks.sort(function(a, b) {
            if (a.active !== b.active) return b.active - a.active
            return b.strength - a.strength
        })

        root.networks = allNetworks
        root.networksKnown = allNetworks.filter(function(n) { return n.known })
        root.active = activeNetwork
        root.networkStatusChanged()
    }

    function _triggerNativeScan() {
        if (!_nativeObj || !_nativeObj.devices?.values) return
        var devs = _nativeObj.devices.values
        for (var i = 0; i < devs.length; i++) {
            if (devs[i].type === 1 && devs[i].scannerEnabled !== undefined) {
                devs[i].scannerEnabled = true
            }
        }
        root.scanning = true
        _nativeScanTimer.restart()
    }

    Timer {
        id: _nativeScanTimer
        interval: 3000
        repeat: false
        onTriggered: {
            root.scanning = false
            root._rebuildFromNative()
        }
    }

    function _nativeConnect(ssid) {
        if (!_nativeObj || !_nativeObj.devices?.values) return
        var devs = _nativeObj.devices.values
        for (var i = 0; i < devs.length; i++) {
            if (devs[i].type !== 1 || !devs[i].networks?.values) continue
            var nets = devs[i].networks.values
            for (var j = 0; j < nets.length; j++) {
                if (nets[j].name === ssid) {
                    nets[j].connect()
                    return
                }
            }
        }
    }

    function _nativeDisconnect() {
        if (!_nativeObj || !_nativeObj.devices?.values) return
        var devs = _nativeObj.devices.values
        for (var i = 0; i < devs.length; i++) {
            if (devs[i].type !== 1 || !devs[i].networks?.values) continue
            var nets = devs[i].networks.values
            for (var j = 0; j < nets.length; j++) {
                if (nets[j].connected) {
                    nets[j].disconnect()
                    return
                }
            }
        }
    }

    // Rebuild from native module periodically for signal strength updates
    Timer {
        id: _nativeRebuildTimer
        interval: 5000
        running: root._nativeAvailable
        repeat: true
        onTriggered: root._rebuildFromNative()
    }

    // ======================================================================
    // Private: nmcli fallback (same as v0.0.1)
    // ======================================================================

    function _initNmcliFallback() {
        _nmcliStartupProc.running = true
        _wifiStatusProc.running = true
    }

    Process {
        id: _nmcliStartupProc
        command: ["nmcli", "m"]
        stdout: SplitParser {
            onRead: {
                _getNetworks.running = true
                _getKnownNetworks.running = true
            }
        }
    }

    Process {
        id: _wifiStatusProc
        command: ["nmcli", "radio", "wifi"]
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: SplitParser {
            onRead: data => {
                root.wifiEnabled = data.trim() === "enabled"
            }
        }
    }

    Process {
        id: _enableWifiProc
        onExited: {
            root.getWifiStatus()
            _getNetworks.running = true
            _getKnownNetworks.running = true
        }
    }

    Process {
        id: _rescanProc
        command: ["nmcli", "dev", "wifi", "list", "--rescan", "yes"]
        onRunningChanged: root.scanning = running
        onExited: {
            _getNetworks.running = true
            _getKnownNetworks.running = true
        }
    }

    Process {
        id: _connectProc
        stdout: SplitParser {
            onRead: {
                _getNetworks.running = true
                _getKnownNetworks.running = true
            }
        }
    }

    Process {
        id: _disconnectProc
        stdout: SplitParser {
            onRead: {
                _getNetworks.running = true
                _getKnownNetworks.running = true
            }
        }
    }

    Process {
        id: _getNetworks
        command: ["nmcli", "-g", "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY", "d", "w"]
        environment: ({ LANG: "C", LC_ALL: "C" })

        stdout: SplitParser {
            onRead: data => {
                var PLACEHOLDER = "STRINGWHICHHOPEFULLYWONTBEUSED"
                var rep = /\\:/g
                var rep2 = new RegExp(PLACEHOLDER, "g")

                var allNetworks = data.trim().split("\n").map(function(n) {
                    var net = n.replace(rep, PLACEHOLDER).split(":")
                    return {
                        active: net[0] === "yes",
                        strength: parseInt(net[1]),
                        frequency: parseInt(net[2]),
                        ssid: net[3] || "",
                        bssid: (net[4] || "").replace(rep2, ":"),
                        security: net[5] || ""
                    }
                }).filter(function(n) { return n.ssid })

                var map = new Map()
                for (var i = 0; i < allNetworks.length; i++) {
                    var n = allNetworks[i]
                    var e = map.get(n.ssid)
                    if (!e || (n.active && !e.active) || (!e.active && n.strength > e.strength)) {
                        map.set(n.ssid, n)
                    }
                }

                var result = Array.from(map.values())

                root.networks = result.map(function(n) {
                    return {
                        ssid: n.ssid,
                        bssid: n.bssid,
                        strength: n.strength,
                        frequency: n.frequency,
                        active: n.active,
                        security: n.security,
                        isSecure: n.security.length > 0
                    }
                })

                root.active = root.networks.find(function(n) { return n.active }) || null
                root.networkStatusChanged()
            }
        }

        onExited: {
            _getKnownNetworks.running = true
        }
    }

    Process {
        id: _getKnownNetworks
        command: ["nmcli", "-g", "NAME,TYPE", "connection", "show"]
        environment: ({ LANG: "C", LC_ALL: "C" })

        stdout: SplitParser {
            onRead: data => {
                var known = data.trim().split("\n")
                    .map(function(l) { return l.split(":") })
                    .filter(function(p) { return p.length >= 2 && p[1].includes("wireless") })
                    .map(function(p) { return p[0] })
                    .filter(Boolean)

                root.networksKnown = root.networks.filter(function(n) {
                    return known.includes(n.ssid)
                })
            }
        }
    }

    Component.onCompleted: {
        _initNativeNetworking()
    }
}
