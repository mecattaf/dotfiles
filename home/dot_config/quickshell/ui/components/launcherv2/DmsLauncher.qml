import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    LauncherModal {
        id: modal
    }

    function toggle() {
        modal.toggle();
    }

    IpcHandler {
        target: "launcher"
        function toggle() { root.toggle(); }
        function open() { modal.show(); }
        function close() { modal.hide(); }
    }

    IpcHandler {
        target: "spotlight"
        function toggle() { root.toggle(); }
        function open() { modal.show(); }
        function close() { modal.hide(); }
    }
}
