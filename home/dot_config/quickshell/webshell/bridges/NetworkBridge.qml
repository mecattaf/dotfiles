// NetworkBridge.qml -- Network status and control.
// Fixed: direct import of Quickshell.Networking, no Qt.createQmlObject.
// API verified against quickshellX/src/network/*.hpp:
//   Networking singleton: devices (ObjectModel<NetworkDevice>), wifiEnabled, wifiHardwareEnabled
//   NetworkDevice: type (DeviceType.Enum), name, address, connected, state
//   WifiDevice extends NetworkDevice: networks (ObjectModel<WifiNetwork>), scannerEnabled
//   WifiNetwork extends Network: signalStrength (0.0-1.0), known, security (WifiSecurityType.Enum)
//   Network: name, connected, state (NetworkState.Enum)
// Falls back to nmcli if native module not available.
// POJO-only across bridge boundary.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

Scope {
    id: root

    // ======================================================================
    // Public properties (os.network)
    // ======================================================================

    property bool ready: false

    property var networks: []
    property var networksKnown: []
    property var active: null
    property bool wifiEnabled: _nativeAvailable ? Networking.wifiEnabled : _nmcliWifiEnabled
    property bool wifiHardwareEnabled: _nativeAvailable ? Networking.wifiHardwareEnabled : true
    property bool scanning: false
    property string backend: _nativeAvailable ? "native" : "nmcli"

    // ======================================================================
    // Signals
    // ======================================================================

    signal networkStatusChanged()

    // ======================================================================
    // Public methods (os.network)
    // ======================================================================

    function enableWifi(enabled) {
        if (_nativeAvailable) {
            Networking.wifiEnabled = enabled
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

    function forgetNetwork(ssid) {
        if (_nativeAvailable) {
            _nativeForget(ssid)
        }
        // nmcli fallback: nmcli connection delete <ssid> -- not yet implemented
    }

    function getWifiStatus() {
        if (!_nativeAvailable) {
            _wifiStatusProc.running = true
        }
    }

    // ======================================================================
    // Private: native Quickshell.Networking
    // ======================================================================

    property bool _nativeAvailable: true  // assume available; set false if it fails
    property bool _nmcliWifiEnabled: true

    // Map WifiSecurityType enum to human-readable string.
    // Enum from wifi.hpp: Wpa3SuiteB192=0, Sae=1, Wpa2Eap=2, Wpa2Psk=3,
    //   WpaEap=4, WpaPsk=5, StaticWep=6, DynamicWep=7, Leap=8, Owe=9, Open=10, Unknown=11
    function _securityToString(securityEnum) {
        switch (securityEnum) {
            case 0: return "WPA3-Suite-B-192"
            case 1: return "SAE"
            case 2: return "WPA2-EAP"
            case 3: return "WPA2-PSK"
            case 4: return "WPA-EAP"
            case 5: return "WPA-PSK"
            case 6: return "WEP"
            case 7: return "Dynamic-WEP"
            case 8: return "LEAP"
            case 9: return "OWE"
            case 10: return "Open"
            default: return "Unknown"
        }
    }

    function _rebuildFromNative() {
        if (!Networking.devices) return

        var allNetworks = []
        var activeNetwork = null

        var devs = Networking.devices.values
        for (var i = 0; i < devs.length; i++) {
            var dev = devs[i]
            // DeviceType.Wifi = 1 (from device.hpp)
            if (dev.type !== DeviceType.Wifi) continue

            // WifiDevice has networks property (ObjectModel<WifiNetwork>)
            if (dev.networks) {
                var nets = dev.networks.values
                for (var j = 0; j < nets.length; j++) {
                    var net = nets[j]
                    var securityEnum = net.security ?? 11 // Unknown=11
                    var flat = {
                        ssid: net.name ?? "",
                        bssid: "",
                        // signalStrength is 0.0-1.0 per wifi.hpp, scale to 0-100
                        strength: Math.round((net.signalStrength ?? 0) * 100),
                        frequency: 0,
                        active: net.connected ?? false,
                        security: _securityToString(securityEnum),
                        // WifiSecurityType.Open = 10
                        isSecure: securityEnum !== 10,
                        known: net.known ?? false,
                        // NetworkState enum: Unknown=0, Connecting=1, Connected=2, Disconnecting=3, Disconnected=4
                        state: net.state ?? 0,
                        stateChanging: net.stateChanging ?? false
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
        if (!root.ready) root.ready = true
        root.networkStatusChanged()
    }

    function _triggerNativeScan() {
        if (!Networking.devices) return
        var devs = Networking.devices.values
        for (var i = 0; i < devs.length; i++) {
            // WifiDevice has scannerEnabled property
            if (devs[i].type === DeviceType.Wifi && devs[i].scannerEnabled !== undefined) {
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
        if (!Networking.devices) return
        var devs = Networking.devices.values
        for (var i = 0; i < devs.length; i++) {
            if (devs[i].type !== DeviceType.Wifi || !devs[i].networks) continue
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
        if (!Networking.devices) return
        var devs = Networking.devices.values
        for (var i = 0; i < devs.length; i++) {
            if (devs[i].type !== DeviceType.Wifi || !devs[i].networks) continue
            var nets = devs[i].networks.values
            for (var j = 0; j < nets.length; j++) {
                if (nets[j].connected) {
                    nets[j].disconnect()
                    return
                }
            }
        }
    }

    function _nativeForget(ssid) {
        if (!Networking.devices) return
        var devs = Networking.devices.values
        for (var i = 0; i < devs.length; i++) {
            if (devs[i].type !== DeviceType.Wifi || !devs[i].networks) continue
            var nets = devs[i].networks.values
            for (var j = 0; j < nets.length; j++) {
                if (nets[j].name === ssid) {
                    nets[j].forget()
                    return
                }
            }
        }
    }

    // Watch Networking singleton for wifiEnabled changes
    Connections {
        target: Networking
        function onWifiEnabledChanged() {
            root._rebuildFromNative()
        }
        function onWifiHardwareEnabledChanged() {
            root._rebuildFromNative()
        }
    }

    // Signal-driven rebuild: watch WiFi device networks for onValuesChanged
    Connections {
        id: _wifiDeviceNetworksConn
        target: {
            if (!root._nativeAvailable || !Networking.devices) return null
            var devs = Networking.devices.values
            for (var i = 0; i < devs.length; i++) {
                if (devs[i].type === DeviceType.Wifi && devs[i].networks) {
                    return devs[i].networks
                }
            }
            return null
        }
        function onValuesChanged() { _nativeRebuildDebounce.restart() }
    }

    Timer {
        id: _nativeRebuildDebounce
        interval: 50
        repeat: false
        onTriggered: root._rebuildFromNative()
    }

    // 30s fallback poll for signal strength which doesn't fire signals
    Timer {
        id: _nativeRebuildTimer
        interval: 30000
        running: root._nativeAvailable
        repeat: true
        onTriggered: root._rebuildFromNative()
    }

    // ======================================================================
    // Private: nmcli fallback
    // ======================================================================

    function _initNmcliFallback() {
        _nativeAvailable = false
        root.backend = "nmcli"
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
                root._nmcliWifiEnabled = data.trim() === "enabled"
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
                        isSecure: n.security.length > 0,
                        known: false
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

    // ======================================================================
    // Pull-data fallback: getData(key)
    // ======================================================================

    function getData(key) {
        if (key === "networks") return JSON.stringify(root.networks)
        if (key === "networksKnown") return JSON.stringify(root.networksKnown)
        if (key === "active") return JSON.stringify(root.active)
        if (key === "status") return JSON.stringify({
            wifiEnabled: root.wifiEnabled,
            wifiHardwareEnabled: root.wifiHardwareEnabled,
            scanning: root.scanning,
            backend: root.backend
        })
        return "{}"
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
                console.warn("NetworkBridge: HEALTH CHECK — not ready after 3s")
            } else {
                console.info("NetworkBridge: healthy")
            }
        }
    }

    Component.onCompleted: {
        // Try native first; if Networking.devices is available, use it
        if (Networking.devices) {
            _nativeAvailable = true
            _rebuildFromNative()
            // Ready when networks list is populated or we've at least queried
            root.ready = root.networks.length > 0
            if (!root.ready) {
                // Will become ready when first rebuild completes with data
            }
            console.info("NetworkBridge: using native Quickshell.Networking module")
        } else {
            console.info("NetworkBridge: Quickshell.Networking not available, falling back to nmcli")
            _initNmcliFallback()
        }
    }
}
