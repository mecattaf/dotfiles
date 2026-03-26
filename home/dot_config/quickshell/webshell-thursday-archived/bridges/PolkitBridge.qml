// PolkitBridge.qml -- wraps Quickshell.Services.Polkit for authentication prompts.
// Fixed: all API names verified against quickshellX/src/services/polkit/*.hpp.
//   - flow.respond() -> flow.submit()
//   - flow.cancel() -> flow.cancelAuthenticationRequest()
//   - flow.icon -> flow.iconName
//   - ident.uid -> ident.id, ident.username -> ident.string
//   - Uses Connections on AuthFlow for success/failure signals
// POJO-only across bridge boundary.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Polkit

Scope {
    id: root

    // ======================================================================
    // Public properties (os.polkit)
    // ======================================================================

    property bool ready: false

    property string state: "idle"
    property var request: null
    readonly property bool isRegistered: agent.isRegistered
    property int failCount: 0

    // ======================================================================
    // Signals
    // ======================================================================

    signal requestArrived(var req)
    signal dismissed()

    // ======================================================================
    // Public methods (os.polkit)
    // ======================================================================

    // respond() kept as the public method name to match the TS spec (os.polkit.respond).
    // Internally calls flow.submit() per quickshellX API.
    function respond(password) {
        if (root.state !== "prompting" && root.state !== "failed") return
        if (root.state === "authenticating") return
        if (!agent.flow) return

        root.state = "authenticating"
        agent.flow.submit(password)
    }

    // cancel() kept as the public method name to match the TS spec (os.polkit.cancel).
    // Internally calls flow.cancelAuthenticationRequest() per quickshellX API.
    function cancel() {
        if (root.state === "idle") return
        if (agent.flow) {
            agent.flow.cancelAuthenticationRequest()
        }

        root.state = "cancelled"
        timeoutTimer.stop()
        root.dismissed()
        transientCleanup.restart()
    }

    function selectIdentity(uid) {
        if (!root.request) return
        // Find the matching identity in our POJO list
        var ident = root.request.identities.find(function(i) { return i.uid === uid })
        if (!ident) return
        root.request = Object.assign({}, root.request, { selectedIdentity: ident })

        // Also set on the actual flow if still active.
        // Identity.id is a quint32 (uid/gid), match against it.
        if (agent.flow) {
            var flowIdents = agent.flow.identities ?? []
            for (var i = 0; i < flowIdents.length; i++) {
                if (flowIdents[i].id === uid) {
                    agent.flow.selectedIdentity = flowIdents[i]
                    break
                }
            }
        }
    }

    // ======================================================================
    // Private: PolkitAgent (direct instantiation)
    // ======================================================================

    PolkitAgent {
        id: agent
    }

    // Watch for flow changes on the PolkitAgent
    Connections {
        target: agent
        function onFlowChanged() {
            root._onFlowChanged()
        }
    }

    // Watch for AuthFlow signals when a flow is active.
    // AuthFlow signals verified from flow.hpp:
    //   authenticationSucceeded(), authenticationFailed(), authenticationRequestCancelled()
    //   isResponseRequiredChanged(), isCompletedChanged(), supplementaryMessageChanged()
    Connections {
        id: flowConn
        target: agent.flow ?? null

        function onAuthenticationSucceeded() {
            root.state = "success"
            timeoutTimer.stop()
            root.dismissed()
            transientCleanup.restart()
        }

        function onAuthenticationFailed() {
            root.failCount++
            root.state = "failed"

            // Auto-cancel after 3 failures
            if (root.failCount >= 3) {
                root.cancel()
            }
        }

        function onAuthenticationRequestCancelled() {
            if (root.state !== "idle") {
                root.state = "cancelled"
                timeoutTimer.stop()
                root.dismissed()
                transientCleanup.restart()
            }
        }

        function onSupplementaryMessageChanged() {
            // Update the request with supplementary info if available
            if (agent.flow && root.request) {
                root.request = Object.assign({}, root.request, {
                    supplementaryMessage: agent.flow.supplementaryMessage ?? "",
                    supplementaryIsError: agent.flow.supplementaryIsError ?? false
                })
            }
        }
    }

    function _onFlowChanged() {
        if (agent.flow) {
            root.failCount = 0
            root.state = "prompting"

            // Flatten identities to POJOs.
            // Identity properties from identity.hpp:
            //   id (quint32), string (name), displayName, isGroup
            var identities = []
            var flowIdentities = agent.flow.identities ?? []
            for (var i = 0; i < flowIdentities.length; i++) {
                var ident = flowIdentities[i]
                identities.push({
                    uid: ident.id ?? 0,
                    username: ident.string ?? "",
                    displayName: ident.displayName ?? ident.string ?? "",
                    isGroup: ident.isGroup ?? false,
                    // isCurrentUser: approximate by checking against current UID
                    isCurrentUser: !ident.isGroup && (ident.id === _currentUid)
                })
            }

            // Flatten the request to a POJO.
            // AuthFlow properties from flow.hpp:
            //   message, iconName, actionId, cookie, identities, selectedIdentity,
            //   isResponseRequired, inputPrompt, responseVisible,
            //   supplementaryMessage, supplementaryIsError,
            //   isCompleted, isSuccessful, isCancelled, failed
            root.request = {
                id: Date.now().toString(),
                message: agent.flow.message ?? "",
                icon: agent.flow.iconName ?? null,
                actionId: agent.flow.actionId ?? "",
                cookie: agent.flow.cookie ?? "",
                identities: identities,
                selectedIdentity: identities.find(function(i) { return i.isCurrentUser }) ?? identities[0] ?? null,
                inputPrompt: agent.flow.inputPrompt ?? "",
                responseVisible: agent.flow.responseVisible ?? false
            }

            timeoutTimer.restart()
            root.requestArrived(root.request)
        } else {
            // Flow became null. If we were in authenticating/prompting and didn't get
            // an explicit success/failure signal, treat as cancelled.
            if (root.state !== "idle" && root.state !== "success" && root.state !== "cancelled" && root.state !== "timeout") {
                root.state = "cancelled"
                root.dismissed()
                transientCleanup.restart()
            }
        }
    }

    // ======================================================================
    // Private: current UID for isCurrentUser detection
    // ======================================================================

    readonly property int _currentUid: {
        var uid = parseInt(Quickshell.env("UID") ?? Quickshell.env("EUID") ?? "0")
        return isNaN(uid) ? 0 : uid
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
                if (agent.flow) agent.flow.cancelAuthenticationRequest()
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

    // ======================================================================
    // Health check timer
    // ======================================================================

    Timer {
        interval: 3000
        running: true
        repeat: false
        onTriggered: {
            if (!root.ready) {
                console.warn("PolkitBridge: HEALTH CHECK — not ready after 3s")
            } else {
                console.info("PolkitBridge: healthy")
            }
        }
    }

    Component.onCompleted: {
        if (Quickshell.env("WEBSHELL_DISABLE_POLKIT") === "1") {
            console.info("PolkitBridge: disabled via WEBSHELL_DISABLE_POLKIT")
            root.ready = true
            return
        }
        root.ready = true
        console.info("PolkitBridge: initialized, isRegistered:", agent.isRegistered)
    }
}
