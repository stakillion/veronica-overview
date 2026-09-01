import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.pipewire as PipeWire
import org.kde.taskmanager as TaskManager

Rectangle {
    id: root

    required property var targetModelIndex
    required property string windowTitle
    required property var windowIcon
    required property string appLabel
    required property bool isActive
    required property var winIds
    property var windowGeometry: null
    property int itemIndex: 0
    property bool overviewOpen: false
    property bool isMinimized: false

    property bool showTitle: true
    property bool showCloseButton: true
    property int itemRadius: 14
    property bool isBeingDragged: false

    signal activated()
    signal closed()
    signal aspectDiscovered(real aspect)
    signal dragStarted(real itemGlobalX, real itemGlobalY, real grabX, real grabY)
    signal dragMoved(real globalX, real globalY)
    signal dragEnded(real globalX, real globalY)
    signal dragCanceled()

    // Card title displays the specific window title, falling back to application title
    readonly property string cardTitle: {
        if (windowTitle && typeof windowTitle === "string" && windowTitle.trim().length > 0) {
            return windowTitle.trim();
        }
        if (appLabel && typeof appLabel === "string" && appLabel.trim().length > 0) {
            return appLabel.trim();
        }
        return i18n("Window");
    }
    readonly property var iconSource: windowIcon ? windowIcon : "application-x-executable"

    readonly property bool isWaylandWindow: {
        if (numericWinId > 0 && String(winUuid).indexOf("-") < 0) return false;
        return true;
    }

    readonly property string winUuid: {
        if (!winIds) return "";
        try {
            if (Array.isArray(winIds) && winIds.length > 0) {
                return String(winIds[0]);
            }
            if (typeof winIds === "object" && typeof winIds.length === "number" && winIds.length > 0) {
                if (winIds[0] !== undefined) return String(winIds[0]);
            }
            if (typeof winIds === "string" && winIds.length > 5) {
                return winIds;
            }
            const s = String(winIds);
            if (s && s !== "[object Object]" && s !== "undefined" && s.length > 5) {
                return s;
            }
        } catch (e) {}
        return "";
    }

    readonly property int numericWinId: {
        if (!winIds) return 0;
        try {
            if (typeof winIds === "number" && !isNaN(winIds)) return winIds;
            if (Array.isArray(winIds) && winIds.length > 0) {
                const n = Number(winIds[0]);
                return (!isNaN(n) && n > 0) ? n : 0;
            }
            if (typeof winIds === "object" && typeof winIds.length === "number" && winIds.length > 0) {
                const n = Number(winIds[0]);
                return (!isNaN(n) && n > 0) ? n : 0;
            }
            const n = Number(winIds);
            return (!isNaN(n) && n > 0) ? n : 0;
        } catch (e) {}
        return 0;
    }

    radius: itemRadius
    opacity: isBeingDragged ? 0.30 : 1.0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    readonly property bool isHovered: Boolean((mouseArea && mouseArea.containsMouse) || (closeMouse && closeMouse.containsMouse))

    color: isActive ? Qt.rgba(0.24, 0.24, 0.28, 0.95) : (isHovered ? Qt.rgba(0.20, 0.20, 0.23, 0.92) : Qt.rgba(0.14, 0.14, 0.16, 0.88))
    border.width: isActive ? 2 : 0
    border.color: isActive ? "#3584e4" : "transparent"

    scale: isHovered ? 1.025 : 1.0
    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }

    readonly property bool isCompact: root.height < 110

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.isCompact ? 4 : 6
        spacing: root.isCompact ? 2 : 4

        // Header bar: App Icon & Window Title
        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            Layout.preferredHeight: root.isCompact ? 18 : 24
            Layout.maximumHeight: root.isCompact ? 18 : 24
            Layout.leftMargin: 2
            Layout.rightMargin: root.showCloseButton ? (root.isCompact ? 22 : 28) : 2
            spacing: root.isCompact ? 4 : 6

            Kirigami.Icon {
                source: root.iconSource
                implicitWidth: root.isCompact ? 14 : 18
                implicitHeight: root.isCompact ? 14 : 18
                Layout.alignment: Qt.AlignVCenter
            }

            QQC2.Label {
                text: root.cardTitle
                font.bold: true
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: "#ffffff"
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // Window Preview Canvas Area (Matches official TaskManager architecture)
        Rectangle {
            id: previewArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Math.max(4, root.itemRadius - 4)
            color: "#14151e"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            // 1. High-resolution application icon (Underneath, visible while loading or if minimized)
            Item {
                anchors.fill: parent
                z: 1

                Rectangle {
                    anchors.centerIn: parent
                    width: centerIcon.width + 24
                    height: centerIcon.height + 24
                    radius: width / 2
                    color: Qt.rgba(1, 1, 1, 0.05)
                }

                Kirigami.Icon {
                    id: centerIcon
                    anchors.centerIn: parent
                    source: root.iconSource
                    implicitWidth: Math.min(80, Math.max(36, parent.height * 0.46))
                    implicitHeight: implicitWidth
                }
            }

            // 2. X11 Window Thumbnail (Fallback for X11 / Xwayland windows)
            PlasmaCore.WindowThumbnail {
                id: winThumbnail
                anchors.fill: parent
                z: 2
                winId: (!root.isMinimized && !root.isWaylandWindow && root.numericWinId > 0) ? root.numericWinId : 0
                visible: !root.isWaylandWindow && root.numericWinId > 0 && thumbnailAvailable
            }

            // 3. Live Wayland Window Texture (Direct TaskManager Screencast)
            PipeWire.PipeWireSourceItem {
                id: pwSource
                anchors.fill: parent
                z: 3
                visible: root.isWaylandWindow && !root.isMinimized
                opacity: root.isBeingDragged ? 0.30 : 1.0
                nodeId: waylandReq.nodeId

                readonly property real liveAspect: (streamSize && streamSize.width > 20 && streamSize.height > 20) ? (streamSize.width / streamSize.height) : 0

                onLiveAspectChanged: {
                    if (liveAspect > 0) {
                        root.aspectDiscovered(liveAspect);
                    }
                }

                TaskManager.ScreencastingRequest {
                    id: waylandReq
                    uuid: (root.isWaylandWindow && root.overviewOpen && !root.isMinimized && root.winUuid.length > 0) ? root.winUuid : ""
                }
            }
        }
    }

    // Transparent click+hover+drag overlay for the entire card (above all content)
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        anchors.margins: -2
        z: 50
        hoverEnabled: true
        cursorShape: dragInitiated ? Qt.ClosedHandCursor : (containsMouse ? Qt.PointingHandCursor : Qt.ArrowCursor)
        acceptedButtons: Qt.LeftButton

        property real pressX: 0
        property real pressY: 0
        property bool dragInitiated: false

        onPressed: mouse => {
            pressX = mouse.x;
            pressY = mouse.y;
            dragInitiated = false;
        }

        onPositionChanged: mouse => {
            if (pressed && !dragInitiated) {
                const dx = mouse.x - pressX;
                const dy = mouse.y - pressY;
                if (Math.sqrt(dx * dx + dy * dy) > 8) {
                    dragInitiated = true;
                    const globalOrigin = root.mapToItem(null, 0, 0);
                    root.dragStarted(globalOrigin.x, globalOrigin.y, pressX, pressY);
                }
            }
            if (dragInitiated) {
                const globalPos = root.mapToItem(null, mouse.x, mouse.y);
                root.dragMoved(globalPos.x, globalPos.y);
            }
        }

        onReleased: mouse => {
            if (dragInitiated) {
                dragInitiated = false;
                const globalPos = root.mapToItem(null, mouse.x, mouse.y);
                root.dragEnded(globalPos.x, globalPos.y);
            } else {
                root.activated();
            }
            root.dragCanceled(); // Ensure reset on release
        }

        onCanceled: {
            dragInitiated = false;
            root.dragCanceled();
        }

        onWheel: wheel => {
            wheel.accepted = false;
        }
    }

    // GNOME-style Close button in top-right corner of card (always visible)
    Rectangle {
        id: closeBtn
        z: 100
        visible: root.showCloseButton
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 6
        width: root.isCompact ? 18 : 22
        height: root.isCompact ? 18 : 22
        radius: width / 2
        color: closeMouse.containsMouse ? "#e01b24" : Qt.rgba(0.15, 0.15, 0.18, 0.85)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.25)
        Behavior on color { ColorAnimation { duration: 120 } }

        Kirigami.Icon {
            anchors.centerIn: parent
            source: "window-close-symbolic"
            implicitWidth: 12
            implicitHeight: 12
            color: "#ffffff"
        }

        MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                mouse.accepted = true;
                root.closed();
            }
            QQC2.ToolTip.text: i18n("Close")
            QQC2.ToolTip.visible: containsMouse
        }
    }
}
