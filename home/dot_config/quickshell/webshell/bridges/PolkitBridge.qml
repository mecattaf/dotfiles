// PolkitBridge.qml -- wraps Quickshell.Services.Polkit (try/catch for graceful degradation)
// Auth flow state machine: idle -> prompting -> authenticating -> success/failed.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

QtObject {
    id: root
    default property list<QtObject> _children

    // ======================================================================
    // Public properties (os.polkit)
    // ======================================================================

    property string state: "idle"
    property var request: null
    readonly property bool isRegistered: _agent ? _agent.isRegistered : false
    property int failCount: 0

    // ======================================================================
    // Signals
    // ======================================================================

    signal requestArrived(var req)
    signal dismissed()

    // ======================================================================
    // Public methods (os.polkit)
    // ======================================================================

    function respond(password) {
        if (root.state !== "prompting" && root.state !== "failed") return
        if (root.state === "authenticating") return
        if (!_agent || !_agent.flow) return

        root.state = "authenticating"
        _agent.flow.respond(password)
    }

    function cancel() {
        if (root.state === "idle") return
        if (_agent && _agent.flow) {
            _agent.flow.cancel()
        }

        root.state = "cancelled"
        timeoutTimer.stop()
        root.dismissed()
        transientCleanup.restart()
    }

    function selectIdentity(uid) {
        if (!root.request) return
        var ident = root.request.identities.find(function(i) { return i.uid === uid })
        if (!ident) return
        root.request = Object.assign({}, root.request, { selectedIdentity: ident })
    }

    // ======================================================================
    // Private: graceful feature detection via Qt.createQmlObject
    // ======================================================================

    property bool polkitAvailable: false
    property var _agent: null

    function _createPolkitAgent() {
        try {
            var qmlString = 'import QtQuick; import Quickshell.Services.Polkit; PolkitAgent {}'
            _agent = Qt.createQmlObject(qmlString, root, "PolkitBridge.Agent")
            polkitAvailable = true
            console.info("PolkitBridge: initialized successfully")

            _agent.flowChanged.connect(_onFlowChanged)
        } catch (e) {
            polkitAvailable = false
            console.warn("PolkitBridge: Polkit not available:", e)
        }
    }

    function _onFlowChanged() {
        if (!_agent) return

        if (_agent.flow) {
            root.failCount = 0
            root.state = "prompting"

            var identities = []
            var flowIdentities = _agent.flow.identities ?? []
            for (var i = 0; i < flowIdentities.length; i++) {
                var ident = flowIdentities[i]
                identities.push({
                    uid: ident.uid ?? 0,
                    username: ident.username ?? "",
                    displayName: ident.displayName ?? ident.username ?? "",
                    isCurrentUser: ident.isCurrentUser ?? false
                })
            }

            root.request = {
                id: Date.now().toString(),
                message: _agent.flow.message ?? "",
                icon: _agent.flow.icon ?? null,
                cookie: _agent.flow.cookie ?? "",
                identities: identities,
                selectedIdentity: identities.find(function(i) { return i.isCurrentUser }) ?? identities[0] ?? null
            }

            timeoutTimer.restart()
            root.requestArrived(root.request)
        } else {
            if (root.state === "authenticating") {
                root.state = "success"
                root.dismissed()
                transientCleanup.restart()
            } else if (root.state !== "idle") {
                root.state = "cancelled"
                root.dismissed()
                transientCleanup.restart()
            }
        }
    }

    // ======================================================================
    // Private: timeout (90 seconds for the entire request)
    // ======================================================================

    Timer {
        id: timeoutTimer
        interval: 90000
        repeat: false
        onTriggered: {
            if (root.state !== "idle") {
                if (root._agent && root._agent.flow) root._agent.flow.cancel()
                root.state = "timeout"
                root.dismissed()
                transientCleanup.restart()
            }
        }
    }

    Timer {
        id: transientCleanup
        interval: 500
        repeat: false
        onTriggered: {
            root.state = "idle"
            root.request = null
            root.failCount = 0
            timeoutTimer.stop()
        }
    }

    Component.onCompleted: {
        if (Quickshell.env("WEBSHELL_DISABLE_POLKIT") === "1") {
            console.info("PolkitBridge: disabled via WEBSHELL_DISABLE_POLKIT")
            return
        }
        _createPolkitAgent()
    }
}
