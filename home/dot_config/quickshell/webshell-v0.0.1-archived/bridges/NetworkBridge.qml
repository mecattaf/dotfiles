// NetworkBridge.qml -- Port of current-dotfiles NetworkManager.qml
// Uses nmcli for scan/connect/disconnect. Exposes networks list,
// active AP, known networks, wifiEnabled. Process-based nmcli integration.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    // ======================================================================
    // Reactive properties (os.network)
    // ======================================================================

    property var networks: []
    property var networksKnown: []
    property var active: null
    property bool wifiEnabled: true
    property bool scanning: rescanProc.running

    // ======================================================================
    // Signals
    // ======================================================================

    signal networkStatusChanged()

    // ======================================================================
    // Methods (os.network)
    // ======================================================================

    function enableWifi(enabled) {
        enableWifiProc.command = ["nmcli", "radio", "wifi", enabled ? "on" : "off"]
        enableWifiProc.running = true
    }

    function toggleWifi() {
        enableWifiProc.command = ["nmcli", "radio", "wifi", root.wifiEnabled ? "off" : "on"]
        enableWifiProc.running = true
    }

    function rescanWifi() {
        rescanProc.running = true
    }

    function connectToNetwork(ssid, password) {
        if (!password || password === "") {
            connectProc.command = ["nmcli", "conn", "up", ssid]
        } else {
            connectProc.command = ["nmcli", "--ask", "device", "wifi", "connect", ssid, "password", password]
        }
        connectProc.running = true
    }

    function disconnectFromNetwork() {
        if (root.active) {
            disconnectProc.command = ["nmcli", "connection", "down", root.active.ssid]
            disconnectProc.running = true
        }
    }

    function getWifiStatus() {
        wifiStatusProc.running = true
    }

    // ======================================================================
    // Startup trigger
    // ======================================================================

    Process {
        running: true
        command: ["nmcli", "m"]
        stdout: SplitParser {
            onRead: {
                getNetworks.running = true
                getKnownNetworks.running = true
            }
        }
    }

    // ======================================================================
    // Wi-Fi status
    // ======================================================================

    Process {
        id: wifiStatusProc
        running: true
        command: ["nmcli", "radio", "wifi"]
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: SplitParser {
            onRead: data => {
                root.wifiEnabled = data.trim() === "enabled"
            }
        }
    }

    Process {
        id: enableWifiProc
        onExited: {
            root.getWifiStatus()
            getNetworks.running = true
            getKnownNetworks.running = true
        }
    }

    // ======================================================================
    // Scan
    // ======================================================================

    Process {
        id: rescanProc
        command: ["nmcli", "dev", "wifi", "list", "--rescan", "yes"]
        onExited: {
            getNetworks.running = true
            getKnownNetworks.running = true
        }
    }

    // ======================================================================
    // Connect / Disconnect
    // ======================================================================

    Process {
        id: connectProc
        stdout: SplitParser {
            onRead: {
                getNetworks.running = true
                getKnownNetworks.running = true
            }
        }
    }

    Process {
        id: disconnectProc
        stdout: SplitParser {
            onRead: {
                getNetworks.running = true
                getKnownNetworks.running = true
            }
        }
    }

    // ======================================================================
    // Visible Wi-Fi networks (from current dotfiles)
    // ======================================================================

    Process {
        id: getNetworks
        running: true
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

                // Group by SSID: keep active or strongest signal
                var map = new Map()
                for (var i = 0; i < allNetworks.length; i++) {
                    var n = allNetworks[i]
                    var e = map.get(n.ssid)
                    if (!e || (n.active && !e.active) || (!e.active && n.strength > e.strength)) {
                        map.set(n.ssid, n)
                    }
                }

                var result = Array.from(map.values())

                // Flatten to plain objects for WebChannel
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

                // Update active
                root.active = root.networks.find(function(n) { return n.active }) || null
                root.networkStatusChanged()
            }
        }

        onExited: {
            getKnownNetworks.running = true
        }
    }

    // ======================================================================
    // Known (saved) Wi-Fi networks (from current dotfiles)
    // ======================================================================

    Process {
        id: getKnownNetworks
        running: false
        command: ["nmcli", "-g", "NAME,TYPE", "connection", "show"]
        environment: ({ LANG: "C", LC_ALL: "C" })

        stdout: SplitParser {
            onRead: data => {
                var known = data.trim().split("\n")
                    .map(function(l) { return l.split(":") })
                    .filter(function(p) { return p.length >= 2 && p[1].includes("wireless") })
                    .map(function(p) { return p[0] })
                    .filter(Boolean)

                // Build known networks from active networks list
                root.networksKnown = root.networks.filter(function(n) {
                    return known.includes(n.ssid)
                })
            }
        }
    }

    Component.onCompleted: {
        console.info("NetworkBridge: initialized (nmcli-based)")
    }
}
