pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root
    property var appUsageRanking: ({})

    function addAppUsage(app) {
        var appId = app.id || app.execString || app.exec || "";
        if (!appId) return;
        var entry = appUsageRanking[appId] || { usageCount: 0, lastUsed: 0 };
        entry.usageCount++;
        entry.lastUsed = Date.now();
        entry.name = app.name || "";
        var r = Object.assign({}, appUsageRanking);
        r[appId] = entry;
        appUsageRanking = r;
    }

    function getAppUsage(appId) {
        return appUsageRanking[appId] || null;
    }
}
