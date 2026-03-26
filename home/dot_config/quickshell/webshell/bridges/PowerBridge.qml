// PowerBridge.qml -- wraps Quickshell.Services.UPower
// Exposes batteries, charging state, percentage. Battery warning state machine.
// PowerProfiles (graceful: may not exist on all hardware).
//
// Fixed: removed UPower.lidIsClosed (doesn't exist in QS API),
// fixed energyRate -> changeRate, activeProfile -> profile,
// flattened battery/peripheral to POJOs with correct property names.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Scope {
    id: root

    // ======================================================================
    // Public properties (os.power)
    // ======================================================================

    readonly property var source: ({
        onBattery: UPower.onBattery ?? false,
        displayPercentage: UPower.displayDevice ? UPower.displayDevice.percentage : 100,
        displayState: _mapBatteryState(UPower.displayDevice ? UPower.displayDevice.state : null),
        displayTimeRemaining: _computeTimeRemaining()
    })

    property var batteries: []
    property var peripherals: []

    // NOTE: UPower.lidIsClosed does NOT exist in the QS UPower API.
    // Lid state would need to come from logind D-Bus. Removed.

    // PowerProfiles: property name is "profile" (not "activeProfile")
    readonly property string profile: _powerProfilesAvailable ? _activeProfile : "balanced"
    readonly property bool hasPerformanceProfile: _powerProfilesAvailable ? _hasPerformance : false
    readonly property var profilesAvailable: _powerProfilesAvailable ? _profiles : []

    // v0.2.0 SHOULD: hibernate detection (#219)
    property bool canHibernate: false
    // v0.2.0 SHOULD: suspend-then-hibernate (#220)
    property bool canSuspendThenHibernate: false

    // ======================================================================
    // Signals
    // ======================================================================

    signal batteryWarning(string level)

    // ======================================================================
    // Public methods (os.power)
    // ======================================================================

    function setProfile(profileName) {
        if (!_powerProfilesAvailable) return
        // PowerProfiles.profile is writable; accepts PowerProfile enum values.
        // Map string to enum for safety.
        switch (profileName) {
            case "power-saver":
                PowerProfiles.profile = PowerProfile.PowerSaver
                _activeProfile = "power-saver"
                break
            case "balanced":
                PowerProfiles.profile = PowerProfile.Balanced
                _activeProfile = "balanced"
                break
            case "performance":
                if (_hasPerformance) {
                    PowerProfiles.profile = PowerProfile.Performance
                    _activeProfile = "performance"
                }
                break
        }
    }

    // ======================================================================
    // Private: battery warning state machine
    // ======================================================================

    property string _warningState: "above_20"

    // ======================================================================
    // Private: power profiles (graceful feature detection)
    // ======================================================================

    property bool _powerProfilesAvailable: false
    property string _activeProfile: "balanced"
    property bool _hasPerformance: false
    property var _profiles: []

    function _mapProfileEnum(enumVal) {
        switch (enumVal) {
            case PowerProfile.PowerSaver: return "power-saver"
            case PowerProfile.Balanced: return "balanced"
            case PowerProfile.Performance: return "performance"
            default: return "balanced"
        }
    }

    function _initPowerProfiles() {
        try {
            // PowerProfiles is a QML singleton from Quickshell.Services.UPower.
            // It's always defined when the module is imported, but data may be
            // invalid if power-profiles-daemon is not installed.
            // Check if we get a valid profile value.
            var p = PowerProfiles.profile
            _powerProfilesAvailable = true
            _activeProfile = _mapProfileEnum(p)
            _hasPerformance = PowerProfiles.hasPerformanceProfile ?? false
            _rebuildProfilesList()
            console.info("PowerBridge: PowerProfiles initialized, profile:", _activeProfile)
        } catch (e) {
            _powerProfilesAvailable = false
            console.info("PowerBridge: PowerProfiles not available:", e)
        }
    }

    function _rebuildProfilesList() {
        var profiles = ["power-saver", "balanced"]
        if (_hasPerformance) profiles.push("performance")
        _profiles = profiles
    }

    // Watch for profile changes from PowerProfiles singleton
    Connections {
        target: _powerProfilesAvailable ? PowerProfiles : null
        function onProfileChanged() {
            root._activeProfile = root._mapProfileEnum(PowerProfiles.profile)
        }
        function onHasPerformanceProfileChanged() {
            root._hasPerformance = PowerProfiles.hasPerformanceProfile ?? false
            root._rebuildProfilesList()
        }
    }

    // ======================================================================
    // Private: helpers
    // ======================================================================

    function _mapBatteryState(state) {
        if (state === undefined || state === null) return "unknown"
        switch (state) {
            case UPowerDeviceState.Unknown: return "unknown"
            case UPowerDeviceState.Charging: return "charging"
            case UPowerDeviceState.Discharging: return "discharging"
            case UPowerDeviceState.Empty: return "empty"
            case UPowerDeviceState.FullyCharged: return "fully-charged"
            case UPowerDeviceState.PendingCharge: return "pending-charge"
            case UPowerDeviceState.PendingDischarge: return "pending-discharge"
            default: return "unknown"
        }
    }

    function _mapDeviceType(upowerType) {
        // UPowerDeviceType enum values from device.hpp
        switch (upowerType) {
            case UPowerDeviceType.Mouse: return "mouse"
            case UPowerDeviceType.Keyboard: return "keyboard"
            case UPowerDeviceType.Phone: return "phone"
            case UPowerDeviceType.MediaPlayer: return "media-player"
            case UPowerDeviceType.Tablet: return "tablet"
            case UPowerDeviceType.GamingInput: return "gaming-input"
            case UPowerDeviceType.Pen: return "pen"
            case UPowerDeviceType.Touchpad: return "touchpad"
            case UPowerDeviceType.Headset: return "headset"
            case UPowerDeviceType.Speakers: return "speakers"
            case UPowerDeviceType.Headphones: return "headphones"
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
            // UPowerDevice has nativePath, not "path"
            id: dev.nativePath ?? "",
            percentage: dev.percentage ?? 0,
            state: _mapBatteryState(dev.state),
            timeToEmpty: dev.timeToEmpty > 0 ? dev.timeToEmpty : null,
            timeToFull: dev.timeToFull > 0 ? dev.timeToFull : null,
            // Property is "changeRate" (not "energyRate")
            changeRate: dev.changeRate ?? 0,
            energy: dev.energy ?? 0,
            energyCapacity: dev.energyCapacity ?? 0,
            // Health via healthPercentage (not "capacity")
            healthPercentage: dev.healthPercentage ?? 0,
            healthSupported: dev.healthSupported ?? false,
            isPresent: dev.isPresent ?? true,
            model: dev.model ?? "",
            icon: dev.iconName ?? "battery-missing-symbolic"
        }
    }

    function _flattenPeripheral(dev) {
        return {
            id: dev.nativePath ?? "",
            percentage: dev.percentage ?? 0,
            state: _mapBatteryState(dev.state),
            model: dev.model ?? "",
            type: _mapDeviceType(dev.type),
            icon: dev.iconName ?? "battery-missing-symbolic",
            isPresent: dev.isPresent ?? true
        }
    }

    function _rebuildDevices() {
        if (!UPower.devices) {
            root.batteries = []
            root.peripherals = []
            return
        }
        var devs = UPower.devices.values
        var newBatteries = []
        var newPeripherals = []

        for (var i = 0; i < devs.length; i++) {
            var dev = devs[i]
            // Use UPowerDeviceType enum instead of magic numbers.
            // isLaptopBattery = (type == Battery && powerSupply == true)
            if (dev.isLaptopBattery) {
                newBatteries.push(_flattenBattery(dev))
            } else if (dev.type !== UPowerDeviceType.LinePower && dev.type !== UPowerDeviceType.Battery) {
                // Non-battery, non-line-power = peripheral
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
    // Private: connections
    // ======================================================================

    Connections {
        target: UPower.devices ?? null
        function onValuesChanged() { root._rebuildDevices() }
    }

    Connections {
        target: UPower.displayDevice ?? null
        function onPercentageChanged() { root._evaluateWarning() }
    }

    // v0.2.0 SHOULD: hibernate detection (#219)
    Process {
        command: ["cat", "/sys/power/state"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                var states = data.trim().split(/\s+/)
                root.canHibernate = states.indexOf("disk") >= 0
                root.canSuspendThenHibernate = states.indexOf("disk") >= 0 && states.indexOf("mem") >= 0
            }
        }
    }

    Component.onCompleted: {
        _rebuildDevices()
        _evaluateWarning()
        _initPowerProfiles()
    }
}
