import QtQuick
import Tacit.Kit

DemoWindow {
    id: demo
    heading: "Controls"
    details: ({name: nameField.text, enabled: toggle.checked,
        amount: Math.round(amount.value * 100), choice: choices.current})
    Column {
        width: parent.width
        spacing: Kit.tokens.space.l
        TacitText { text: "Type, toggle, drag, then try the arrow keys."; ink: "sec" }
        Field { id: nameField; width: parent.width; label: "Example name"; hint: "Give this example a name" }
        Row {
            spacing: Kit.tokens.space.l
            Switch { id: toggle; label: "Enable example"; onToggled: checked => toggle.checked = checked }
            TacitText { text: toggle.checked ? "Example enabled" : "Example disabled" }
        }
        Slider {
            id: amount
            width: parent.width
            label: "Amount"
            value: 0.4
            word: Math.round(value * 100) + "%"
            onMoved: value => amount.value = value
        }
        Check { id: check; label: "Keep this choice"; onToggled: checked => check.checked = checked }
        Choices {
            id: choices
            width: parent.width
            label: "Preview size"
            model: ["Small", "Medium", "Large"]
            current: 1
            onPicked: index => choices.current = index
        }
    }
}
