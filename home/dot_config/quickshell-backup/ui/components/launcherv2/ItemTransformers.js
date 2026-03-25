.pragma library

.import "ControllerUtils.js" as Utils

function transformApp(app, override, defaultActions, primaryActionLabel) {
    var appId = app.id || app.execString || app.exec || "";
    var actions = [];
    if (app.actions && app.actions.length > 0) {
        for (var i = 0; i < app.actions.length; i++) {
            actions.push({ name: app.actions[i].name, icon: "play_arrow", actionData: app.actions[i] });
        }
    }
    return {
        id: appId, type: "app",
        name: override?.name || app.name || "",
        subtitle: override?.comment || app.comment || "",
        icon: override?.icon || app.icon || "application-x-executable",
        iconType: "image", section: "apps", data: app,
        keywords: app.keywords || [], actions: actions,
        primaryAction: { name: primaryActionLabel, icon: "open_in_new", action: "launch" },
        _hName: "", _hSub: "", _hRich: false, _preScored: undefined
    };
}

function transformCoreApp(app, openLabel) {
    return {
        id: app.builtInPluginId || app.action || "", type: "app",
        name: app.name || "", subtitle: app.comment || "",
        icon: app.icon || "apps", iconType: "material",
        section: "apps", data: app, isCore: true, actions: [],
        primaryAction: { name: openLabel, icon: "open_in_new", action: "launch" },
        _hName: "", _hSub: "", _hRich: false, _preScored: undefined
    };
}

function transformBuiltInLauncherItem(item, pluginId, openLabel) {
    return { id: "", type: "plugin", name: "", subtitle: "", icon: "extension",
        iconType: "material", section: "apps", data: item,
        _hName: "", _hSub: "", _hRich: false, _preScored: undefined };
}

function transformFileResult(file, openLabel, openFolderLabel, copyPathLabel, openTerminalLabel) {
    var filename = file.path ? file.path.split("/").pop() : "";
    var dirname = file.path ? file.path.substring(0, file.path.lastIndexOf("/")) : "";
    var isDir = file.is_dir || false;
    var actions = [];
    if (isDir) {
        if (openTerminalLabel) actions.push({ name: openTerminalLabel, icon: "terminal", action: "open_terminal" });
    } else {
        actions.push({ name: openFolderLabel, icon: "folder_open", action: "open_folder" });
    }
    actions.push({ name: copyPathLabel, icon: "content_copy", action: "copy_path" });
    return {
        id: file.path || "", type: "file",
        name: filename, subtitle: dirname,
        icon: isDir ? "folder" : Utils.getFileIcon(filename),
        iconType: "material", section: "files", data: file,
        actions: actions,
        primaryAction: { name: openLabel, icon: "open_in_new", action: "open" },
        _hName: "", _hSub: "", _hRich: false, _preScored: undefined
    };
}

function transformPluginItem(item, pluginId, selectLabel) {
    return { id: "", type: "plugin", name: "", subtitle: "", icon: "extension",
        iconType: "material", section: "apps", data: item,
        _hName: "", _hSub: "", _hRich: false, _preScored: undefined };
}

function createPluginBrowseItem(pluginId, plugin, trigger, isBuiltIn, isAllowed, browseLabel, triggerLabel, noTriggerLabel) {
    return { id: "browse_" + pluginId, type: "plugin_browse", name: pluginId, subtitle: "",
        icon: "extension", iconType: "material", section: "browse_plugins", data: {},
        actions: [], _hName: "", _hSub: "", _hRich: false, _preScored: undefined };
}
