import QtQuick
import Tacit.Kit

DemoWindow {
    id: demo
    heading: "Tabs, menus and panels"
    details: ({tab: tabs.current, selection: select.current, panel: panel.open, lastAction: status.text})
    Column {
        width: parent.width - panel.width
        spacing: Kit.tokens.space.l
        Tabs { id: tabs; labels: ["Overview", "Details", "History"]; onPicked: index => tabs.current = index }
        TacitText { text: ["Overview of a sample item", "Details for the sample item", "History of the sample item"][tabs.current]; size: "section"; width: parent.width; wrapMode: Text.WordWrap }
        Select {
            id: select
            label: "Sort order"
            options: ["Name", "Newest first", "Oldest first", "Size", "Type", "Recently opened", "Recently edited"]
            current: 0
            onPicked: index => select.current = index
        }
        MenuButton {
            text: "Item actions"
            items: [{label: "Open sample"}, {label: "Duplicate sample"}, {label: "Rename sample"}]
            onPicked: index => status.text = ["Opened sample", "Duplicated sample", "Rename selected"][index]
        }
        Slab { text: panel.open ? "Hide details" : "Show details"; tone: "default"; onActivated: panel.open = !panel.open }
        TacitText { id: status; text: "Try Tab, arrow keys, Enter, and Escape in the menu."; ink: "meta"; width: parent.width; wrapMode: Text.WordWrap }
    }
    DockedPanel {
        id: panel
        anchors.right: parent.right
        height: parent.height
        openWidth: Kit.tokens.width.panel
        label: "Sample details"
        Keys.onEscapePressed: open = false
        Column {
            x: Kit.tokens.space.l; y: Kit.tokens.space.l
            width: Kit.tokens.width.panel - Kit.tokens.space.l * 2
            spacing: Kit.tokens.space.l
            TacitText { text: "Sample details"; size: "section" }
            TacitText { text: "The panel grows from the page edge."; ink: "sec"; width: parent.width; wrapMode: Text.WordWrap }
            Field { width: parent.width; label: "Sample label"; hint: "Edit the sample label" }
            Slab { text: "Close details"; onActivated: panel.open = false }
        }
    }
}
