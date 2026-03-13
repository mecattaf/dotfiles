pragma Singleton

import QtQuick
import Quickshell

Singleton {
    function resolveIconUrl(iconName) {
        if (!iconName) return "";
        return Quickshell.iconPath(iconName);
    }
    function resolveIconPath(iconName) {
        if (!iconName) return "";
        return Quickshell.iconPath(iconName);
    }
    function strip(url) {
        var s = url.toString();
        if (s.startsWith("file://")) return s.substring(7);
        return s;
    }
}
