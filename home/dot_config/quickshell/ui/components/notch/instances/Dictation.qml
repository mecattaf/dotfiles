import QtQuick
import Quickshell
import qs.config
import qs.ui.controls.auxiliary.notch
import qs.ui.controls.primitives
import QtQuick.VectorImage
import QtQuick.Effects

NotchApplication {
    details.version: "Elephant-1"
    details.appType: "indicator"
    noMode: true

    indicative: Item {
        CFVI {
            anchors {
                left: parent.left
                leftMargin: 10
                verticalCenter: parent.verticalCenter
            }
            icon: "mic.svg"
            size: 18
            color: "#4ade80"
        }
    }
}
