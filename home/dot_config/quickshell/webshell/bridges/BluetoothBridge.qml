// BluetoothBridge.qml -- wraps Quickshell.Bluetooth (try/catch for graceful degradation)
// Exposes adapter, devices, powered state.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

QtObject {
    id: root

    // ======================================================================
    // Public properties (os.bluetooth)
    // ======================================================================

    property bool available: false
    property bool powered: false
    property bool discovering: false
    property bool discoverable: false
    property string adapterName: ""
    property string adapterAddress: ""

    property var devices: []
    readonly property var pairedDevices: root.devices.filter(function(d) { return d.paired })
    readonly property var connectedDevices: root.devices.filter(function(d) { return d.connected })

    // ======================================================================
    // Signals
    // ======================================================================

    signal deviceAdded(var device)
    signal deviceRemoved(string address)

    // ======================================================================
    // Public methods (os.bluetooth)
    // ======================================================================

    function setPower(on) {
        if (_btAdapter) _btAdapter.powered = on
    }

    function startDiscovery() {
        if (_btAdapter && _btAdapter.powered) _btAdapter.startDiscovery()
    }

    function stopDiscovery() {
        if (_btAdapter) _btAdapter.stopDiscovery()
    }

    function setDiscoverable(on) {
        if (_btAdapter) _btAdapter.discoverable = on
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
        if (dev) dev.cancelPairing()
    }

    function removeDevice(address) {
        if (!_btAdapter) return
        var dev = _findQsDevice(address)
        if (dev) _btAdapter.removeDevice(dev)
    }

    function trust(address) {
        var dev = _findQsDevice(address)
        if (dev) dev.trusted = true
    }

    function untrust(address) {
        var dev = _findQsDevice(address)
        if (dev) dev.trusted = false
    }

    // ======================================================================
    // Private: graceful Bluetooth module detection
    // ======================================================================

    property bool _btAvailable: false
    property var _btAdapter: null
    property var _btDevices: null
    property var _lastDeviceAddresses: []

    function _initBluetooth() {
        try {
            var qmlString = 'import QtQuick; import Quickshell.Bluetooth; QtObject { property var adapter: Bluetooth.adapter; property var devices: Bluetooth.devices }'
            var bt = Qt.createQmlObject(qmlString, root, "BluetoothBridge.BT")
            _btAvailable = true
            _btAdapter = Qt.binding(function() { return bt.adapter })
            _btDevices = Qt.binding(function() { return bt.devices })
            _syncAdapterState()
            _rebuildDevices()
            console.info("BluetoothBridge: initialized")
        } catch (e) {
            _btAvailable = false
            console.warn("BluetoothBridge: Bluetooth module not available:", e)
        }
    }

    function _syncAdapterState() {
        if (!_btAvailable || !_btAdapter) {
            root.available = false
            root.powered = false
            root.discovering = false
            root.discoverable = false
            root.adapterName = ""
            root.adapterAddress = ""
            return
        }
        root.available = _btAdapter !== null
        root.powered = _btAdapter?.powered ?? false
        root.discovering = _btAdapter?.discovering ?? false
        root.discoverable = _btAdapter?.discoverable ?? false
        root.adapterName = _btAdapter?.alias ?? ""
        root.adapterAddress = _btAdapter?.address ?? ""
    }

    function _findQsDevice(address) {
        if (!_btDevices?.values) return null
        return _btDevices.values.find(function(d) { return d.address === address }) ?? null
    }

    function _classifyDeviceType(device) {
        var icon = (device.icon ?? "").toLowerCase()
        if (icon.includes("headset")) return "audio-headset"
        if (icon.includes("headphone")) return "audio-headphones"
        if (icon.includes("speaker")) return "audio-speakers"
        if (icon.includes("keyboard")) return "input-keyboard"
        if (icon.includes("mouse")) return "input-mouse"
        if (icon.includes("phone")) return "phone"
        if (icon.includes("computer")) return "computer"
        return "unknown"
    }

    function _flattenDevice(dev) {
        return {
            address: dev.address ?? "",
            name: dev.alias || dev.name || dev.address || "",
            alias: dev.alias ?? "",
            icon: dev.icon ?? "",
            type: _classifyDeviceType(dev),
            paired: dev.paired ?? false,
            trusted: dev.trusted ?? false,
            blocked: dev.blocked ?? false,
            connected: dev.connected ?? false,
            connecting: dev.connecting ?? false,
            rssi: dev.rssi ?? null,
            battery: dev.battery ?? null
        }
    }

    function _rebuildDevices() {
        if (!_btDevices?.values) {
            root.devices = []
            return
        }
        var devs = _btDevices.values
        var newDevices = devs.map(function(d) { return _flattenDevice(d) })
        root.devices = newDevices

        var newAddrs = newDevices.map(function(d) { return d.address })
        var oldAddrs = root._lastDeviceAddresses

        for (var i = 0; i < newAddrs.length; i++) {
            if (!oldAddrs.includes(newAddrs[i])) {
                var d = newDevices.find(function(dev) { return dev.address === newAddrs[i] })
                if (d) root.deviceAdded(d)
            }
        }
        for (var j = 0; j < oldAddrs.length; j++) {
            if (!newAddrs.includes(oldAddrs[j])) {
                root.deviceRemoved(oldAddrs[j])
            }
        }
        root._lastDeviceAddresses = newAddrs
        _syncAdapterState()
    }

    // ======================================================================
    // Private: watch for changes
    // ======================================================================

    Timer {
        id: rebuildDebounce
        interval: 50
        repeat: false
        onTriggered: root._rebuildDevices()
    }

    Timer {
        interval: 2000
        running: root._btAvailable
        repeat: true
        onTriggered: root._rebuildDevices()
    }

    Component.onCompleted: {
        _initBluetooth()
    }
}
