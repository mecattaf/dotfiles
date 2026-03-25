pragma Singleton

import QtQuick
import Quickshell

Singleton {
    // Launcher size
    readonly property string dankLauncherV2Size: "default"
    readonly property bool dankLauncherV2BorderEnabled: false
    readonly property string dankLauncherV2BorderColor: "primary"
    readonly property int dankLauncherV2BorderThickness: 1
    readonly property bool dankLauncherV2UnloadOnClose: false
    readonly property bool dankLauncherV2ShowFooter: true
    readonly property int appLauncherGridColumns: 4
    readonly property bool spotlightCloseNiriOverview: true
    readonly property bool modalDarkenBackground: true
    readonly property bool modalElevationEnabled: true
    readonly property bool popoutElevationEnabled: true
    readonly property bool m3ElevationEnabled: true
    readonly property bool sortAppsAlphabetically: false
    readonly property bool enableRippleEffects: true
    readonly property string launchPrefix: ""
    property var spotlightSectionViewModes: ({})
    property var appDrawerSectionViewModes: ({})
    property var launcherPluginVisibility: ({})
    property var launcherPluginOrder: []

    enum AnimationSpeed { None, Reduced, Normal }
    readonly property int currentAnimationSpeed: SettingsData.AnimationSpeed.Normal

    function getPluginAllowWithoutTrigger(pluginId) { return false; }
    function setPluginAllowWithoutTrigger(pluginId, allowed) {}
}
