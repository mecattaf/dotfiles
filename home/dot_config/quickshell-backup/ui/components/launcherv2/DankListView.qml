import QtQuick
import QtQuick.Controls
import "ScrollConstants.js" as Scroll

ListView {
    id: listView
    property real scrollBarTopMargin: 0
    property real mouseWheelSpeed: Scroll.mouseWheelSpeed

    flickDeceleration: Scroll.flickDeceleration
    maximumFlickVelocity: Scroll.maximumFlickVelocity
    boundsBehavior: Flickable.StopAtBounds
    boundsMovement: Flickable.FollowBoundsBehavior
    pressDelay: 0
    flickableDirection: Flickable.VerticalFlick

    add: null
    remove: null
    displaced: null
    move: null

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            var delta = event.angleDelta.y;
            var scrollAmount = (delta > 0 ? -1 : 1) * listView.mouseWheelSpeed;
            var newY = listView.contentY + scrollAmount;
            var maxY = Math.max(0, listView.contentHeight - listView.height + listView.originY);
            newY = Math.max(listView.originY, Math.min(maxY, newY));
            listView.contentY = newY;
            event.accepted = true;
        }
    }

    ScrollBar.vertical: DankScrollbar {
        id: vbar
        topPadding: listView.scrollBarTopMargin
    }
}
