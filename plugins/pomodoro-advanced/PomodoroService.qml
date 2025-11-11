import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // Status properties
    property bool running: false
    property string phase: "stopped" // work, break, paused, stopped
    property string status: "stopped"
    property string icon: "⏱️"
    property string timeDisplay: "--:--"
    property int minutes: 0
    property int seconds: 0
    property int percentage: 0
    property int totalSeconds: 0
    property int workTime: 25
    property int breakTime: 5
    property bool isBusy: false

    // Signals
    signal statusChanged()
    signal timerCompleted()
    signal errorOccurred(string message)

    // Path to the pomo script
    readonly property string pomoScriptPath: Qt.resolvedUrl("./pomo").toString().replace("file://", "")

    // Timer for periodic updates
    property var updateTimer: Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.updateStatus()
    }

    Component.onCompleted: {
        updateStatus()
    }

    // Update status from pomo script
    function updateStatus() {
        if (isBusy) return

        const statusProc = Process {
            running: true
            command: [pomoScriptPath, "json"]

            stdout: SplitParser {
                onRead: data => {
                    try {
                        const status = JSON.parse(data)
                        parseStatus(status)
                    } catch (e) {
                        console.error("Failed to parse pomodoro status:", e, data)
                    }
                }
            }

            stderr: SplitParser {
                onRead: data => {
                    console.error("Pomodoro script error:", data)
                }
            }

            onExited: (code, status) => {
                statusProc.destroy()
            }
        }
    }

    function parseStatus(status) {
        if (!status) return

        const wasRunning = running
        const wasPhase = phase

        running = status.running || false
        phase = status.phase || "stopped"
        root.status = status.status || "stopped"
        icon = status.icon || "⏱️"
        timeDisplay = status.time || "--:--"
        minutes = status.minutes || 0
        seconds = status.seconds || 0
        percentage = status.percentage || 0
        totalSeconds = status.totalSeconds || 0
        workTime = status.workTime || 25
        breakTime = status.breakTime || 5

        // Detect phase transitions
        if (wasRunning && running && wasPhase !== phase && phase !== "stopped") {
            timerCompleted()
        }

        statusChanged()
    }

    // Start pomodoro
    function start() {
        if (isBusy) return

        isBusy = true
        executeCommand("start", () => {
            isBusy = false
            updateStatus()
        })
    }

    // Stop pomodoro
    function stop() {
        if (isBusy) return

        isBusy = true
        executeCommand("stop", () => {
            isBusy = false
            updateStatus()
        })
    }

    // Pause/Resume pomodoro
    function togglePause() {
        if (isBusy || !running) return

        isBusy = true
        executeCommand("pause", () => {
            isBusy = false
            updateStatus()
        })
    }

    // Restart pomodoro
    function restart() {
        if (isBusy) return

        isBusy = true
        executeCommand("restart", () => {
            isBusy = false
            updateStatus()
        })
    }

    // Execute a pomo command
    function executeCommand(cmd, callback) {
        const proc = Process {
            running: true
            command: [pomoScriptPath, cmd]

            stderr: SplitParser {
                onRead: data => {
                    console.error("Pomodoro command error:", data)
                }
            }

            onExited: (code, status) => {
                proc.destroy()
                if (callback) {
                    Qt.callLater(callback)
                }
            }
        }
    }

    // Get display text for current state
    function getDisplayText() {
        if (!running) return "Start Pomodoro"
        if (status === "paused") return "Paused"
        if (phase === "work") return "Focus Time"
        if (phase === "break") return "Break Time"
        return timeDisplay
    }

    // Get CSS class for current state
    function getCssClass() {
        if (!running) return "stopped"
        if (status === "paused") return "paused"
        if (phase === "work") return "work"
        if (phase === "break") return "break"
        return "stopped"
    }
}
