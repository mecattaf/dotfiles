//@ pragma UseWebEngine

// Lockscreen.qml -- Wayland session lock surface with PAM authentication.
//
// Uses WlSessionLock (ext-session-lock-v1 protocol) instead of PanelWindow.
// The compositor TRUSTS this surface to fully cover the screen when locked.
// If this component is destroyed while locked, the compositor will keep the
// screen locked (painted solid) for security.
//
// The visual lockscreen UI is rendered by the SolidJS frontend in a
// WebEngineView. Authentication is handled by PamContext on the QML side.
// The frontend sends the password to SessionBridge.requestUnlock(), which
// calls this component's tryUnlock() method.
//
// Multi-screen: WlSessionLock automatically creates a WlSessionLockSurface
// for each connected screen via its default component mechanism.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtWebEngine
import QtWebChannel

Scope {
    id: root

    // ======================================================================
    // Required properties -- set by shell.qml
    // ======================================================================

    required property var channel
    required property string baseUrl

    // ======================================================================
    // Public interface -- called by SessionBridge
    // ======================================================================

    // Set to true to acquire the session lock. Set to false to release it.
    property bool lockRequested: false

    // Read by SessionBridge for lock state reporting
    readonly property bool isLocked: sessionLock.locked
    readonly property bool isSecure: sessionLock.secure

    // Authentication state pushed to SessionBridge
    property string authError: ""
    property string authMessage: ""
    property bool authActive: false

    signal lockAcquired()
    signal lockReleased()
    signal authSucceeded()
    signal authFailed(string message)

    // Try to unlock with the given password.
    // Called by SessionBridge.requestUnlock().
    function tryUnlock(password) {
        if (!sessionLock.locked) return
        if (pam.active) {
            // Already authenticating -- if PAM is waiting for a response,
            // provide it. Otherwise abort and restart.
            if (pam.responseRequired) {
                pam.respond(password)
                return
            }
            pam.abort()
        }
        root._pendingPassword = password
        root.authError = ""
        root.authMessage = ""
        root.authActive = true
        pam.start()
    }

    // ======================================================================
    // Private: pending password for PAM response
    // ======================================================================

    property string _pendingPassword: ""

    // ======================================================================
    // PAM authentication
    // ======================================================================

    // Auto-detect PAM service. Default to "login" which exists on most distros.
    // Can be overridden with WEBSHELL_PAM_SERVICE env var.
    property string _pamService: Quickshell.env("WEBSHELL_PAM_SERVICE") || "login"
    property bool _pamServiceDetected: false

    // Detect available PAM service on startup
    Process {
        id: pamDetectProc
        command: ["sh", "-c",
            "if [ -f /etc/pam.d/login ]; then echo login; exit 0; fi; " +
            "if [ -f /etc/pam.d/system-auth ]; then echo system-auth; exit 0; fi; " +
            "if [ -f /etc/pam.d/common-auth ]; then echo common-auth; exit 0; fi; " +
            "echo login"
        ]
        running: !root._pamServiceDetected && !Quickshell.env("WEBSHELL_PAM_SERVICE")
        stdout: SplitParser {
            onRead: data => {
                var service = data.trim()
                if (service) {
                    root._pamService = service
                    console.info("Lockscreen: detected PAM service:", service)
                }
                root._pamServiceDetected = true
            }
        }
    }

    PamContext {
        id: pam
        config: root._pamService
        // Use system PAM directory
        configDirectory: "/etc/pam.d"

        onPamMessage: {
            // Update the auth message for the frontend
            root.authMessage = pam.message
            root.authError = pam.messageIsError ? pam.message : ""
        }

        onResponseRequiredChanged: {
            if (!pam.responseRequired) return
            // PAM is asking for a password. If we have one pending, send it.
            if (root._pendingPassword !== "") {
                pam.respond(root._pendingPassword)
                root._pendingPassword = ""
            }
            // Otherwise, the frontend will call tryUnlock() with the password
            // and we will respond at that point.
        }

        onCompleted: function(result) {
            root.authActive = false
            if (result === PamResult.Success) {
                root.authError = ""
                root.authMessage = ""
                root._pendingPassword = ""
                // Release the session lock
                root.lockRequested = false
                root.authSucceeded()
            } else {
                root._pendingPassword = ""
                var errorMsg = ""
                switch (result) {
                    case PamResult.Failed:
                        errorMsg = "Authentication failed"
                        break
                    case PamResult.Error:
                        errorMsg = "Authentication error"
                        break
                    case PamResult.MaxTries:
                        errorMsg = "Too many attempts"
                        break
                    default:
                        errorMsg = "Authentication failed"
                }
                root.authError = errorMsg
                root.authFailed(errorMsg)
                // Reset after a delay so the user can try again
                _authResetTimer.restart()
            }
        }
    }

    Timer {
        id: _authResetTimer
        interval: 2000
        repeat: false
        onTriggered: {
            root.authError = ""
            root.authMessage = ""
        }
    }

    // ======================================================================
    // Session Lock
    // ======================================================================

    WlSessionLock {
        id: sessionLock

        // locked is driven by lockRequested. When lockRequested becomes true,
        // the session lock is acquired and lock surfaces cover all screens.
        locked: root.lockRequested

        onSecureChanged: {
            if (sessionLock.secure) {
                console.info("Lockscreen: session lock is secure (all screens covered)")
                root.lockAcquired()
            }
        }

        onLockStateChanged: {
            if (!sessionLock.locked) {
                console.info("Lockscreen: session lock released")
                root.lockReleased()
                // Clean up auth state
                if (pam.active) pam.abort()
                root._pendingPassword = ""
                root.authError = ""
                root.authMessage = ""
                root.authActive = false
            }
        }

        // Default surface component: created for each screen when locked.
        // Must be a WlSessionLockSurface.
        WlSessionLockSurface {
            id: lockSurface

            // Opaque background for security -- lockscreen must NEVER leak
            // desktop content through transparency.
            color: "#0a0a0a"

            WebEngineView {
                anchors.fill: parent
                backgroundColor: "#0a0a0a"
                webChannel: root.channel

                Component.onCompleted: url = root.baseUrl + "#/lock"

                onNewWindowRequested: function(request) {
                    Qt.openUrlExternally(request.requestedUrl)
                }

                settings.javascriptCanAccessClipboard: false
                settings.localContentCanAccessRemoteUrls: false
                settings.localContentCanAccessFileUrls: true
                settings.localStorageEnabled: true
                settings.focusOnNavigationEnabled: false
                settings.showScrollBars: false
                settings.linksIncludedInFocusChain: false

                // Suppress tooltip and context menu in lockscreen
                onTooltipRequested: function(request) { request.accepted = true }
                onContextMenuRequested: function(request) { request.accepted = true }
            }
        }
    }
}
