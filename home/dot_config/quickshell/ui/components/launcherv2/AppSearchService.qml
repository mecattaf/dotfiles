pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    property var _cachedDefaultSections: null
    property var _transformCache: ({})
    property int cacheVersion: 0

    readonly property var categoryIcons: ({
        "All": "apps",
        "Media": "play_circle",
        "Development": "code",
        "Games": "sports_esports",
        "Graphics": "palette",
        "Internet": "language",
        "Office": "description",
        "Settings": "settings",
        "System": "computer",
        "Utilities": "build"
    })

    readonly property var builtInPlugins: ({})

    function getCategoryIcon(category) {
        return categoryIcons[category] || "apps";
    }

    function searchApplications(query) {
        var apps = DesktopEntries.applications.values;
        if (!apps) return [];
        var result = [];
        for (var i = 0; i < apps.length; i++) {
            var app = apps[i];
            if (SessionData.isAppHidden(app.id || app.execString || ""))
                continue;
            if (!query || query.length === 0) {
                result.push(app);
            } else {
                var q = query.toLowerCase();
                var name = (app.name || "").toLowerCase();
                var comment = (app.comment || "").toLowerCase();
                if (name.includes(q) || comment.includes(q)) {
                    result.push(app);
                } else if (app.keywords) {
                    for (var k = 0; k < app.keywords.length; k++) {
                        if (app.keywords[k].toLowerCase().includes(q)) {
                            result.push(app);
                            break;
                        }
                    }
                }
            }
        }
        return result;
    }

    function getCoreApps(query) { return []; }
    function executeCoreApp(app) { return false; }

    function getAllCategories() {
        var apps = DesktopEntries.applications.values;
        if (!apps) return ["All"];
        var cats = {"All": true};
        for (var i = 0; i < apps.length; i++) {
            var categories = apps[i].categories;
            if (categories) {
                for (var j = 0; j < categories.length; j++) {
                    cats[categories[j]] = true;
                }
            }
        }
        return Object.keys(cats).sort();
    }

    function getAppsInCategory(category) {
        if (!category || category === "All") return searchApplications("");
        var apps = DesktopEntries.applications.values;
        if (!apps) return [];
        var result = [];
        for (var i = 0; i < apps.length; i++) {
            if (SessionData.isAppHidden(apps[i].id || apps[i].execString || ""))
                continue;
            var categories = apps[i].categories;
            if (categories && categories.indexOf(category) !== -1)
                result.push(apps[i]);
        }
        return result;
    }

    function getCategoriesForApp(app) { return []; }

    function getOrTransformApp(app, transformFn) {
        var appId = app.id || app.execString || app.exec || "";
        if (_transformCache[appId]) return _transformCache[appId];
        var item = transformFn(app);
        _transformCache[appId] = item;
        return item;
    }

    function invalidateLauncherCache() {
        _cachedDefaultSections = null;
        _transformCache = {};
        cacheVersion++;
    }

    function isCacheValid() { return _cachedDefaultSections !== null; }
    function getCachedDefaultSections() { return _cachedDefaultSections; }
    function setCachedDefaultSections(sections, flatModel) { _cachedDefaultSections = sections; }

    function getPluginItemsForPlugin(pluginId, query) { return []; }
    function getBuiltInLauncherItems(pluginId, query) { return []; }
    function getBuiltInLauncherTriggers() { return {}; }
    function getBuiltInLauncherPlugins() { return {}; }
    function getBuiltInLauncherPluginsWithEmptyTrigger() { return []; }
    function getBuiltInPluginTrigger(pluginId) { return ""; }
    function getPluginLauncherCategories(pluginId) { return []; }
    function setPluginLauncherCategory(pluginId, category) {}
    function getPluginPasteArgs(pluginId, data) { return null; }
}
