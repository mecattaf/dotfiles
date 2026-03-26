// PowerBridge.qml -- wraps Quickshell.Services.UPower
// Exposes batteries, charging state, percentage. Battery warning state machine.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.UPower

Scope {
    id: root

    // ======================================================================
    // Reactive properties (os.power)
    // ======================================================================

    readonly property var source: ({
        onBattery: UPower.onBattery ?? false,
        displayPercentage: UPower.displayDevice?.percentage ?? 100,
        displayState: _mapBatteryState(UPower.displayDevice?.state),
        displayTimeRemaining: _computeTimeRemaining()
    })

    property var batteries: []
    property var peripherals: []

    readonly property bool lidClosed: UPower.lidIsClosed ?? false

    // Power profiles (graceful: may not exist on all hardware)
    readonly property string profile: _powerProfilesAvailable ? _activeProfile : "balanced"
    readonly property var profilesAvailable: _powerProfilesAvailable ? _profiles : []

    // ======================================================================
    // Signals
    // ======================================================================

    signal batteryWarning(string level)

    // ======================================================================
    // Battery warning state machine
    // ======================================================================

    property string _warningState: "above_20"

    // ======================================================================
    // Power profiles (graceful feature detection)
    // ======================================================================

    property bool _powerProfilesAvailable: false
    property string _activeProfile: "balanced"
    property var _profiles: []
    property var _powerProfilesObj: null

    function _initPowerProfiles() {
        try {
            var qmlString = 'import QtQuick; import Quickshell.Services.UPower; PowerProfiles {}'
            _powerProfilesObj = Qt.createQmlObject(qmlString, root, "PowerBridge.PowerProfiles")
            _powerProfilesAvailable = true
            _activeProfile = _powerProfilesObj.activeProfile ?? "balanced"
            _profiles = _powerProfilesObj.profiles ?? []
            console.info("PowerBridge: PowerProfiles initialized")
        } catch (e) {
            _powerProfilesAvailable = false
            console.warn("PowerBridge: PowerProfiles not available:", e)
        }
    }

    // ======================================================================
    // Methods (os.power)
    // ======================================================================

    function setProfile(profileName) {
        if (!_powerProfilesAvailable || !_powerProfilesObj) return
        _powerProfilesObj.activeProfile = profileName
        _activeProfile = profileName
    }

    // ======================================================================
    // Internal helpers
    // ======================================================================

    function _mapBatteryState(state) {
        if (state === undefined || state === null) return "unknown"
        switch (state) {
            case 1: return "charging"
            case 2: return "discharging"
            case 3: return "empty"
            case 4: return "fully-charged"
            case 5: return "pending-charge"
            case 6: return "pending-discharge"
            default: return "unknown"
        }
    }

    function _mapPeripheralType(upowerType) {
        switch (upowerType) {
            case 5: return "mouse"
            case 6: return "keyboard"
            case 8: return "phone"
            case 9: return "media-player"
            case 10: return "tablet"
            case 12: return "headphones"
            case 13: return "headset"
            case 14: return "gaming-input"
            default: return "unknown"
        }
    }

    function _computeTimeRemaining() {
        var dev = UPower.displayDevice
        if (!dev) return null
        if (dev.timeToEmpty > 0) return dev.timeToEmpty
        if (dev.timeToFull > 0) return dev.timeToFull
        return null
    }

    function _flattenBattery(dev) {
        return {
            id: dev.path ?? "",
            percentage: dev.percentage ?? 0,
            state: _mapBatteryState(dev.state),
            timeToEmpty: dev.timeToEmpty > 0 ? dev.timeToEmpty : null,
            timeToFull: dev.timeToFull > 0 ? dev.timeToFull : null,
            energyRate: dev.energyRate ?? 0,
            capacity: dev.capacity ?? 100,
            isPresent: dev.isPresent ?? true,
            model: dev.model ?? "",
            icon: dev.iconName ?? "battery-missing-symbolic"
        }
    }

    function _flattenPeripheral(dev) {
        return {
            id: dev.path ?? "",
            percentage: dev.percentage ?? 0,
            state: _mapBatteryState(dev.state),
            model: dev.model ?? "",
            type: _mapPeripheralType(dev.type),
            icon: dev.iconName ?? "battery-missing-symbolic",
            isPresent: dev.isPresent ?? true
        }
    }

    function _rebuildDevices() {
        if (!UPower.devices?.values) {
            root.batteries = []
            root.peripherals = []
            return
        }
        var devs = UPower.devices.values
        var newBatteries = []
        var newPeripherals = []

        for (var i = 0; i < devs.length; i++) {
            var dev = devs[i]
            if (dev.type === 2) {
                newBatteries.push(_flattenBattery(dev))
            } else if (dev.type !== 1) {
                newPeripherals.push(_flattenPeripheral(dev))
            }
        }

        root.batteries = newBatteries
        root.peripherals = newPeripherals
    }

    function _evaluateWarning() {
        var pct = source.displayPercentage
        var state = source.displayState
        var isDischarging = (state === "discharging")

        if (pct >= 20 || !isDischarging) {
            root._warningState = "above_20"
            return
        }
        if (root._warningState === "above_20" && pct < 20) {
            root._warningState = "warned_low"
            root.batteryWarning("low")
        }
        if (root._warningState === "warned_low" && pct < 5) {
            root._warningState = "warned_critical"
            root.batteryWarning("critical")
        }
    }

    // ======================================================================
    // Connections
    // ======================================================================

    Connections {
        target: UPower.devices ?? null
        function onValuesChanged() { root._rebuildDevices() }
    }

    Connections {
        target: UPower.displayDevice ?? null
        function onPercentageChanged() { root._evaluateWarning() }
    }

    Component.onCompleted: {
        _rebuildDevices()
        _evaluateWarning()
        _initPowerProfiles()
    }
}
