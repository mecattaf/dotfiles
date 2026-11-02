import QtQuick
import Tacit.Kit

DemoWindow {
    id: demo
    heading: "Actions and feedback"
    property int count: 3
    property int before: 3
    property real progressValue: 0
    details: ({items: count, progress: progressValue, notice: notice.shown})
    Column {
        width: parent.width
        spacing: Kit.tokens.space.l
        TacitText { text: "Actions ask in place. Reversible actions offer Undo."; ink: "sec" }
        TacitText { text: demo.count + " sample items"; size: "section" }
        Row {
            spacing: Kit.tokens.space.l
            Slab { text: "Add item"; tone: "default"; onActivated: { demo.count++; notice.show("Added a sample item", ""); } }
            Slab {
                text: "Remove item"; enabled: demo.count > 0
                onActivated: { demo.before = demo.count; demo.count--; notice.show("Removed a sample item", "Undo"); }
            }
        }
        WordAction {
            text: "Clear sample items"
            risk: true
            confirm: "Clear all sample items?"
            onActivated: { demo.before = demo.count; demo.count = 0; notice.show("Cleared sample items", "Undo"); }
        }
        Slab { text: "Run sample progress"; tone: "default"; waiting: clock.running; onActivated: { demo.progressValue = 0; clock.start(); } }
        TacitText { text: clock.running ? "Sample job: " + Math.round(demo.progressValue * 100) + "%" : "Sample job ready" }
        Progress { width: parent.width; value: demo.progressValue; label: "Sample job progress" }
        TacitText { text: "Tab to a button, then press Enter. Ctrl+Z restores removed items."; ink: "meta" }
    }
    Notice { id: notice; onActivated: demo.count = demo.before }
    Timer {
        id: clock
        interval: 80; repeat: true
        onTriggered: {
            demo.progressValue = Math.min(1, demo.progressValue + 0.02);
            if (demo.progressValue >= 1) { stop(); notice.show("Sample job finished", ""); }
        }
    }
    Shortcut { sequence: "Ctrl+Z"; onActivated: { demo.count = demo.before; notice.hide(); } }
}
