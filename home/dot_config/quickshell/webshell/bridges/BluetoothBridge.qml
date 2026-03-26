// BluetoothBridge.qml -- wraps Quickshell.Bluetooth for adapter/device state.
// Fixed: all API names verified against quickshellX/src/bluetooth/*.hpp.
// POJO-only across bridge boundary. No QObject pointers in properties.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth

Scope {
    id: root

    // ======================================================================
    // Public properties (os.bluetooth)
    // ======================================================================

    property bool ready: false

    property bool available: false
    property bool powered: false
    property bool discovering: false
    property bool discoverable: false
    property string adapterName: ""
    property string adapterAddress: ""

    property var devices: []
    readonly property var pairedDevices: root.devices.filter(function(d) { return d.paired })
    readonly property var connectedDevices: root.devices.filter(function(d) { return d.connected })

    // v0.2.0 SHOULD: pinned/favorite devices (#155)
    property var pinnedDevices: []

    // v0.2.0 SHOULD: pairing agent state (#152)
    property var pairingRequest: null  // { address, pinCode, passkey, type: "pin"|"passkey"|"confirm" }

    // ======================================================================
    // Signals
    // ======================================================================

    signal deviceAdded(var device)
    signal deviceRemoved(string address)
    signal pairingRequested(var request)

    // ======================================================================
    // Public methods (os.bluetooth)
    // ======================================================================

    function setPower(on) {
        var adapter = Bluetooth.defaultAdapter
        if (adapter) adapter.enabled = on
    }

    function startDiscovery() {
        var adapter = Bluetooth.defaultAdapter
        if (adapter && adapter.enabled) adapter.discovering = true
    }

    function stopDiscovery() {
        var adapter = Bluetooth.defaultAdapter
        if (adapter) adapter.discovering = false
    }

    function setDiscoverable(on) {
        var adapter = Bluetooth.defaultAdapter
        if (adapter) adapter.discoverable = on
    }

    function connectDevice(address) {
        var dev = _findQsDevice(address)
        if (dev) dev.connect()
    }

    function disconnectDevice(address) {
        var dev = _findQsDevice(address)
        if (dev) dev.disconnect()
    }

    function pair(address) {
        var dev = _findQsDevice(address)
        if (dev) dev.pair()
    }

    function cancelPairing(address) {
        var dev = _findQsDevice(address)
        if (dev) dev.cancelPair()
    }

    function removeDevice(address) {
        var dev = _findQsDevice(address)
        if (dev) dev.forget()
    }

    function trust(address) {
        var dev = _findQsDevice(address)
        if (dev) dev.trusted = true
    }

    function untrust(address) {
        var dev = _findQsDevice(address)
        if (dev) dev.trusted = false
    }

    // v0.2.0 SHOULD: device pinning (#155)
    function pinDevice(address) {
        if (!root.pinnedDevices.includes(address)) {
            root.pinnedDevices = root.pinnedDevices.concat([address])
        }
    }

    function unpinDevice(address) {
        root.pinnedDevices = root.pinnedDevices.filter(function(a) { return a !== address })
    }

    // v0.2.0 SHOULD: pairing agent response (#152)
    function respondPairing(address, accepted, pin) {
        // Stub: real implementation needs BlueZ Agent1 D-Bus interface (Rust daemon)
        root.pairingRequest = null
        if (accepted) {
            root.pair(address)
        } else {
            root.cancelPairing(address)
        }
    }

    // ======================================================================
    // Private: device lookup
    // ======================================================================

    property var _lastDeviceAddresses: []

    function _findQsDevice(address) {
        if (!Bluetooth.defaultAdapter) return null
        var devs = Bluetooth.defaultAdapter.devices.values
        for (var i = 0; i < devs.length; i++) {
            if (devs[i].address === address) return devs[i]
        }
        return null
    }

    function _classifyDeviceType(dev) {
        // icon from BlueZ via device.hpp Q_PROPERTY(QString icon ...)
        var icon = (dev.icon ?? "").toLowerCase()
        if (icon.includes("headset")) return "audio-headset"
        if (icon.includes("headphone")) return "audio-headphones"
        if (icon.includes("speaker")) return "audio-speakers"
        if (icon.includes("keyboard")) return "input-keyboard"
        if (icon.includes("mouse")) return "input-mouse"
        if (icon.includes("phone")) return "phone"
        if (icon.includes("computer")) return "computer"
        return "unknown"
    }

    // Flatten BluetoothDevice QObject to POJO -- NEVER expose QObject pointers.
    // Properties verified against quickshellX/src/bluetooth/device.hpp:
    //   address, name (alias-aware), deviceName, icon, state, connected, paired,
    //   bonded, pairing, trusted, blocked, wakeAllowed, batteryAvailable, battery
    function _flattenDevice(dev) {
        return {
            address: dev.address ?? "",
            name: dev.name || dev.deviceName || dev.address || "",
            deviceName: dev.deviceName ?? "",
            icon: dev.icon ?? "",
            type: _classifyDeviceType(dev),
            paired: dev.paired ?? false,
            trusted: dev.trusted ?? false,
            blocked: dev.blocked ?? false,
            connected: dev.connected ?? false,
            // state enum: Disconnected=0, Connected=1, Disconnecting=2, Connecting=3
            connecting: dev.state === BluetoothDeviceState.Connecting,
            pairing: dev.pairing ?? false,
            batteryAvailable: dev.batteryAvailable ?? false,
            battery: dev.batteryAvailable ? Math.round((dev.battery ?? 0) * 100) : null,
            // v0.2.0 SHOULD: pinned state (#155)
            isPinned: root.pinnedDevices.includes(dev.address ?? "")
        }
    }

    function _syncAdapterState() {
        var adapter = Bluetooth.defaultAdapter
        if (!adapter) {
            root.available = false
            root.powered = false
            root.discovering = false
            root.discoverable = false
            root.adapterName = ""
            root.adapterAddress = ""
            return
        }
        root.available = true
        root.powered = adapter.enabled
        root.discovering = adapter.discovering
        root.discoverable = adapter.discoverable
        root.adapterName = adapter.name ?? ""
        // BluetoothAdapter has adapterId (e.g. "hci0") and dbusPath, but no MAC address property.
        // Use adapterId as the identifier.
        root.adapterAddress = adapter.adapterId ?? ""
    }

    function _rebuildDevices() {
        var adapter = Bluetooth.defaultAdapter
        if (!adapter) {
            root.devices = []
            _syncAdapterState()
            return
        }

        var devs = adapter.devices.values
        var newDevices = []
        for (var i = 0; i < devs.length; i++) {
            newDevices.push(_flattenDevice(devs[i]))
        }
        root.devices = newDevices

        // Emit deviceAdded/deviceRemoved signals
        var newAddrs = newDevices.map(function(d) { return d.address })
        var oldAddrs = root._lastDeviceAddresses

        for (var j = 0; j < newAddrs.length; j++) {
            if (!oldAddrs.includes(newAddrs[j])) {
                var d = newDevices.find(function(dev) { return dev.address === newAddrs[j] })
                if (d) root.deviceAdded(d)
            }
        }
        for (var k = 0; k < oldAddrs.length; k++) {
            if (!newAddrs.includes(oldAddrs[k])) {
                root.deviceRemoved(oldAddrs[k])
            }
        }
        root._lastDeviceAddresses = newAddrs
        _syncAdapterState()
    }

    // ======================================================================
    // Private: watch for changes via Connections on Bluetooth singleton
    // ======================================================================

    Connections {
        target: Bluetooth
        function onDefaultAdapterChanged() {
            root._rebuildDevices()
            if (!root.ready) {
                // Ready when adapter exists (even if null -- means BT unavailable)
                root.ready = true
            }
        }
    }

    Timer {
        id: rebuildDebounce
        interval: 50
        repeat: false
        onTriggered: root._rebuildDevices()
    }

    // Signal-driven device list updates: watch adapter.devices for onValuesChanged
    Connections {
        target: Bluetooth.defaultAdapter?.devices ?? null
        function onValuesChanged() { rebuildDebounce.restart() }
    }

    // 30s fallback poll for RSSI/battery which don't fire signals
    Timer {
        interval: 30000
        running: root.available
        repeat: true
        onTriggered: root._rebuildDevices()
    }

    // ======================================================================
    // Pull-data fallback: getData(key)
    // ======================================================================

    function getData(key) {
        if (key === "devices") return JSON.stringify(root.devices)
        if (key === "pairedDevices") return JSON.stringify(root.pairedDevices)
        if (key === "connectedDevices") return JSON.stringify(root.connectedDevices)
        if (key === "adapter") return JSON.stringify({
            available: root.available,
            powered: root.powered,
            discovering: root.discovering,
            discoverable: root.discoverable,
            name: root.adapterName,
            address: root.adapterAddress
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
                console.warn("BluetoothBridge: HEALTH CHECK — not ready after 3s")
            } else {
                console.info("BluetoothBridge: healthy")
            }
        }
    }

    Component.onCompleted: {
        _rebuildDevices()
        // Ready immediately: adapter may be null (BT unavailable) but we know the state
        if (Bluetooth.defaultAdapter !== null) {
            root.ready = true
        } else {
            // No adapter = BT unavailable, still mark ready (available=false is valid state)
            root.ready = true
        }
        console.info("BluetoothBridge: initialized, adapter available:", root.available)
    }
}
