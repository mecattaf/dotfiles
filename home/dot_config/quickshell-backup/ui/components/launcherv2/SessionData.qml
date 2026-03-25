pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool isLightMode: false
    property string launcherLastMode: "all"
    property var pinnedApps: []
    property var hiddenApps: []
    property var appOverrides: ({})

    function setLauncherLastMode(mode) { launcherLastMode = mode; _save(); }
    function isPinnedApp(appId) { return pinnedApps.indexOf(appId) !== -1; }
    function addPinnedApp(appId) {
        if (!isPinnedApp(appId)) {
            pinnedApps = pinnedApps.concat([appId]);
            _save();
        }
    }
    function removePinnedApp(appId) {
        pinnedApps = pinnedApps.filter(function(id) { return id !== appId; });
        _save();
    }
    function hideApp(appId) {
        if (hiddenApps.indexOf(appId) === -1) {
            hiddenApps = hiddenApps.concat([appId]);
            _save();
        }
    }
    function isAppHidden(appId) { return hiddenApps.indexOf(appId) !== -1; }
    function getAppOverride(appId) { return appOverrides[appId] || null; }
    function setAppOverride(appId, override) {
        var o = Object.assign({}, appOverrides);
        if (!override || Object.keys(override).length === 0)
            delete o[appId];
        else
            o[appId] = override;
        appOverrides = o;
        _save();
    }
    function clearAppOverride(appId) {
        var o = Object.assign({}, appOverrides);
        delete o[appId];
        appOverrides = o;
        _save();
    }

    readonly property string _savePath: {
        var home = Quickshell.env("HOME") || "/tmp";
        return home + "/.config/quickshell/launcherv2-session.json";
    }

    Component.onCompleted: _load()

    function _load() {
        try {
            var proc = Quickshell.exec(["cat", _savePath]);
        } catch(e) {}
    }

    function _save() {
        var data = JSON.stringify({
            launcherLastMode: launcherLastMode,
            pinnedApps: pinnedApps,
            hiddenApps: hiddenApps,
            appOverrides: appOverrides
        });
        Quickshell.execDetached(["bash", "-c", "echo '" + data.replace(/'/g, "'\\''") + "' > " + _savePath]);
    }
}
