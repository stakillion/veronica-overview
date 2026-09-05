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
import org.kde.milou as Milou

FocusScope {
    id: root

    property bool isOverviewOpen: false
    property var lastActiveWinId: null

    property bool showWorkspaceStrip: Plasmoid.configuration.showWorkspaceStrip !== false
    property int cardRadius: Plasmoid.configuration.cardBorderRadius !== undefined ? Plasmoid.configuration.cardBorderRadius : 14

    signal requestClose()
    signal requestDesktopSwitch(var desktopId)
    signal requestTaskMoved(var targetDesktopId)

    focus: true

    onIsOverviewOpenChanged: {
        if (isOverviewOpen) {
            openOverview();
        } else {
            if (searchBar) searchBar.text = "";
            if (carouselTrack) {
                carouselTrack.readyToAnimate = false;
            }
        }
    }

    function openOverview() {
        if (searchBar) {
            searchBar.text = "";
            searchBar.searchField.focus = false;
        }
        root.forceActiveFocus();
        if (carouselTrack) {
            carouselTrack.readyToAnimate = false;
            carouselTrack.resetTracking();
            carouselTrack.updateDefaultSelection();
            Qt.callLater(() => {
                carouselTrack.readyToAnimate = true;
            });
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

        const currentIndex = ids.indexOf(desktopInfo.currentDesktop);
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

        const currentIndex = ids.indexOf(desktopInfo.currentDesktop);
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
        root.requestDesktopSwitch(desktopId);

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

        // 1. Top Virtual Desktop Pager - Centered and ALWAYS visible
        Pager {
            id: pager
            visible: root.showWorkspaceStrip
            Layout.fillWidth: true

            onDesktopSelected: (desktopId, index) => root.switchToDesktop(desktopId, index)
            onCurrentDesktopClicked: root.dismissOverview()
        }

        // 2. GNOME Search Bar - Horizontally centered and remains in place
        SearchBar {
            id: searchBar
            Layout.alignment: Qt.AlignHCenter

            onSearchFieldFocused: {
                carouselTrack.clearSelection();
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
                    carouselTrack.updateDefaultSelection();
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
                    carouselTrack.updateDefaultSelection();
                } else {
                    root.dismissOverview();
                }
            }
        }
    }

    // Multi-page sliding workspace carousel
    Item {
        id: carouselTrack
        anchors.top: topHeader.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Kirigami.Units.largeSpacing
        anchors.bottomMargin: (Plasmoid.configuration.hasBottomPanel) ? 56 : Kirigami.Units.largeSpacing
        visible: searchBar.text.length === 0
        clip: true
        z: 1

        property int layoutRefreshTick: 0
        property bool readyToAnimate: false

        readonly property int pageCount: Math.max(1, desktopInfo.desktopIds ? desktopInfo.desktopIds.length : 1)
        readonly property int currentDesktopIndex: {
            const ids = desktopInfo.desktopIds;
            const cur = desktopInfo.currentDesktop;
            if (!ids || ids.length === 0) return 0;
            const idx = ids.indexOf(cur);
            return idx >= 0 ? idx : 0;
        }

        onCurrentDesktopIndexChanged: {
            carouselTrack.layoutRefreshTick++;
        }

        Component.onCompleted: {
            Qt.callLater(() => {
                carouselTrack.readyToAnimate = true;
            });
        }

        function resetTracking() {
            carouselTrack.layoutRefreshTick++;
        }

        function getCurrentPage() {
            if (!pageRepeater) return null;
            return pageRepeater.itemAt(carouselTrack.currentDesktopIndex);
        }

        function clearSelection() {
            const page = getCurrentPage();
            if (page && page.clearSelection) page.clearSelection();
        }

        function updateDefaultSelection() {
            const page = getCurrentPage();
            if (page && page.updateDefaultSelection) page.updateDefaultSelection();
        }

        function navigateSelection(dx, dy) {
            const page = getCurrentPage();
            if (page && page.navigateSelection) return page.navigateSelection(dx, dy);
            return "no_page";
        }

        function activateSelected() {
            const page = getCurrentPage();
            if (page && page.activateSelected) page.activateSelected();
        }

        function moveTaskToDesktop(pageIndex, taskRow, targetDesktopId) {
            if (!pageRepeater) return;
            const page = pageRepeater.itemAt(pageIndex);
            if (page && page.moveTaskToDesktop) page.moveTaskToDesktop(taskRow, targetDesktopId);
        }

        // Dismiss click area covering empty background
        MouseArea {
            id: bgClickArea
            anchors.fill: parent
            z: -1
            onClicked: root.dismissOverview()
            onWheel: wheel => {
                wheel.accepted = false;
            }
        }

        // Multi-page sliding carousel track
        Item {
            id: pagesTrack
            width: carouselTrack.width * carouselTrack.pageCount
            height: carouselTrack.height
            x: -carouselTrack.currentDesktopIndex * carouselTrack.width

            Behavior on x {
                enabled: carouselTrack.readyToAnimate
                NumberAnimation {
                    duration: Kirigami.Units.longDuration > 0 ? Math.round(Kirigami.Units.longDuration * 1.5) : 380
                    easing.type: Easing.OutCubic
                }
            }

            Repeater {
                id: pageRepeater
                model: desktopInfo.desktopIds

                delegate: WindowGrid {
                    id: pageDelegate
                    required property var modelData
                    required property int index

                    x: pageDelegate.index * carouselTrack.width
                    y: 0
                    width: carouselTrack.width
                    height: carouselTrack.height

                    desktopId: pageDelegate.modelData
                    pageIndex: pageDelegate.index
                    isCurrentPage: pageDelegate.index === carouselTrack.currentDesktopIndex
                    desktopCount: Math.max(1, desktopInfo.numberOfDesktops || (desktopInfo.desktopIds ? desktopInfo.desktopIds.length : 1))
                    desktopIds: desktopInfo.desktopIds
                    lastActiveWinId: root.lastActiveWinId

                    showCloseButtons: Plasmoid.configuration.showCloseButtons !== false
                    cardRadius: root.cardRadius
                    overviewOpen: root.isOverviewOpen
                    layoutRefreshTick: carouselTrack.layoutRefreshTick

                    onTaskActivated: root.dismissOverview()
                    onTaskClosed: {
                        carouselTrack.layoutRefreshTick++;
                    }
                    onEmptyAreaClicked: root.dismissOverview()

                    onWindowDragStarted: (pageIdx, taskRow, winIds, title, iconSource, appName, cardW, cardH, aspect, ox, oy, gx, gy) => {
                        dragOverlay.sourcePageIndex = pageIdx;
                        dragOverlay.sourceTaskRow = taskRow;
                        dragOverlay.sourceWinIds = winIds;
                        dragOverlay.cardTitle = title;
                        dragOverlay.cardIcon = iconSource;

                        // Non-preview overhead in dragOverlay:
                        // Horizontal: 6px left margin + 6px right margin = 12px
                        // Vertical: 6px top margin + 20px header + 4px spacing + 6px bottom margin = 36px
                        const nonPreviewW = 12;
                        const nonPreviewH = 36;

                        // Target preview aspect ratio matching the live window preview exactly
                        const a = (aspect && aspect > 0) ? aspect : ((cardW > 12 && cardH > 40) ? ((cardW - 12) / (cardH - 40)) : 1.6);
                        const maxPreviewW = 210;
                        const maxPreviewH = 135;

                        let pw, ph;
                        if (a >= (maxPreviewW / maxPreviewH)) {
                            pw = maxPreviewW;
                            ph = Math.round(pw / a);
                        } else {
                            ph = maxPreviewH;
                            pw = Math.round(ph * a);
                        }

                        pw = Math.max(90, pw);
                        ph = Math.max(60, ph);

                        // Card bounds = preview dimensions + overhead so previewArea matches the window aspect ratio 1:1
                        dragOverlay.cardWidth = pw + nonPreviewW;
                        dragOverlay.cardHeight = ph + nonPreviewH;

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

                        const target = pager.getDesktopAt(gx, gy);
                        pager.highlightedDesktopId = target ? target.desktopId : "";
                    }
                    onWindowDragEnded: (gx, gy) => {
                        if (!dragOverlay.isDragging) return;

                        const target = pager.getDesktopAt(gx, gy);
                        pager.highlightedDesktopId = "";

                        if (target && target.desktopId !== undefined) {
                            root.requestTaskMoved(target.desktopId);
                            carouselTrack.moveTaskToDesktop(dragOverlay.sourcePageIndex, dragOverlay.sourceTaskRow, target.desktopId);
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
            }
        }
    }

    // Search Results View (placed just under search bar, horizontally centered)
    Rectangle {
        id: searchResults
        anchors.top: topHeader.bottom
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width * 0.75, 750)
        height: Math.min(parent.height - topHeader.height - 40, 520)
        visible: searchBar.text.length > 0
        z: 20
        radius: 16
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.96)
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
        clip: true

        function activateCurrent() {
            if (resultsView.currentIndex < 0 && resultsView.count > 0) {
                resultsView.currentIndex = 0;
            }
            resultsView.runCurrentIndex();
        }

        function selectNext() {
            if (resultsView.currentIndex < resultsView.count - 1) {
                resultsView.currentIndex++;
                resultsView.positionViewAtIndex(resultsView.currentIndex, ListView.Contain);
            }
        }

        function selectPrevious() {
            if (resultsView.currentIndex > 0) {
                resultsView.currentIndex--;
                resultsView.positionViewAtIndex(resultsView.currentIndex, ListView.Contain);
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            QQC2.Label {
                text: i18n("Search Results for \"%1\"", searchBar.text)
                font.bold: true
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize + 1
                color: Kirigami.Theme.textColor
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
            }

            Milou.ResultsView {
                id: resultsView
                Layout.fillWidth: true
                Layout.fillHeight: true
                queryString: searchBar.text
                onActivated: {
                    Qt.callLater(() => {
                        root.dismissOverview();
                    });
                }
            }
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
                carouselTrack.updateDefaultSelection();
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
            carouselTrack.navigateSelection(-1, 0);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Right) {
            carouselTrack.navigateSelection(1, 0);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Up) {
            const res = carouselTrack.navigateSelection(0, -1);
            if (res === "above_top") {
                carouselTrack.clearSelection();
                searchBar.forceFocus();
            }
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Down) {
            carouselTrack.navigateSelection(0, 1);
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            carouselTrack.activateSelected();
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Backspace) {
            event.accepted = true;
            return;
        }

        // Printable text typed anywhere routes to search box and selects it
        if (event.text && event.text.length > 0 && event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab) {
            carouselTrack.clearSelection();
            searchBar.forceFocus();
            searchBar.text += event.text;
            event.accepted = true;
            return;
        }
    }

    // Floating drag card overlay styled identically to real WindowCard cards
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
        property real cardWidth: 222
        property real cardHeight: 154
        property real grabOffsetX: 0
        property real grabOffsetY: 0
        property real startGlobalX: 0
        property real startGlobalY: 0
        property real currentGlobalX: 0
        property real currentGlobalY: 0

        readonly property string dragWinUuid: {
            if (!sourceWinIds) return "";
            return Array.isArray(sourceWinIds) && sourceWinIds.length > 0 ? String(sourceWinIds[0]) : String(sourceWinIds);
        }

        readonly property int dragNumericWinId: {
            if (!sourceWinIds) return 0;
            const raw = Array.isArray(sourceWinIds) && sourceWinIds.length > 0 ? sourceWinIds[0] : sourceWinIds;
            const n = Number(raw);
            return (!isNaN(n) && n > 0) ? n : 0;
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

        // Card Container - matches WindowCard styling, borders, shadow and header
        Rectangle {
            anchors.fill: parent
            radius: Math.max(6, root.cardRadius - 2)
            color: Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.18))
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
                        color: Kirigami.Theme.textColor
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
                    color: Kirigami.Theme.alternateBackgroundColor
                    border.width: 1
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10)
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
