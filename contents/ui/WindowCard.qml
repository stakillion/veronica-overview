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
    property bool alternateCardStyle: Plasmoid.configuration.alternateCardStyle === true
    property int alternateCardIconSize: Plasmoid.configuration.alternateCardIconSize || 64
    property bool showAudioIndicator: Plasmoid.configuration.showAudioIndicator !== false
    property bool showMicIndicator: Plasmoid.configuration.showMicIndicator !== false
    property bool showCardMediaControls: Plasmoid.configuration.showCardMediaControls !== false
    property bool hasAudioStream: false
    property bool playingAudio: false
    property bool isAudioMuted: false

    property bool hasMicStream: false
    property bool recordingMic: false
    property bool isMicMuted: false

    property bool hasMediaControl: false
    property bool isMediaPlaying: false
    property bool canMediaPause: true
    property bool canMediaPlay: true
    property bool canMediaGoPrevious: false
    property bool canMediaGoNext: false

    property int itemRadius: 14
    property bool isBeingDragged: false

    signal activated()
    signal selected()
    signal closed()
    signal audioMuteToggled()
    signal micMuteToggled()
    signal mediaPreviousClicked()
    signal mediaPlayPauseClicked()
    signal mediaNextClicked()
    signal aspectDiscovered(real aspect)
    signal contextMenuRequested(real mouseX, real mouseY, var visualParent)
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
        return Array.isArray(winIds) && winIds.length > 0 ? String(winIds[0]) : String(winIds);
    }

    readonly property int numericWinId: {
        if (!winIds) return 0;
        const raw = Array.isArray(winIds) && winIds.length > 0 ? winIds[0] : winIds;
        const n = Number(raw);
        return (!isNaN(n) && n > 0) ? n : 0;
    }

    radius: itemRadius
    opacity: isBeingDragged ? 0.30 : 1.0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    readonly property bool isHovered: Boolean(
        (mouseArea && mouseArea.containsMouse) ||
        (clusterHoverHandler && clusterHoverHandler.hovered) ||
        (bottomIconHoverHandler && bottomIconHoverHandler.hovered)
    )

    color: isActive
        ? Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.18))
        : (isHovered
            ? Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(Kirigami.Theme.hoverColor.r, Kirigami.Theme.hoverColor.g, Kirigami.Theme.hoverColor.b, 0.20))
            : Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.90))
    border.width: isActive ? 2 : 1
    border.color: isActive
        ? Kirigami.Theme.highlightColor
        : (isHovered
            ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.50)
            : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15))

    scale: isHovered ? 1.025 : 1.0
    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }

    readonly property bool isCompact: root.height < 110

    // Header bar: App Icon & Window Title
    Item {
        id: headerRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.isCompact ? 4 : 6
        anchors.leftMargin: root.isCompact ? 4 : 6
        anchors.rightMargin: root.isCompact ? 4 : 6
        height: root.isCompact ? 18 : 24

        // Standard style left app icon
        Kirigami.Icon {
            id: headerAppIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            source: root.iconSource
            implicitWidth: root.isCompact ? 14 : 18
            implicitHeight: root.isCompact ? 14 : 18
            visible: !root.alternateCardStyle
        }

        // Window title
        QQC2.Label {
            id: titleLabel
            anchors.left: {
                if (root.alternateCardStyle) {
                    const leftW = (leftActionCluster.visible && leftActionCluster.width > 0) ? (leftActionCluster.width + 4) : 0;
                    const rightW = (topActionCluster.visible && topActionCluster.width > 0) ? (topActionCluster.width + 4) : 0;
                    return parent.left;
                }
                return headerAppIcon.visible ? headerAppIcon.right : parent.left;
            }
            anchors.leftMargin: {
                if (root.alternateCardStyle) {
                    const leftW = (leftActionCluster.visible && leftActionCluster.width > 0) ? (leftActionCluster.width + 4) : 0;
                    const rightW = (topActionCluster.visible && topActionCluster.width > 0) ? (topActionCluster.width + 4) : 0;
                    return Math.max(leftW, rightW);
                }
                return 6;
            }
            anchors.right: parent.right
            anchors.rightMargin: {
                if (root.alternateCardStyle) {
                    const leftW = (leftActionCluster.visible && leftActionCluster.width > 0) ? (leftActionCluster.width + 4) : 0;
                    const rightW = (topActionCluster.visible && topActionCluster.width > 0) ? (topActionCluster.width + 4) : 0;
                    return Math.max(leftW, rightW);
                }
                return (topActionCluster.visible && topActionCluster.width > 0) ? (topActionCluster.width + 4) : 0;
            }
            anchors.verticalCenter: parent.verticalCenter
            text: root.cardTitle
            font.bold: true
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            color: Kirigami.Theme.textColor
            elide: Text.ElideRight
            horizontalAlignment: root.alternateCardStyle ? Text.AlignHCenter : Text.AlignLeft
            visible: width > 24
        }
    }

    // Window Preview Canvas Area (Matches official TaskManager architecture)
    Rectangle {
        id: previewArea
        anchors.top: headerRow.bottom
        anchors.topMargin: root.isCompact ? 2 : 4
        anchors.left: parent.left
        anchors.leftMargin: root.isCompact ? 4 : 6
        anchors.right: parent.right
        anchors.rightMargin: root.isCompact ? 4 : 6
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.isCompact ? 4 : 6
        radius: Math.max(4, root.itemRadius - 4)
        color: Kirigami.Theme.alternateBackgroundColor
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10)
        clip: true

            // 1. High-resolution application icon (Underneath, visible while loading or if minimized)
            Item {
                anchors.fill: parent
                z: 1

                Rectangle {
                    anchors.centerIn: parent
                    width: centerIcon.width + 24
                    height: centerIcon.height + 24
                    radius: width / 2
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
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

    // Transparent click+hover+drag overlay for the entire card (above all content)
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        anchors.margins: -2
        z: 50
        hoverEnabled: true
        cursorShape: dragInitiated ? Qt.ClosedHandCursor : (containsMouse ? Qt.PointingHandCursor : Qt.ArrowCursor)
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        property real pressX: 0
        property real pressY: 0
        property bool dragInitiated: false

        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.selected();
                root.contextMenuRequested(mouse.x, mouse.y, mouseArea);
                return;
            }
            if (mouse.button === Qt.LeftButton) {
                pressX = mouse.x;
                pressY = mouse.y;
                dragInitiated = false;
            }
        }

        onPositionChanged: mouse => {
            if ((pressedButtons & Qt.LeftButton) && !dragInitiated) {
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
            if (mouse.button === Qt.RightButton) return;
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

    // Top-left action button cluster (when alternateCardStyle is enabled): [Media] [Audio] [Mic]
    Row {
        id: leftActionCluster
        visible: root.alternateCardStyle
        z: 100
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.isCompact ? 4 : 6
        anchors.leftMargin: root.isCompact ? 4 : 6
        spacing: 6
        layoutDirection: Qt.LeftToRight

        // 1. Media playback controls: [[Previous track] [Play/pause] [Next track]]
        Row {
            id: altMediaControlsRow
            visible: root.showCardMediaControls && root.hasMediaControl
            spacing: 3
            anchors.verticalCenter: parent.verticalCenter

            // Previous Track
            Rectangle {
                id: altPrevBtn
                width: root.isCompact ? 18 : 22
                height: root.isCompact ? 18 : 22
                radius: width / 2
                enabled: root.canMediaGoPrevious
                opacity: enabled ? 1.0 : 0.45
                color: altPrevMouse.containsMouse && enabled
                    ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                    : Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.75)
                border.width: 1
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                Behavior on color { ColorAnimation { duration: 120 } }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: "media-skip-backward"
                    implicitWidth: root.isCompact ? 10 : 12
                    implicitHeight: root.isCompact ? 10 : 12
                    color: altPrevMouse.containsMouse && altPrevBtn.enabled ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                }

                MouseArea {
                    id: altPrevMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: mouse => {
                        mouse.accepted = true;
                        root.mediaPreviousClicked();
                    }
                    QQC2.ToolTip.text: i18n("Previous Track")
                    QQC2.ToolTip.visible: containsMouse && parent.enabled
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }

            // Play / Pause
            Rectangle {
                id: altPlayPauseBtn
                width: root.isCompact ? 18 : 22
                height: root.isCompact ? 18 : 22
                radius: width / 2
                enabled: root.isMediaPlaying ? root.canMediaPause : root.canMediaPlay
                opacity: enabled ? 1.0 : 0.45
                color: altPlayPauseMouse.containsMouse && enabled
                    ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                    : Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.75)
                border.width: 1
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                Behavior on color { ColorAnimation { duration: 120 } }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: root.isMediaPlaying ? "media-playback-pause" : "media-playback-start"
                    implicitWidth: root.isCompact ? 10 : 12
                    implicitHeight: root.isCompact ? 10 : 12
                    color: altPlayPauseMouse.containsMouse && altPlayPauseBtn.enabled ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                }

                MouseArea {
                    id: altPlayPauseMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: mouse => {
                        mouse.accepted = true;
                        root.mediaPlayPauseClicked();
                    }
                    QQC2.ToolTip.text: root.isMediaPlaying ? i18n("Pause") : i18n("Play")
                    QQC2.ToolTip.visible: containsMouse && parent.enabled
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }

            // Next Track
            Rectangle {
                id: altNextBtn
                width: root.isCompact ? 18 : 22
                height: root.isCompact ? 18 : 22
                radius: width / 2
                enabled: root.canMediaGoNext
                opacity: enabled ? 1.0 : 0.45
                color: altNextMouse.containsMouse && enabled
                    ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                    : Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.75)
                border.width: 1
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                Behavior on color { ColorAnimation { duration: 120 } }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: "media-skip-forward"
                    implicitWidth: root.isCompact ? 10 : 12
                    implicitHeight: root.isCompact ? 10 : 12
                    color: altNextMouse.containsMouse && altNextBtn.enabled ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                }

                MouseArea {
                    id: altNextMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: mouse => {
                        mouse.accepted = true;
                        root.mediaNextClicked();
                    }
                    QQC2.ToolTip.text: i18n("Next Track")
                    QQC2.ToolTip.visible: containsMouse && parent.enabled
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }
        }

        // 2. Audio playing/muted indicator button: [Audio indicator]
        Rectangle {
            id: altAudioIndicatorBtn
            visible: root.showAudioIndicator && root.hasAudioStream && (root.playingAudio || root.isAudioMuted)
            anchors.verticalCenter: parent.verticalCenter
            width: root.isCompact ? 18 : 22
            height: root.isCompact ? 18 : 22
            radius: width / 2
            color: altAudioMouse.containsMouse
                ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                : Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.85)
            border.width: 1
            border.color: root.isAudioMuted
                ? Qt.rgba(Kirigami.Theme.negativeTextColor.r, Kirigami.Theme.negativeTextColor.g, Kirigami.Theme.negativeTextColor.b, 0.50)
                : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.20)
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on border.color { ColorAnimation { duration: 120 } }

            Kirigami.Icon {
                anchors.centerIn: parent
                source: root.isAudioMuted ? "audio-volume-muted" : "audio-volume-high"
                implicitWidth: root.isCompact ? 11 : 13
                implicitHeight: root.isCompact ? 11 : 13
                color: altAudioMouse.containsMouse
                    ? Kirigami.Theme.highlightColor
                    : (root.isAudioMuted ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor)
            }

            MouseArea {
                id: altAudioMouse
                anchors.fill: parent
                anchors.margins: -4
                preventStealing: true
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => mouse.accepted = true
                onClicked: mouse => {
                    mouse.accepted = true;
                    root.audioMuteToggled();
                }
                onDoubleClicked: mouse => {
                    mouse.accepted = true;
                    root.audioMuteToggled();
                }
                QQC2.ToolTip.text: root.isAudioMuted ? i18n("Unmute Playback") : i18n("Mute Playback")
                QQC2.ToolTip.visible: containsMouse
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }

        // 3. Microphone recording/muted indicator button: [Mic indicator]
        Rectangle {
            id: altMicIndicatorBtn
            visible: root.showMicIndicator && root.hasMicStream && (root.recordingMic || root.isMicMuted)
            anchors.verticalCenter: parent.verticalCenter
            width: root.isCompact ? 18 : 22
            height: root.isCompact ? 18 : 22
            radius: width / 2
            color: altMicMouse.containsMouse
                ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                : Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.85)
            border.width: 1
            border.color: root.isMicMuted
                ? Qt.rgba(Kirigami.Theme.negativeTextColor.r, Kirigami.Theme.negativeTextColor.g, Kirigami.Theme.negativeTextColor.b, 0.50)
                : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.20)
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on border.color { ColorAnimation { duration: 120 } }

            Kirigami.Icon {
                anchors.centerIn: parent
                source: root.isMicMuted ? "microphone-sensitivity-muted" : "microphone-sensitivity-high"
                implicitWidth: root.isCompact ? 11 : 13
                implicitHeight: root.isCompact ? 11 : 13
                color: altMicMouse.containsMouse
                    ? Kirigami.Theme.highlightColor
                    : (root.isMicMuted ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor)
            }

            MouseArea {
                id: altMicMouse
                anchors.fill: parent
                anchors.margins: -4
                preventStealing: true
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => mouse.accepted = true
                onClicked: mouse => {
                    mouse.accepted = true;
                    root.micMuteToggled();
                }
                onDoubleClicked: mouse => {
                    mouse.accepted = true;
                    root.micMuteToggled();
                }
                QQC2.ToolTip.text: root.isMicMuted ? i18n("Unmute Microphone") : i18n("Mute Microphone")
                QQC2.ToolTip.visible: containsMouse
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
    }

    // Top-right action button cluster:
    // When standard style: [Mic] [Audio] [Media] [Close]
    // When alternate style: [Close]
    Row {
        id: topActionCluster
        z: 100
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: root.isCompact ? 4 : 6
        anchors.rightMargin: root.isCompact ? 4 : 6
        spacing: 6
        layoutDirection: Qt.LeftToRight

        HoverHandler {
            id: clusterHoverHandler
        }

        // 1. Microphone recording/muted indicator button: [Mic indicator] (standard style only)
        Rectangle {
            id: micIndicatorBtn
            visible: !root.alternateCardStyle && root.showMicIndicator && root.hasMicStream && (root.recordingMic || root.isMicMuted)
            anchors.verticalCenter: parent.verticalCenter
            width: root.isCompact ? 18 : 22
            height: root.isCompact ? 18 : 22
            radius: width / 2
            color: micMouse.containsMouse
                ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                : Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.85)
            border.width: 1
            border.color: root.isMicMuted
                ? Qt.rgba(Kirigami.Theme.negativeTextColor.r, Kirigami.Theme.negativeTextColor.g, Kirigami.Theme.negativeTextColor.b, 0.50)
                : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.20)
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on border.color { ColorAnimation { duration: 120 } }

            Kirigami.Icon {
                anchors.centerIn: parent
                source: root.isMicMuted ? "microphone-sensitivity-muted" : "microphone-sensitivity-high"
                implicitWidth: root.isCompact ? 11 : 13
                implicitHeight: root.isCompact ? 11 : 13
                color: micMouse.containsMouse
                    ? Kirigami.Theme.highlightColor
                    : (root.isMicMuted ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor)
            }

            MouseArea {
                id: micMouse
                anchors.fill: parent
                anchors.margins: -4
                preventStealing: true
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => mouse.accepted = true
                onClicked: mouse => {
                    mouse.accepted = true;
                    root.micMuteToggled();
                }
                onDoubleClicked: mouse => {
                    mouse.accepted = true;
                    root.micMuteToggled();
                }
                QQC2.ToolTip.text: root.isMicMuted ? i18n("Unmute Microphone") : i18n("Mute Microphone")
                QQC2.ToolTip.visible: containsMouse
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }

        // 2. Audio playing/muted indicator button: [Audio indicator] (standard style only)
        Rectangle {
            id: audioIndicatorBtn
            visible: !root.alternateCardStyle && root.showAudioIndicator && root.hasAudioStream && (root.playingAudio || root.isAudioMuted)
            anchors.verticalCenter: parent.verticalCenter
            width: root.isCompact ? 18 : 22
            height: root.isCompact ? 18 : 22
            radius: width / 2
            color: audioMouse.containsMouse
                ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                : Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.85)
            border.width: 1
            border.color: root.isAudioMuted
                ? Qt.rgba(Kirigami.Theme.negativeTextColor.r, Kirigami.Theme.negativeTextColor.g, Kirigami.Theme.negativeTextColor.b, 0.50)
                : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.20)
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on border.color { ColorAnimation { duration: 120 } }

            Kirigami.Icon {
                anchors.centerIn: parent
                source: root.isAudioMuted ? "audio-volume-muted" : "audio-volume-high"
                implicitWidth: root.isCompact ? 11 : 13
                implicitHeight: root.isCompact ? 11 : 13
                color: audioMouse.containsMouse
                    ? Kirigami.Theme.highlightColor
                    : (root.isAudioMuted ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor)
            }

            MouseArea {
                id: audioMouse
                anchors.fill: parent
                anchors.margins: -4
                preventStealing: true
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => mouse.accepted = true
                onClicked: mouse => {
                    mouse.accepted = true;
                    root.audioMuteToggled();
                }
                onDoubleClicked: mouse => {
                    mouse.accepted = true;
                    root.audioMuteToggled();
                }
                QQC2.ToolTip.text: root.isAudioMuted ? i18n("Unmute Playback") : i18n("Mute Playback")
                QQC2.ToolTip.visible: containsMouse
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }

        // 3. Media playback controls: [[Previous track] [Play/pause] [Next track]] (standard style only)
        Row {
            id: mediaControlsRow
            visible: !root.alternateCardStyle && root.showCardMediaControls && root.hasMediaControl
            spacing: 3
            anchors.verticalCenter: parent.verticalCenter

            // Previous Track
            Rectangle {
                id: prevBtn
                width: root.isCompact ? 18 : 22
                height: root.isCompact ? 18 : 22
                radius: width / 2
                enabled: root.canMediaGoPrevious
                opacity: enabled ? 1.0 : 0.45
                color: prevMouse.containsMouse && enabled
                    ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                    : Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.75)
                border.width: 1
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                Behavior on color { ColorAnimation { duration: 120 } }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: "media-skip-backward"
                    implicitWidth: root.isCompact ? 10 : 12
                    implicitHeight: root.isCompact ? 10 : 12
                    color: prevMouse.containsMouse && prevBtn.enabled ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                }

                MouseArea {
                    id: prevMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: mouse => {
                        mouse.accepted = true;
                        root.mediaPreviousClicked();
                    }
                    QQC2.ToolTip.text: i18n("Previous Track")
                    QQC2.ToolTip.visible: containsMouse && parent.enabled
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }

            // Play / Pause
            Rectangle {
                id: playPauseBtn
                width: root.isCompact ? 18 : 22
                height: root.isCompact ? 18 : 22
                radius: width / 2
                enabled: root.isMediaPlaying ? root.canMediaPause : root.canMediaPlay
                opacity: enabled ? 1.0 : 0.45
                color: playPauseMouse.containsMouse && enabled
                    ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                    : Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.75)
                border.width: 1
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                Behavior on color { ColorAnimation { duration: 120 } }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: root.isMediaPlaying ? "media-playback-pause" : "media-playback-start"
                    implicitWidth: root.isCompact ? 10 : 12
                    implicitHeight: root.isCompact ? 10 : 12
                    color: playPauseMouse.containsMouse && playPauseBtn.enabled ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                }

                MouseArea {
                    id: playPauseMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: mouse => {
                        mouse.accepted = true;
                        root.mediaPlayPauseClicked();
                    }
                    QQC2.ToolTip.text: root.isMediaPlaying ? i18n("Pause") : i18n("Play")
                    QQC2.ToolTip.visible: containsMouse && parent.enabled
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }

            // Next Track
            Rectangle {
                id: nextBtn
                width: root.isCompact ? 18 : 22
                height: root.isCompact ? 18 : 22
                radius: width / 2
                enabled: root.canMediaGoNext
                opacity: enabled ? 1.0 : 0.45
                color: nextMouse.containsMouse && enabled
                    ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                    : Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.75)
                border.width: 1
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                Behavior on color { ColorAnimation { duration: 120 } }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: "media-skip-forward"
                    implicitWidth: root.isCompact ? 10 : 12
                    implicitHeight: root.isCompact ? 10 : 12
                    color: nextMouse.containsMouse && nextBtn.enabled ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                }

                MouseArea {
                    id: nextMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: mouse => {
                        mouse.accepted = true;
                        root.mediaNextClicked();
                    }
                    QQC2.ToolTip.text: i18n("Next Track")
                    QQC2.ToolTip.visible: containsMouse && parent.enabled
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }
        }

        // 3. Close button: [Close button]
        Rectangle {
            id: closeBtn
            visible: root.showCloseButton
            anchors.verticalCenter: parent.verticalCenter
            width: root.isCompact ? 18 : 22
            height: root.isCompact ? 18 : 22
            radius: width / 2
            color: closeMouse.containsMouse
                ? (Kirigami.Theme.negativeTextColor ? Kirigami.Theme.negativeTextColor : "#e01b24")
                : Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.85)
            border.width: 1
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.20)
            Behavior on color { ColorAnimation { duration: 120 } }

            Kirigami.Icon {
                anchors.centerIn: parent
                source: "window-close-symbolic"
                implicitWidth: 12
                implicitHeight: 12
                color: closeMouse.containsMouse ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
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
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
    }

    // Application icon positioned on the bottom edge, peeking slightly over the card border
    Item {
        id: bottomAppIconItem
        visible: root.alternateCardStyle
        z: 90
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -Math.round(height * 0.22)

        readonly property real baseSize: root.alternateCardIconSize > 0 ? root.alternateCardIconSize : 64
        readonly property real scaleRatio: root.isCompact ? 0.55 : (root.height < 180 ? 0.70 : (root.height < 320 ? 0.85 : 1.0))
        width: Math.max(20, Math.round(baseSize * scaleRatio))
        height: width
        scale: bottomIconHoverHandler.hovered ? 1.08 : 1.0

        Behavior on scale {
            NumberAnimation { duration: Kirigami.Units.shortDuration }
        }

        HoverHandler {
            id: bottomIconHoverHandler
        }

        Kirigami.Icon {
            anchors.fill: parent
            source: root.iconSource
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                mouse.accepted = true;
                if (mouse.button === Qt.RightButton) {
                    root.selected();
                    root.contextMenuRequested(mouse.x, mouse.y, bottomAppIconItem);
                } else {
                    root.activated();
                }
            }
        }
    }
}
