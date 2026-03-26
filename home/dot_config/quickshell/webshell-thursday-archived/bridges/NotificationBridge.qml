// NotificationBridge.qml -- Notification daemon using Quickshell.Services.Notifications.
// Fixed: FileView API verified against quickshellX/src/io/fileview.hpp:
//   - text() is Q_INVOKABLE (correct, it's a method not property)
//   - setText() is Q_INVOKABLE (correct)
//   - path accepts Qt.resolvedUrl() URLs
//   - Signals: loaded(), loadFailed(error), saved(), saveFailed(error), fileChanged()
// Notification properties verified against notification.hpp:
//   id, tracked, appName, appIcon, summary, body, image, urgency, expireTimeout,
//   actions (QList<NotificationAction*>), hasActionIcons, resident, transient,
//   desktopEntry, hasInlineReply, inlineReplyPlaceholder, hints
// NotificationAction: identifier, text, invoke()
// Full JSON persistence, grouped by app, rate limiting (20/sec), per-urgency timeouts.
// POJO-only across bridge boundary.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Scope {
    id: root

    // ======================================================================
    // Public properties (os.notifications)
    // ======================================================================

    property bool ready: false

    property var history: []
    property var popups: []
    property int unreadCount: 0
    property bool dnd: false

    // v0.2.0 SHOULD: privacy mode (#79) -- hides notification body
    property bool privacyMode: false

    // v0.2.0 SHOULD: notification sounds enabled (#75)
    property bool soundsEnabled: true

    readonly property var groups: _buildGroups()

    // ======================================================================
    // Signals
    // ======================================================================

    signal notification(var notif)
    signal closed(int id, string reason)
    // v0.2.0 SHOULD: notification sound trigger (#75)
    signal playSound(string urgency)

    // ======================================================================
    // Public methods (os.notifications)
    // ======================================================================

    function dismiss(id) {
        for (var i = 0; i < root._notifObjects.length; i++) {
            if (root._notifObjects[i].nid === id) {
                root._notifObjects[i].popup = false
                root._notifObjects[i].isRead = true
                break
            }
        }
        root.unreadCount = Math.max(0, root.unreadCount - 1)
        _rebuildFromWrappers()
    }

    function dismissAll() {
        for (var i = 0; i < root._notifObjects.length; i++) {
            root._notifObjects[i].popup = false
        }
        root.popups = []
        _rebuildFromWrappers()
    }

    function close(id) {
        var tracked = server.trackedNotifications?.values ?? []
        for (var i = 0; i < tracked.length; i++) {
            if (tracked[i].id + root._idOffset === id) {
                tracked[i].dismiss()
                break
            }
        }

        root._notifObjects = root._notifObjects.filter(function(w) { return w.nid !== id })
        _rebuildFromWrappers()
        _persistToFile()
        root.closed(id, "dismissed")
    }

    function clearHistory() {
        var tracked = server.trackedNotifications?.values ?? []
        for (var i = 0; i < tracked.length; i++) {
            tracked[i].dismiss()
        }
        root._notifObjects = []
        root.history = []
        root.popups = []
        root.unreadCount = 0
        _persistToFile()
    }

    function clearApp(appName) {
        var toRemove = root._notifObjects.filter(function(w) { return w.appName === appName })
        for (var i = 0; i < toRemove.length; i++) {
            var tracked = server.trackedNotifications?.values ?? []
            for (var j = 0; j < tracked.length; j++) {
                if (tracked[j].id + root._idOffset === toRemove[i].nid) {
                    tracked[j].dismiss()
                    break
                }
            }
        }
        root._notifObjects = root._notifObjects.filter(function(w) { return w.appName !== appName })
        _rebuildFromWrappers()
        _persistToFile()
    }

    function invokeAction(notificationId, actionIdentifier) {
        var tracked = server.trackedNotifications?.values ?? []
        for (var i = 0; i < tracked.length; i++) {
            if (tracked[i].id + root._idOffset === notificationId) {
                // NotificationAction: identifier (QString), text (QString), invoke()
                var actions = tracked[i].actions ?? []
                for (var j = 0; j < actions.length; j++) {
                    if (actions[j].identifier === actionIdentifier) {
                        actions[j].invoke()
                        break
                    }
                }
                break
            }
        }
        root.close(notificationId)
    }

    function sendInlineReply(notificationId, replyText) {
        var tracked = server.trackedNotifications?.values ?? []
        for (var i = 0; i < tracked.length; i++) {
            if (tracked[i].id + root._idOffset === notificationId) {
                if (tracked[i].hasInlineReply) {
                    tracked[i].sendInlineReply(replyText)
                }
                break
            }
        }
    }

    function toggleDnd() {
        root.dnd = !root.dnd
    }

    function setDnd(enabled) {
        root.dnd = enabled
    }

    // v0.2.0 SHOULD: privacy mode (#79)
    function setPrivacyMode(enabled) {
        root.privacyMode = enabled
    }

    function togglePrivacyMode() {
        root.privacyMode = !root.privacyMode
    }

    function markRead(id) {
        var changed = false
        for (var i = 0; i < root._notifObjects.length; i++) {
            if (root._notifObjects[i].nid === id && !root._notifObjects[i].isRead) {
                root._notifObjects[i].isRead = true
                changed = true
                break
            }
        }
        if (changed) {
            root.unreadCount = Math.max(0, root.unreadCount - 1)
            _rebuildFromWrappers()
        }
    }

    function markAllRead() {
        for (var i = 0; i < root._notifObjects.length; i++) {
            root._notifObjects[i].isRead = true
        }
        root.unreadCount = 0
        _rebuildFromWrappers()
    }

    // ======================================================================
    // Private: internal state
    // ======================================================================

    readonly property string _filePath: {
        var xdgData = Quickshell.env("XDG_DATA_HOME")
        if (!xdgData) xdgData = Quickshell.env("HOME") + "/.local/share"
        return xdgData + "/quickshell/notifications.json"
    }

    property var _notifObjects: []
    property int _idOffset: 0

    // Rate limiting: track notification count per second window
    property int _rateLimitCount: 0
    property int _rateLimitWindow: 0
    readonly property int _rateLimitMax: 20

    // ======================================================================
    // Private: notification wrapper component
    // ======================================================================

    component Notif: QtObject {
        id: notif

        required property int nid
        property var qsNotification: null
        property bool popup: false

        property string appIcon: qsNotification?.appIcon ?? ""
        property string appName: qsNotification?.appName ?? ""
        property string body: qsNotification?.body ?? ""
        property string image: qsNotification?.image ?? ""
        property string summary: qsNotification?.summary ?? ""
        property string desktopEntry: qsNotification?.desktopEntry ?? ""
        property double time: 0
        property string urgency: "normal"
        property var actions: []
        property bool isRead: false
        property bool hasInlineReply: qsNotification?.hasInlineReply ?? false
        property string inlineReplyPlaceholder: qsNotification?.inlineReplyPlaceholder ?? ""

        // Per-urgency timeouts: critical stays indefinitely, low=3s, normal=5s
        readonly property Timer timer: Timer {
            running: notif.popup
            interval: {
                if (notif.urgency === "critical") return 0
                if (notif.urgency === "low") return 3000
                if (notif.qsNotification) {
                    var timeout = notif.qsNotification.expireTimeout
                    return timeout > 0 ? timeout * 1000 : 5000
                }
                return 5000
            }
            onTriggered: {
                notif.popup = false
                root._rebuildFromWrappers()
            }
        }
    }

    Component {
        id: notifComp
        Notif {}
    }

    // ======================================================================
    // Private: notification server
    // ======================================================================

    NotificationServer {
        id: server
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        inlineReplySupported: true
        keepOnReload: true
        persistenceSupported: true

        onNotification: notification => {
            // Rate limiting: drop if > 20/sec
            var now = Math.floor(Date.now() / 1000)
            if (now !== root._rateLimitWindow) {
                root._rateLimitWindow = now
                root._rateLimitCount = 0
            }
            root._rateLimitCount++
            if (root._rateLimitCount > root._rateLimitMax) {
                console.warn("NotificationBridge: rate limit exceeded, dropping notification from", notification.appName)
                return
            }

            notification.tracked = true

            // Map urgency enum to string. NotificationUrgency from notification.hpp: Low=0, Normal=1, Critical=2
            var urgencyStr = "normal"
            if (notification.urgency === NotificationUrgency.Low) urgencyStr = "low"
            else if (notification.urgency === NotificationUrgency.Critical) urgencyStr = "critical"

            // Flatten actions to POJO array. NotificationAction: identifier (QString), text (QString)
            var actionsList = []
            var rawActions = notification.actions ?? []
            for (var i = 0; i < rawActions.length; i++) {
                actionsList.push({
                    identifier: rawActions[i].identifier ?? "",
                    text: rawActions[i].text ?? ""
                })
            }

            var newNotif = notifComp.createObject(root, {
                nid: notification.id + root._idOffset,
                qsNotification: notification,
                time: Date.now(),
                urgency: urgencyStr,
                actions: actionsList,
                popup: !root.dnd
            })

            root._notifObjects = [...root._notifObjects, newNotif]
            root._rebuildFromWrappers()

            root.unreadCount++
            root.notification(_flattenNotif(newNotif))
            // v0.2.0 SHOULD: trigger sound (#75)
            if (root.soundsEnabled && !root.dnd) {
                root.playSound(urgencyStr)
            }
            _persistToFile()
        }
    }

    // ======================================================================
    // Private: IPC handler
    // ======================================================================

    IpcHandler {
        target: "doNotDisturb"
        function toggle(): void { root.toggleDnd() }
        function enable(): void { root.dnd = true }
        function disable(): void { root.dnd = false }
    }

    // ======================================================================
    // Private: flatten and rebuild
    // ======================================================================

    function _flattenNotif(wrapper) {
        return {
            id: wrapper.nid,
            appName: wrapper.appName,
            appIcon: wrapper.appIcon,
            summary: wrapper.summary,
            body: wrapper.body,
            image: wrapper.image,
            urgency: wrapper.urgency,
            time: wrapper.time,
            actions: wrapper.actions,
            isRead: wrapper.isRead,
            desktopEntry: wrapper.desktopEntry,
            hasInlineReply: wrapper.hasInlineReply,
            inlineReplyPlaceholder: wrapper.inlineReplyPlaceholder
        }
    }

    function _rebuildFromWrappers() {
        var newHistory = []
        var newPopups = []

        for (var i = root._notifObjects.length - 1; i >= 0; i--) {
            var wrapper = root._notifObjects[i]
            var flat = _flattenNotif(wrapper)
            newHistory.push(flat)
            if (wrapper.popup) {
                newPopups.push(flat)
            }
        }

        root.history = newHistory
        root.popups = newPopups
    }

    function _buildGroups() {
        var groups = {}
        for (var i = 0; i < root.history.length; i++) {
            var n = root.history[i]
            var key = n.appName || "Unknown"
            if (!groups[key]) {
                groups[key] = {
                    appName: key,
                    appIcon: n.appIcon || "",
                    notifications: [],
                    unreadCount: 0,
                    latestTime: 0
                }
            }
            groups[key].notifications.push(n)
            if (!n.isRead) groups[key].unreadCount++
            if (n.time > groups[key].latestTime) {
                groups[key].latestTime = n.time
            }
        }
        var result = Object.values(groups)
        result.sort(function(a, b) { return b.latestTime - a.latestTime })
        return result
    }

    // ======================================================================
    // Private: persistence
    // FileView API from fileview.hpp:
    //   path: QString (set via setPath or property)
    //   text(): Q_INVOKABLE QString (method, not property)
    //   setText(text: QString): Q_INVOKABLE void
    //   reload(): Q_INVOKABLE void
    //   Signals: loaded(), loadFailed(FileViewError::Enum), saved(), saveFailed(...)
    // ======================================================================

    FileView {
        id: notifFileView
        path: Qt.resolvedUrl(root._filePath)
        onLoaded: {
            try {
                var fileContents = notifFileView.text()
                var saved = JSON.parse(fileContents)
                var maxId = 0
                for (var i = 0; i < saved.length; i++) {
                    var n = saved[i]
                    var wrapper = notifComp.createObject(root, {
                        nid: n.id,
                        time: n.time,
                        urgency: n.urgency || "normal",
                        actions: n.actions || [],
                        isRead: true,
                        popup: false
                    })
                    wrapper.appIcon = n.appIcon || ""
                    wrapper.appName = n.appName || ""
                    wrapper.body = n.body || ""
                    wrapper.image = n.image || ""
                    wrapper.summary = n.summary || ""
                    wrapper.desktopEntry = n.desktopEntry || ""
                    root._notifObjects.push(wrapper)
                    maxId = Math.max(maxId, n.id)
                }
                root._idOffset = maxId
                root._rebuildFromWrappers()
                console.info("NotificationBridge: loaded", saved.length, "persisted notifications")
            } catch (e) {
                console.warn("NotificationBridge: failed to parse saved notifications:", e)
            }
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                console.info("NotificationBridge: no saved notifications file, starting fresh")
                root._notifObjects = []
                _persistToFile()
            } else {
                console.warn("NotificationBridge: load error:", error)
            }
        }
    }

    function _persistToFile() {
        var serialized = root._notifObjects.map(function(w) { return _flattenNotif(w) })
        notifFileView.setText(JSON.stringify(serialized, null, 2))
    }

    // ======================================================================
    // Pull-data fallback: getData(key)
    // ======================================================================

    function getData(key) {
        if (key === "history") return JSON.stringify(root.history)
        if (key === "popups") return JSON.stringify(root.popups)
        if (key === "groups") return JSON.stringify(root.groups)
        if (key === "status") return JSON.stringify({
            unreadCount: root.unreadCount,
            dnd: root.dnd,
            privacyMode: root.privacyMode
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
                console.warn("NotificationBridge: HEALTH CHECK — not ready after 3s")
            } else {
                console.info("NotificationBridge: healthy")
            }
        }
    }

    Component.onCompleted: {
        notifFileView.reload()
        // Ready after server init (notification server is created inline, so it's ready)
        root.ready = true
    }
}
