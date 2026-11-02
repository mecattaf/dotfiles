import QtQuick
import Tacit.Kit

DemoWindow {
    id: demo
    heading: "Lists and search"
    property var names: ["Field notes.txt", "Reading list.pdf", "Walkthrough.qml", "Ideas.md", "Weekend plans.txt", "Sketches.svg"]
    property int editing: -1
    property var shown: names.filter(n => n.toLowerCase().includes(search.text.toLowerCase()))
    details: ({query: search.text, rows: shown.length, selected: list.selectionCount, lastAction: status.text})
    Column {
        anchors.fill: parent
        spacing: Kit.tokens.space.m
        TacitText { text: "Select rows; Ctrl/Shift select several. Enter opens, F2 renames."; ink: "sec" }
        SearchField { id: search; scope: "example files"; fieldWidth: demo.width - Kit.tokens.space.xl * 2; onDown: list.forceActiveFocus() }
        RowList {
            id: list
            width: parent.width
            height: Kit.tokens.height.row * 6 + Kit.tokens.space.l
            label: "Example files"
            model: demo.shown
            function nameAt(i) { return demo.shown[i] ?? ""; }
            onActivated: index => status.text = "Opened " + demo.shown[index] + " (sample only)"
            onPeeked: index => status.text = "Preview: " + demo.shown[index]
            onEditRequested: index => demo.editing = index
            delegate: ListRow {
                required property string modelData
                required property int index
                width: list.rowWidth
                name: modelData
                glyph: "description"
                focusable: false
                selected: list.isSelected(index)
                ring: list.ringAt(index)
                joinAbove: list.isSelected(index - 1)
                joinBelow: list.isSelected(index + 1)
                editing: demo.editing === index
                onClicked: modifiers => list.clickAt(index, modifiers)
                onActivated: list.activated(index)
                onRenamed: text => {
                    const copy = demo.names.slice();
                    copy[copy.indexOf(modelData)] = text;
                    demo.editing = -1;
                    demo.names = copy;
                    status.text = "Renamed sample to " + text;
                }
                onEditCancelled: demo.editing = -1
            }
        }
        TacitText { id: status; text: "These are sample names; no files are opened or changed."; ink: "meta" }
    }
}
