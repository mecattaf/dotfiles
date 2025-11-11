import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // Status properties
    property bool running: false
    property bool connected: false
    property string exitNodeName: ""
    property string exitNodeId: ""
    property bool isBusy: false

    // Settings properties
    property bool acceptDns: false
    property bool acceptRoutes: false
    property bool allowLanAccess: false
    property bool shieldsUp: false
    property bool runSsh: false

    // Data properties
    property var nodes: []
    property var profiles: []

    // Signals
    signal statusChanged()
    signal nodesChanged()
    signal profilesChanged()
    signal errorOccurred(string message)

    // Timer for periodic updates
    property var updateTimer: Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.updateStatus()
    }

    Component.onCompleted: {
        updateStatus()
    }

    // Update the status from tailscale
    function updateStatus() {
        if (isBusy) return

        isBusy = true

        // Get status
        const statusProc = Process {
            running: true
            command: ["tailscale", "status", "--json"]

            stdout: SplitParser {
                onRead: data => {
                    try {
                        const status = JSON.parse(data)
                        parseStatus(status)
                    } catch (e) {
                        console.error("Failed to parse tailscale status:", e)
                    }
                }
            }

            onExited: (code, status) => {
                if (code !== 0) {
                    running = false
                    connected = false
                }
                statusProc.destroy()
                getPrefs()
            }
        }
    }

    function parseStatus(status) {
        if (!status) return

        // Update running state
        const backendState = status.BackendState || ""
        running = backendState === "Running"
        connected = running && status.Self && status.Self.Online

        // Parse nodes
        const nodeList = []
        if (status.Peer) {
            for (const [id, peer] of Object.entries(status.Peer)) {
                const node = {
                    id: peer.ID || id,
                    name: (peer.DNSName || peer.HostName || "Unknown").split(".")[0],
                    os: peer.OS || "",
                    online: peer.Active || false,
                    exitNode: peer.ExitNode || false,
                    exitNodeOption: peer.ExitNodeOption || false,
                    ips: peer.TailscaleIPs || [],
                    tags: peer.Tags || [],
                    mullvad: (peer.Tags || []).includes("tag:mullvad-exit-node")
                }
                nodeList.push(node)
            }
        }

        // Sort nodes: exit node first, then online, then by name
        nodeList.sort((a, b) => {
            if (a.exitNode !== b.exitNode) return b.exitNode ? 1 : -1
            if (a.online !== b.online) return b.online ? 1 : -1
            if (a.exitNodeOption !== b.exitNodeOption) return b.exitNodeOption ? 1 : -1
            return a.name.localeCompare(b.name)
        })

        nodes = nodeList
        nodesChanged()

        // Find exit node
        const exitNode = nodeList.find(n => n.exitNode)
        if (exitNode) {
            exitNodeName = exitNode.name
            exitNodeId = exitNode.id
        } else {
            exitNodeName = ""
            exitNodeId = ""
        }

        statusChanged()
    }

    function getPrefs() {
        const prefsProc = Process {
            running: true
            command: ["sh", "-c", "tailscale status --json | jq -r '.Self.PrefsView // {}'"]

            stdout: SplitParser {
                onRead: data => {
                    try {
                        const prefs = JSON.parse(data)
                        parsePrefs(prefs)
                    } catch (e) {
                        console.error("Failed to parse tailscale prefs:", e)
                    }
                }
            }

            onExited: (code, status) => {
                prefsProc.destroy()
                isBusy = false
            }
        }
    }

    function parsePrefs(prefs) {
        if (!prefs) return

        acceptDns = prefs.CorpDNS || false
        acceptRoutes = prefs.RouteAll || false
        allowLanAccess = prefs.ExitNodeAllowLANAccess || false
        shieldsUp = prefs.ShieldsUp || false
        runSsh = prefs.RunSSH || false

        statusChanged()
    }

    // Toggle running state
    function toggleRunning() {
        if (isBusy) return

        isBusy = true
        const cmd = running ? "down" : "up"

        const proc = Process {
            running: true
            command: ["tailscale", cmd]

            onExited: (code, status) => {
                proc.destroy()
                Qt.callLater(() => {
                    isBusy = false
                    updateStatus()
                })
            }
        }
    }

    // Set exit node
    function setExitNode(nodeId) {
        if (isBusy) return

        isBusy = true
        const args = nodeId ? ["--exit-node=" + nodeId] : ["--exit-node="]

        const proc = Process {
            running: true
            command: ["tailscale", "set"].concat(args)

            onExited: (code, status) => {
                proc.destroy()
                Qt.callLater(() => {
                    isBusy = false
                    updateStatus()
                })
            }
        }
    }

    // Toggle setting
    function setSetting(key, value) {
        if (isBusy) return

        isBusy = true

        const settingMap = {
            "acceptDns": "--accept-dns",
            "acceptRoutes": "--accept-routes",
            "allowLanAccess": "--exit-node-allow-lan-access",
            "shieldsUp": "--shields-up",
            "runSsh": "--ssh"
        }

        const flag = settingMap[key]
        if (!flag) {
            isBusy = false
            return
        }

        const args = [flag + "=" + (value ? "true" : "false")]

        const proc = Process {
            running: true
            command: ["tailscale", "set"].concat(args)

            onExited: (code, status) => {
                proc.destroy()
                Qt.callLater(() => {
                    isBusy = false
                    updateStatus()
                })
            }
        }
    }

    // Disconnect (unset exit node)
    function disconnectExitNode() {
        setExitNode("")
    }
}
