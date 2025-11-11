import QtQuick
import QtQuick.Layouts
import qs.Services
import "./layouts.js" as Layouts

Item {
    id: root

    property var pluginService: null
    property var layouts: Layouts.byName
    property string activeLayoutName: {
        if (pluginService) {
            const saved = pluginService.loadPluginData("onscreenkeyboard", "layout", Layouts.defaultLayout)
            return layouts.hasOwnProperty(saved) ? saved : Layouts.defaultLayout
        }
        return Layouts.defaultLayout
    }
    property var currentLayout: layouts[activeLayoutName]

    implicitWidth: keyRows.implicitWidth
    implicitHeight: keyRows.implicitHeight

    ColumnLayout {
        id: keyRows
        anchors.fill: parent
        spacing: 5

        Repeater {
            model: root.currentLayout.keys

            delegate: RowLayout {
                id: keyRow
                required property var modelData
                spacing: 5

                Repeater {
                    model: modelData

                    delegate: OskKey {
                        required property var modelData
                        keyData: modelData
                    }
                }
            }
        }
    }
}
