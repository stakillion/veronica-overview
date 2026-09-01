import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.pipewire as PipeWire
import org.kde.ksvg as KSvg
import org.kde.plasma.workspace.dbus as DBus
import org.kde.taskmanager as TaskManager

FocusScope {
    id: root

    property bool isOverviewOpen: false
    property var lastActiveWinId: null

    property bool showWorkspaceStrip: Plasmoid.configuration.showWorkspaceStrip !== false
    property int cardRadius: Plasmoid.configuration.cardBorderRadius !== undefined ? Plasmoid.configuration.cardBorderRadius : 14

    signal requestClose()

    focus: true

    onIsOverviewOpenChanged: {
        if (isOverviewOpen) {
            openOverview();
        } else {
            if (searchBar) searchBar.text = "";
        }
    }

    function openOverview() {
        if (searchBar) {
            searchBar.text = "";
            searchBar.searchField.focus = false;
        }
        root.forceActiveFocus();
        if (windowGrid) {
            windowGrid.resetTracking();
            windowGrid.updateDefaultSelection();
        }
    }

    function dismissOverview() {
        if (searchBar) searchBar.text = "";
        root.requestClose();
    }

    property int accumulatedDelta: 0
    property bool scrollCooldown: false

    TaskManager.VirtualDesktopInfo {
        id: desktopInfo
    }

    Timer {
        id: scrollCooldownTimer
        interval: 220
        repeat: false
        onTriggered: root.scrollCooldown = false
    }

    function switchToPreviousDesktop() {
        if (searchResults && searchResults.visible) return;
        if (root.scrollCooldown) return;

        const ids = desktopInfo.desktopIds;
        if (!ids || ids.length <= 1) return;

        const currentId = desktopInfo.currentDesktop;
        let currentIndex = -1;
        for (let i = 0; i < ids.length; i++) {
            if (ids[i] === currentId) {
                currentIndex = i;
                break;
            }
        }
        if (currentIndex > 0) {
            const targetIdx = currentIndex - 1;
            root.scrollCooldown = true;
            scrollCooldownTimer.restart();
            root.switchToDesktop(ids[targetIdx], targetIdx);
        }
    }

    function switchToNextDesktop() {
        if (searchResults && searchResults.visible) return;
        if (root.scrollCooldown) return;

        const ids = desktopInfo.desktopIds;
        if (!ids || ids.length <= 1) return;

        const currentId = desktopInfo.currentDesktop;
        let currentIndex = -1;
        for (let i = 0; i < ids.length; i++) {
            if (ids[i] === currentId) {
                currentIndex = i;
                break;
            }
        }
        if (currentIndex >= 0 && currentIndex < ids.length - 1) {
            const targetIdx = currentIndex + 1;
            root.scrollCooldown = true;
            scrollCooldownTimer.restart();
            root.switchToDesktop(ids[targetIdx], targetIdx);
        }
    }

    function handleScroll(deltaY) {
        if (searchResults && searchResults.visible) return;
        if (root.scrollCooldown) return;

        root.accumulatedDelta += deltaY;
        const threshold = 80;

        if (root.accumulatedDelta >= threshold) {
            root.accumulatedDelta = 0;
            root.switchToPreviousDesktop();
        } else if (root.accumulatedDelta <= -threshold) {
            root.accumulatedDelta = 0;
            root.switchToNextDesktop();
        }
    }

    function switchToDesktop(desktopId, index) {
        DBus.SessionBus.asyncCall({
            service: "org.kde.KWin",
            path: "/VirtualDesktopManager",
            iface: "org.freedesktop.DBus.Properties",
            member: "Set",
            arguments: ["org.kde.KWin.VirtualDesktopManager", "current", desktopId]
        });

        DBus.SessionBus.asyncCall({
            service: "org.kde.KWin",
            path: "/KWin",
            iface: "org.kde.KWin",
            member: "setCurrentDesktop",
            arguments: [index + 1]
        });
    }

    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: !searchResults || !searchResults.visible
        onWheel: event => {
            root.handleScroll(event.angleDelta.y);
        }
    }

    // Top-level transparent dismiss area covering whole screen
    MouseArea {
        id: backdropArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.ArrowCursor
        onClicked: mouse => {
            root.dismissOverview();
        }
        onWheel: wheel => {
            if (!searchResults || !searchResults.visible) {
                root.handleScroll(wheel.angleDelta.y);
            }
        }
        z: -1
    }

    readonly property real topPanelMargin: {
        if (Plasmoid.location === PlasmaCore.Types.TopEdge) {
            return 56;
        }
        return Kirigami.Units.largeSpacing;
    }

    // Top Header Container (Workspaces and Search Bar)
    ColumnLayout {
        id: topHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.topPanelMargin
        anchors.leftMargin: Kirigami.Units.largeSpacing
        anchors.rightMargin: Kirigami.Units.largeSpacing
        anchors.bottomMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.mediumSpacing
        z: 10

        // 1. Top Workspace Strip (Virtual Desktops Pager) - Centered and ALWAYS visible
        WorkspaceStrip {
            id: workspaceStrip
            visible: root.showWorkspaceStrip
            Layout.fillWidth: true

            onCurrentDesktopClicked: root.dismissOverview()
        }

        // 2. GNOME Search Bar - Horizontally centered and remains in place
        SearchBar {
            id: searchBar
            Layout.alignment: Qt.AlignHCenter

            onSearchFieldFocused: {
                windowGrid.clearSelection();
            }
            onAccepted: {
                if (searchResults.visible) {
                    searchResults.activateCurrent();
                }
            }
            onMoveSelectionDown: {
                if (searchBar.text.length > 0) {
                    if (searchResults.visible) {
                        searchResults.selectNext();
                    }
                } else {
                    searchBar.searchField.focus = false;
                    root.forceActiveFocus();
                    windowGrid.updateDefaultSelection();
                }
            }
            onMoveSelectionUp: {
                if (searchResults.visible) {
                    searchResults.selectPrevious();
                }
            }
            onEscapePressed: {
                if (searchBar.text.length > 0) {
                    searchBar.text = "";
                    searchBar.searchField.focus = false;
                    root.forceActiveFocus();
                    windowGrid.updateDefaultSelection();
                } else {
                    root.dismissOverview();
                }
            }
        }
    }

    // Window Grid (Exposé) - Positioned strictly BELOW topHeader with clip to NEVER overlap
    WindowGrid {
        id: windowGrid
        overviewOpen: root.isOverviewOpen
        lastActiveWinId: root.lastActiveWinId
        anchors.top: topHeader.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Kirigami.Units.largeSpacing
        anchors.bottomMargin: (Plasmoid.configuration.hasBottomPanel) ? 56 : Kirigami.Units.largeSpacing
        visible: searchBar.text.length === 0
        cardRadius: root.cardRadius
        showCloseButtons: Plasmoid.configuration.showCloseButtons !== undefined ? Plasmoid.configuration.showCloseButtons : true
        filterOnlyCurrentDesktop: Plasmoid.configuration.filterOnlyCurrentDesktop !== undefined ? Plasmoid.configuration.filterOnlyCurrentDesktop : true
        clip: true
        z: 1

        onWindowActivated: root.dismissOverview()
        onEmptyAreaClicked: root.dismissOverview()

        onWindowDragStarted: (pageIdx, taskRow, winIds, title, iconSource, appName, cardW, cardH, ox, oy, gx, gy) => {
            dragOverlay.sourcePageIndex = pageIdx;
            dragOverlay.sourceTaskRow = taskRow;
            dragOverlay.sourceWinIds = winIds;
            dragOverlay.cardTitle = title;
            dragOverlay.cardIcon = iconSource;

            const targetScale = 0.50;
            dragOverlay.cardWidth = Math.max(100, Math.round(cardW * targetScale));
            dragOverlay.cardHeight = Math.max(70, Math.round(cardH * targetScale));

            dragOverlay.grabOffsetX = dragOverlay.cardWidth / 2;
            dragOverlay.grabOffsetY = dragOverlay.cardHeight / 2;

            dragOverlay.startGlobalX = ox + (cardW - dragOverlay.cardWidth) / 2;
            dragOverlay.startGlobalY = oy + (cardH - dragOverlay.cardHeight) / 2;

            dragOverlay.currentGlobalX = gx - dragOverlay.grabOffsetX;
            dragOverlay.currentGlobalY = gy - dragOverlay.grabOffsetY;

            dragOverlay.opacity = 1.0;
            dragOverlay.isDragging = true;
            snapBackAnim.stop();
        }
        onWindowDragMoved: (gx, gy) => {
            if (!dragOverlay.isDragging) return;
            dragOverlay.currentGlobalX = gx - dragOverlay.grabOffsetX;
            dragOverlay.currentGlobalY = gy - dragOverlay.grabOffsetY;

            const target = workspaceStrip.getDesktopAt(gx, gy);
            workspaceStrip.highlightedDesktopId = target ? target.desktopId : "";
        }
        onWindowDragEnded: (gx, gy) => {
            if (!dragOverlay.isDragging) return;

            const target = workspaceStrip.getDesktopAt(gx, gy);
            workspaceStrip.highlightedDesktopId = "";

            if (target && target.desktopId !== undefined) {
                windowGrid.moveTaskToDesktop(dragOverlay.sourcePageIndex, dragOverlay.sourceTaskRow, target.desktopId);
                dragOverlay.isDragging = false;
                dragOverlay.opacity = 0;
            } else {
                snapBackAnim.restart();
            }
        }
        onWindowDragCanceled: {
            if (dragOverlay.isDragging) {
                snapBackAnim.restart();
            }
        }
    }

    // Search Results View (placed just under search bar, horizontally centered)
    SearchResults {
        id: searchResults
        anchors.top: topHeader.bottom
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width * 0.75, 750)
        height: Math.min(parent.height - topHeader.height - 40, 520)
        visible: searchBar.text.length > 0
        query: searchBar.text
        z: 20
        onItemActivated: {
            Qt.callLater(() => {
                root.dismissOverview();
            });
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_PageUp) {
            root.switchToPreviousDesktop();
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_PageDown) {
            root.switchToNextDesktop();
            event.accepted = true;
            return;
        }

        if (searchBar.searchField.activeFocus) {
            if (event.key === Qt.Key_Escape) {
                searchBar.text = "";
                searchBar.searchField.focus = false;
                root.forceActiveFocus();
                windowGrid.updateDefaultSelection();
                event.accepted = true;
            }
            return;
        }

        // --- Window Card Mode ---
        if (event.key === Qt.Key_Escape) {
            root.dismissOverview();
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Left) {
            windowGrid.navigateSelection(-1, 0);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Right) {
            windowGrid.navigateSelection(1, 0);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Up) {
            const res = windowGrid.navigateSelection(0, -1);
            if (res === "above_top") {
                windowGrid.clearSelection();
                searchBar.forceFocus();
            }
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Down) {
            windowGrid.navigateSelection(0, 1);
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            windowGrid.activateSelected();
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Backspace) {
            event.accepted = true;
            return;
        }

        // Printable text typed anywhere routes to search box and selects it
        if (event.text && event.text.length > 0 && event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab) {
            windowGrid.clearSelection();
            searchBar.forceFocus();
            searchBar.text += event.text;
            event.accepted = true;
            return;
        }
    }

    // Floating drag card overlay styled identically to real WindowItem cards
    Item {
        id: dragOverlay
        z: 9999
        visible: opacity > 0

        property bool isDragging: false
        property var sourcePageIndex: null
        property var sourceTaskRow: null
        property var sourceWinIds: []
        property string cardTitle: ""
        property var cardIcon: null
        property real cardWidth: 220
        property real cardHeight: 140
        property real grabOffsetX: 0
        property real grabOffsetY: 0
        property real startGlobalX: 0
        property real startGlobalY: 0
        property real currentGlobalX: 0
        property real currentGlobalY: 0

        readonly property string dragWinUuid: {
            if (!sourceWinIds) return "";
            try {
                if (Array.isArray(sourceWinIds) && sourceWinIds.length > 0) return String(sourceWinIds[0]);
                if (typeof sourceWinIds === "string") return sourceWinIds;
            } catch(e) {}
            return "";
        }

        readonly property int dragNumericWinId: {
            if (!sourceWinIds) return 0;
            try {
                if (typeof sourceWinIds === "number") return sourceWinIds;
                if (Array.isArray(sourceWinIds) && sourceWinIds.length > 0) return Number(sourceWinIds[0]) || 0;
                return Number(sourceWinIds) || 0;
            } catch(e) {}
            return 0;
        }

        readonly property bool isWayland: {
            if (dragNumericWinId > 0 && String(dragWinUuid).indexOf("-") < 0) return false;
            return true;
        }

        x: currentGlobalX
        y: currentGlobalY
        width: cardWidth
        height: cardHeight
        opacity: 0

        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        ParallelAnimation {
            id: snapBackAnim
            NumberAnimation {
                target: dragOverlay
                property: "currentGlobalX"
                to: dragOverlay.startGlobalX
                duration: 220
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: dragOverlay
                property: "currentGlobalY"
                to: dragOverlay.startGlobalY
                duration: 220
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: dragOverlay
                property: "opacity"
                to: 0
                duration: 220
                easing.type: Easing.OutCubic
            }
            onFinished: {
                dragOverlay.isDragging = false;
            }
        }

        // Card Container - matches WindowItem styling, borders, shadow and header
        Rectangle {
            anchors.fill: parent
            radius: Math.max(6, root.cardRadius - 2)
            color: Qt.rgba(0.24, 0.24, 0.28, 0.95)
            border.width: 2
            border.color: Kirigami.Theme.highlightColor

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 4

                // Header row
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20
                    Layout.maximumHeight: 20
                    Layout.leftMargin: 2
                    Layout.rightMargin: 2
                    spacing: 6

                    Kirigami.Icon {
                        source: dragOverlay.cardIcon || "application-x-executable"
                        implicitWidth: 16
                        implicitHeight: 16
                        Layout.alignment: Qt.AlignVCenter
                    }

                    QQC2.Label {
                        text: dragOverlay.cardTitle || i18n("Window")
                        font.bold: true
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        color: "#ffffff"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                // Window Preview Area
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Math.max(4, root.cardRadius - 4)
                    color: "#14151e"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    clip: true

                    // Center App Icon Placeholder
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        source: dragOverlay.cardIcon || "application-x-executable"
                        implicitWidth: Math.min(48, parent.height * 0.5)
                        implicitHeight: implicitWidth
                        z: 1
                    }

                    // Live Wayland screencast texture
                    PipeWire.PipeWireSourceItem {
                        anchors.fill: parent
                        z: 3
                        visible: dragOverlay.isWayland && dragOverlay.isDragging && waylandDragReq.nodeId !== 0
                        nodeId: waylandDragReq.nodeId

                        TaskManager.ScreencastingRequest {
                            id: waylandDragReq
                            uuid: (dragOverlay.isWayland && dragOverlay.isDragging && dragOverlay.dragWinUuid.length > 0) ? dragOverlay.dragWinUuid : ""
                        }
                    }

                    // X11 Thumbnail fallback
                    PlasmaCore.WindowThumbnail {
                        anchors.fill: parent
                        z: 2
                        winId: (!dragOverlay.isWayland && dragOverlay.dragNumericWinId > 0) ? dragOverlay.dragNumericWinId : 0
                        visible: !dragOverlay.isWayland && dragOverlay.dragNumericWinId > 0 && thumbnailAvailable
                    }
                }
            }
        }
    }
}
