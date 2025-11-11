import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property string pluginId: "kanban"

    // Data models for the three default columns
    ListModel { id: todoModel }
    ListModel { id: inProgressModel }
    ListModel { id: doneModel }

    // Column descriptors keep track of runtime UI state
    QtObject {
        id: todoColumn
        property string columnId: "todo"
        property string defaultTitle: "To Do"
        property string title: defaultTitle
        property bool addMode: false
        property string draftText: ""
        property var model: todoModel
    }

    QtObject {
        id: inProgressColumn
        property string columnId: "inProgress"
        property string defaultTitle: "In Progress"
        property string title: defaultTitle
        property bool addMode: false
        property string draftText: ""
        property var model: inProgressModel
    }

    QtObject {
        id: doneColumn
        property string columnId: "done"
        property string defaultTitle: "Done"
        property string title: defaultTitle
        property bool addMode: false
        property string draftText: ""
        property var model: doneModel
    }

    property list<QtObject> columns: [todoColumn, inProgressColumn, doneColumn]

    property bool boardLoaded: false
    property string summaryText: ""
    property string draggedCardId: ""
    property string dragSourceColumnId: ""

    property int totalCount: todoModel.count + inProgressModel.count + doneModel.count

    Component.onCompleted: {
        updateColumnTitles(false)
        loadBoard()
    }

    function getSetting(key, fallback) {
        const value = pluginData && pluginData[key] !== undefined ? pluginData[key] : undefined
        if (value === undefined || value === null || value === "")
            return fallback
        return value
    }

    function refreshColumnTitle(column, fallback) {
        const key = `${column.columnId}Title`
        const resolvedFallback = fallback && fallback.length ? fallback : column.defaultTitle
        column.title = getSetting(key, resolvedFallback)
    }

    function updateColumnTitles(shouldPersist) {
        const persist = shouldPersist === undefined ? true : shouldPersist
        for (const column of columns) {
            refreshColumnTitle(column, column.title || column.defaultTitle)
        }
        updateSummary()
        if (persist && boardLoaded)
            saveBoard()
    }

    function columnById(columnId) {
        for (const column of columns) {
            if (column.columnId === columnId)
                return column
        }
        return null
    }

    function defaultBoardSnapshot() {
        const snapshot = []
        for (const column of columns) {
            snapshot.push({
                id: column.columnId,
                title: column.title || column.defaultTitle,
                cards: []
            })
        }
        return snapshot
    }

    function boardSnapshot() {
        const snapshot = []
        for (const column of columns) {
            const cards = []
            for (let i = 0; i < column.model.count; ++i) {
                const entry = column.model.get(i)
                cards.push({
                    id: entry.cardId,
                    text: entry.text
                })
            }
            snapshot.push({
                id: column.columnId,
                title: column.title || column.defaultTitle,
                cards: cards
            })
        }
        return snapshot
    }

    function saveBoard() {
        if (!boardLoaded || !pluginService)
            return
        try {
            pluginService.savePluginData(pluginId, "board", JSON.stringify(boardSnapshot()))
        } catch (e) {
            console.error("Kanban: Failed to save board", e)
        }
    }

    function applyBoard(board) {
        for (const column of columns) {
            column.model.clear()
        }

        const data = Array.isArray(board) ? board : defaultBoardSnapshot()

        for (const columnData of data) {
            const column = columnById(columnData.id)
            if (!column)
                continue

            refreshColumnTitle(column, columnData.title || column.defaultTitle)

            const cards = Array.isArray(columnData.cards) ? columnData.cards : []
            for (const card of cards) {
                const text = card && card.text ? card.text.toString().trim() : ""
                if (!text.length)
                    continue
                const cardId = card.id || card.cardId || Qt.createUuid()
                column.model.append({
                    cardId: cardId,
                    text: text
                })
            }
        }

        updateSummary()
    }

    function loadBoard(shouldSave) {
        const persist = shouldSave === undefined ? true : shouldSave
        let stored = null
        if (pluginService) {
            stored = pluginService.loadPluginData(pluginId, "board", null)
        }

        let parsed = null
        if (stored) {
            try {
                parsed = typeof stored === "string" ? JSON.parse(stored) : stored
            } catch (e) {
                console.warn("Kanban: Failed to parse stored board, using defaults", e)
            }
        }

        applyBoard(parsed || defaultBoardSnapshot())
        boardLoaded = true
        if (persist)
            saveBoard()
    }

    function updateSummary() {
        summaryText = `${todoColumn.title}: ${todoModel.count} • ${inProgressColumn.title}: ${inProgressModel.count} • ${doneColumn.title}: ${doneModel.count}`
    }

    function addCard(columnId, text) {
        const column = columnById(columnId)
        if (!column)
            return
        const value = text ? text.toString().trim() : ""
        if (!value.length)
            return
        column.model.append({
            cardId: Qt.createUuid(),
            text: value
        })
        updateSummary()
        saveBoard()
    }

    function updateCard(columnId, cardId, newText) {
        const column = columnById(columnId)
        if (!column)
            return
        const value = newText ? newText.toString().trim() : ""
        if (!value.length) {
            removeCard(columnId, cardId)
            return
        }
        for (let i = 0; i < column.model.count; ++i) {
            const entry = column.model.get(i)
            if (entry.cardId === cardId) {
                column.model.set(i, {
                    cardId: cardId,
                    text: value
                })
                break
            }
        }
        updateSummary()
        saveBoard()
    }

    function removeCard(columnId, cardId) {
        const column = columnById(columnId)
        if (!column)
            return
        for (let i = 0; i < column.model.count; ++i) {
            const entry = column.model.get(i)
            if (entry.cardId === cardId) {
                column.model.remove(i)
                break
            }
        }
        updateSummary()
        saveBoard()
    }

    function moveCard(fromColumnId, toColumnId, cardId, targetIndex) {
        const fromColumn = columnById(fromColumnId)
        const toColumn = columnById(toColumnId)
        if (!fromColumn || !toColumn)
            return

        let cardData = null
        let originalIndex = -1
        for (let i = 0; i < fromColumn.model.count; ++i) {
            const entry = fromColumn.model.get(i)
            if (entry.cardId === cardId) {
                cardData = {
                    cardId: entry.cardId,
                    text: entry.text
                }
                originalIndex = i
                break
            }
        }

        if (!cardData)
            return

        fromColumn.model.remove(originalIndex)

        let insertIndex = targetIndex
        if (insertIndex === undefined || insertIndex === null || insertIndex < 0 || insertIndex > toColumn.model.count) {
            insertIndex = toColumn.model.count
        }

        if (fromColumn === toColumn && insertIndex > originalIndex)
            insertIndex -= 1

        toColumn.model.insert(insertIndex, cardData)

        updateSummary()
        saveBoard()
    }

    Connections {
        target: PluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === pluginId) {
                loadBoard(false)
                updateColumnTitles(false)
            }
        }
    }

    ccWidgetIcon: "layout-kanban"
    ccWidgetPrimaryText: "Kanban"
    ccWidgetSecondaryText: totalCount > 0 ? summaryText : "No cards yet"
    ccWidgetIsActive: totalCount > 0

    onCcWidgetToggled: {
        if (popoutService) {
            popoutService.togglePopout(0, 0, 0, "control-center", root.parentScreen, pluginId)
        }
    }

    pillClickAction: (x, y, width, section, screen) => {
        if (popoutService) {
            popoutService.togglePopout(x, y, width, section, screen, pluginId)
        }
    }

    pillRightClickAction: (x, y, width, section, screen) => {
        if (popoutService) {
            popoutService.togglePopout(x, y, width, section, screen, pluginId)
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: "layout-kanban"
                size: Theme.barIconSize(root.barThickness, -2)
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: `${todoModel.count}/${inProgressModel.count}/${doneModel.count}`
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: "layout-kanban"
                size: Theme.barIconSize(root.barThickness, -2)
                color: Theme.primary
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: `${todoModel.count}\n${inProgressModel.count}\n${doneModel.count}`
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutWidth: 960
    popoutHeight: 540

    popoutContent: Component {
        PopoutComponent {
            id: kanbanPopout

            headerText: "Kanban Board"
            detailsText: totalCount > 0 ? summaryText : "Start by adding your first card"
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                Row {
                    width: parent.width
                    spacing: Theme.spacingS
                    Repeater {
                        model: root.columns
                        delegate: Rectangle {
                            width: parent.width / Math.max(3, root.columns.length)
                            height: 56
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHigh
                            border.width: 1
                            border.color: Theme.outline

                            Column {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: 2

                                StyledText {
                                    text: modelData.title
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    text: `${modelData.model.count} cards`
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceTextMedium
                                }
                            }
                        }
                    }
                }

                Flickable {
                    id: boardFlickable
                    width: parent.width
                    height: Math.max(kanbanPopout.height - 200, 320)
                    contentWidth: columnRow.implicitWidth
                    contentHeight: columnRow.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.horizontal: ScrollBar {
                        policy: boardFlickable.contentWidth > boardFlickable.width ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                    }
                    ScrollBar.vertical: ScrollBar {
                        policy: boardFlickable.contentHeight > boardFlickable.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    }

                    Row {
                        id: columnRow
                        spacing: Theme.spacingM
                        anchors.top: parent.top
                        anchors.left: parent.left

                        Repeater {
                            model: root.columns
                            delegate: Column {
                                required property QtObject modelData
                                spacing: Theme.spacingS

                                Rectangle {
                                    id: columnBackground
                                    width: 280
                                    height: boardFlickable.height - Theme.spacingM
                                    radius: Theme.cornerRadius
                                    color: Theme.surfaceContainerHigh
                                    border.width: root.draggedCardId.length && root.dragSourceColumnId !== modelData.columnId ? 2 : 1
                                    border.color: dropArea.containsDrag ? Theme.primary : Theme.outline

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: Theme.spacingM
                                        spacing: Theme.spacingS

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.spacingS

                                            StyledText {
                                                text: modelData.title
                                                font.pixelSize: Theme.fontSizeMedium
                                                font.weight: Font.DemiBold
                                                color: Theme.surfaceText
                                                Layout.fillWidth: true
                                                wrapMode: Text.WordWrap
                                            }

                                            Rectangle {
                                                id: clearButton
                                                width: 28
                                                height: 28
                                                radius: 14
                                                color: Theme.surfaceContainerHighest
                                                visible: modelData.model.count > 0

                                                DankIcon {
                                                    anchors.centerIn: parent
                                                    name: "clear_all"
                                                    size: 16
                                                    color: Theme.surfaceTextMedium
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        modelData.model.clear()
                                                        updateSummary()
                                                        saveBoard()
                                                    }
                                                }
                                            }
                                        }

                                        ListView {
                                            id: cardList
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            spacing: Theme.spacingS
                                            clip: true
                                            model: modelData.model
                                            boundsBehavior: Flickable.StopAtBounds

                                            property QtObject columnRef: modelData

                                            delegate: Item {
                                                id: cardDelegate
                                                required property int index
                                                property string cardId: model.cardId
                                                property string columnId: cardList.columnRef.columnId
                                                width: cardList.width
                                                height: cardContent.implicitHeight

                                                Rectangle {
                                                    id: cardContent
                                                    anchors.fill: parent
                                                    radius: Theme.cornerRadius
                                                    color: Theme.surfaceContainerHighest
                                                    border.width: dragHandler.active ? 2 : 1
                                                    border.color: dragHandler.active ? Theme.primary : Theme.outline
                                                    opacity: dragHandler.active ? 0.85 : 1

                                                    Column {
                                                        anchors.fill: parent
                                                        anchors.margins: Theme.spacingS
                                                        spacing: Theme.spacingS

                                                        Item {
                                                            visible: !editor.visible
                                                            implicitHeight: contentRow.implicitHeight
                                                            width: parent.width

                                                            Row {
                                                                id: contentRow
                                                                spacing: Theme.spacingS
                                                                anchors.fill: parent

                                                                StyledText {
                                                                    text: model.text
                                                                    font.pixelSize: Theme.fontSizeSmall
                                                                    color: Theme.surfaceText
                                                                    wrapMode: Text.WordWrap
                                                                    width: parent.width - deleteButton.width - Theme.spacingS
                                                                }

                                                                Rectangle {
                                                                    id: deleteButton
                                                                    width: 28
                                                                    height: 28
                                                                    radius: 14
                                                                    color: Theme.surfaceContainerHigh

                                                                    DankIcon {
                                                                        anchors.centerIn: parent
                                                                        name: "delete"
                                                                        size: 16
                                                                        color: Theme.error
                                                                    }

                                                                    MouseArea {
                                                                        anchors.fill: parent
                                                                        hoverEnabled: true
                                                                        cursorShape: Qt.PointingHandCursor
                                                                        onClicked: removeCard(cardList.columnRef.columnId, cardDelegate.cardId)
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        FocusScope {
                                                            id: editor
                                                            visible: cardDelegateState.editing
                                                            implicitHeight: editorColumn.implicitHeight

                                                            property alias textArea: editorField

                                                            Column {
                                                                id: editorColumn
                                                                width: parent.width
                                                                spacing: Theme.spacingS

                                                                TextArea {
                                                                    id: editorField
                                                                    text: model.text
                                                                    wrapMode: TextEdit.Wrap
                                                                    placeholderText: "Update card"
                                                                    selectByMouse: true
                                                                    color: Theme.surfaceText
                                                                    background: Rectangle {
                                                                        radius: Theme.cornerRadius
                                                                        color: Theme.surface
                                                                        border.width: 1
                                                                        border.color: Theme.primary
                                                                    }
                                                                    Keys.onPressed: (event) => {
                                                                        if (event.key === Qt.Key_Return && (event.modifiers & Qt.ShiftModifier)) {
                                                                            // Allow newline
                                                                            event.accepted = false
                                                                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                                                            event.accepted = true
                                                                            cardDelegateState.commitEdit()
                                                                        } else if (event.key === Qt.Key_Escape) {
                                                                            event.accepted = true
                                                                            cardDelegateState.cancelEdit()
                                                                        }
                                                                    }
                                                                }

                                                                Row {
                                                                    spacing: Theme.spacingS

                                                                    Rectangle {
                                                                        width: 80
                                                                        height: 32
                                                                        radius: 16
                                                                        color: Theme.primary

                                                                        StyledText {
                                                                            anchors.centerIn: parent
                                                                            text: "Save"
                                                                            color: Theme.onPrimary
                                                                            font.pixelSize: Theme.fontSizeSmall
                                                                            font.weight: Font.Medium
                                                                        }

                                                                        MouseArea {
                                                                            anchors.fill: parent
                                                                            hoverEnabled: true
                                                                            cursorShape: Qt.PointingHandCursor
                                                                            onClicked: cardDelegateState.commitEdit()
                                                                        }
                                                                    }

                                                                    Rectangle {
                                                                        width: 80
                                                                        height: 32
                                                                        radius: 16
                                                                        color: Theme.surfaceContainerHigh

                                                                        StyledText {
                                                                            anchors.centerIn: parent
                                                                            text: "Cancel"
                                                                            color: Theme.surfaceText
                                                                            font.pixelSize: Theme.fontSizeSmall
                                                                        }

                                                                        MouseArea {
                                                                            anchors.fill: parent
                                                                            hoverEnabled: true
                                                                            cursorShape: Qt.PointingHandCursor
                                                                            onClicked: cardDelegateState.cancelEdit()
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    TapHandler {
                                                        acceptedButtons: Qt.LeftButton
                                                        gesturePolicy: TapHandler.DragThreshold
                                                        onDoubleTapped: {
                                                            if (!cardDelegateState.editing)
                                                                cardDelegateState.startEdit()
                                                        }
                                                    }

                                                    DragHandler {
                                                        id: dragHandler
                                                        target: null
                                                        dragThreshold: 6
                                                        onActiveChanged: {
                                                            if (active) {
                                                                root.draggedCardId = cardDelegate.cardId
                                                                root.dragSourceColumnId = cardList.columnRef.columnId
                                                                cardContent.grabToImage(function(result) {
                                                                    cardDelegate.Drag.imageSource = result.url
                                                                })
                                                            } else {
                                                                root.draggedCardId = ""
                                                                root.dragSourceColumnId = ""
                                                            }
                                                        }
                                                    }

                                                    Drag.active: dragHandler.active
                                                    Drag.source: cardDelegate
                                                    Drag.hotSpot.x: width / 2
                                                    Drag.hotSpot.y: height / 2
                                                    Drag.supportedActions: Qt.MoveAction
                                                    Drag.mimeData: {
                                                        "application/x-kanban-card": JSON.stringify({
                                                            id: cardDelegate.cardId,
                                                            from: cardList.columnRef.columnId
                                                        })
                                                    }
                                                    Drag.onDragFinished: {
                                                        root.draggedCardId = ""
                                                        root.dragSourceColumnId = ""
                                                    }
                                                }

                                                QtObject {
                                                    id: cardDelegateState
                                                    property bool editing: false

                                                    function startEdit() {
                                                        editing = true
                                                        editor.textArea.text = model.text
                                                        Qt.callLater(() => {
                                                            editor.textArea.selectAll()
                                                            editor.textArea.forceActiveFocus()
                                                        })
                                                    }

                                                    function commitEdit() {
                                                        updateCard(cardList.columnRef.columnId, cardDelegate.cardId, editor.textArea.text)
                                                        editing = false
                                                    }

                                                    function cancelEdit() {
                                                        editing = false
                                                    }
                                                }
                                            }
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                            implicitHeight: addCardArea.implicitHeight

                                            Column {
                                                id: addCardArea
                                                width: parent.width
                                                spacing: Theme.spacingS

                                                Rectangle {
                                                    id: addButton
                                                    width: parent.width
                                                    height: 36
                                                    radius: Theme.cornerRadius
                                                    color: Theme.surfaceContainerHigh
                                                    visible: !modelData.addMode
                                                    border.width: 1
                                                    border.color: Theme.outline

                                                    Row {
                                                        anchors.centerIn: parent
                                                        spacing: Theme.spacingXS

                                                        DankIcon {
                                                            name: "add"
                                                            size: 18
                                                            color: Theme.primary
                                                        }

                                                        StyledText {
                                                            text: "Add card"
                                                            color: Theme.surfaceText
                                                            font.pixelSize: Theme.fontSizeSmall
                                                            font.weight: Font.Medium
                                                        }
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            modelData.addMode = true
                                                            modelData.draftText = ""
                                                            Qt.callLater(() => addEditorField.forceActiveFocus())
                                                        }
                                                    }
                                                }

                                                FocusScope {
                                                    id: addEditor
                                                    visible: modelData.addMode
                                                    implicitHeight: addEditorColumn.implicitHeight

                                                    Column {
                                                        id: addEditorColumn
                                                        width: parent.width
                                                        spacing: Theme.spacingS

                                                        TextArea {
                                                            id: addEditorField
                                                            text: modelData.draftText
                                                            wrapMode: TextEdit.Wrap
                                                            placeholderText: `Add a card to ${modelData.title}`
                                                            selectByMouse: true
                                                            color: Theme.surfaceText
                                                            background: Rectangle {
                                                                radius: Theme.cornerRadius
                                                                color: Theme.surface
                                                                border.width: 1
                                                                border.color: Theme.primary
                                                            }
                                                            Keys.onPressed: (event) => {
                                                                if (event.key === Qt.Key_Return && (event.modifiers & Qt.ShiftModifier)) {
                                                                    event.accepted = false
                                                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                                                    event.accepted = true
                                                                    addEditorCommit()
                                                                } else if (event.key === Qt.Key_Escape) {
                                                                    event.accepted = true
                                                                    cancelAdd()
                                                                }
                                                            }
                                                        }

                                                        Row {
                                                            spacing: Theme.spacingS

                                                            Rectangle {
                                                                width: 80
                                                                height: 32
                                                                radius: 16
                                                                color: Theme.primary

                                                                StyledText {
                                                                    anchors.centerIn: parent
                                                                    text: "Add"
                                                                    color: Theme.onPrimary
                                                                    font.pixelSize: Theme.fontSizeSmall
                                                                    font.weight: Font.Medium
                                                                }

                                                                MouseArea {
                                                                    anchors.fill: parent
                                                                    hoverEnabled: true
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: addEditorCommit()
                                                                }
                                                            }

                                                            Rectangle {
                                                                width: 80
                                                                height: 32
                                                                radius: 16
                                                                color: Theme.surfaceContainerHigh

                                                                StyledText {
                                                                    anchors.centerIn: parent
                                                                    text: "Cancel"
                                                                    color: Theme.surfaceText
                                                                    font.pixelSize: Theme.fontSizeSmall
                                                                }

                                                                MouseArea {
                                                                    anchors.fill: parent
                                                                    hoverEnabled: true
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    onClicked: cancelAdd()
                                                                }
                                                            }
                                                        }
                                                    }

                                                    function addEditorCommit() {
                                                        addCard(modelData.columnId, addEditorField.text)
                                                        modelData.draftText = ""
                                                        modelData.addMode = false
                                                    }

                                                    function cancelAdd() {
                                                        modelData.addMode = false
                                                        modelData.draftText = ""
                                                    }
                                                }
                                            }
                                        }

                                        DropArea {
                                            id: dropArea
                                            anchors.fill: parent
                                            keys: ["application/x-kanban-card"]
                                            onDropped: (drop) => {
                                                const sourceItem = drop.source
                                                if (!sourceItem)
                                                    return
                                                const localY = drop.y + cardList.contentY
                                                const indexAtPos = cardList.indexAt(drop.x, localY)
                                                let insertIndex = indexAtPos
                                                if (indexAtPos === -1) {
                                                    insertIndex = modelData.model.count
                                                } else {
                                                    const item = cardList.itemAtIndex(indexAtPos)
                                                    if (item) {
                                                        const midpoint = item.y + item.height / 2
                                                        if (localY > midpoint)
                                                            insertIndex = indexAtPos + 1
                                                    }
                                                }
                                                moveCard(sourceItem.columnId, modelData.columnId, sourceItem.cardId, insertIndex)
                                                drop.acceptProposedAction()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
