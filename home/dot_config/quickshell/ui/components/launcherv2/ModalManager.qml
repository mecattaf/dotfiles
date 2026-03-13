pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root
    property var _activeModal: null
    signal closeAllModalsExcept(var excludedModal)

    function openModal(modal) {
        if (_activeModal && _activeModal !== modal)
            closeAllModalsExcept(modal);
        _activeModal = modal;
    }
    function closeModal(modal) {
        if (_activeModal === modal)
            _activeModal = null;
    }
}
