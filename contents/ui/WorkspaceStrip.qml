import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import org.kde.plasma.workspace.dbus as DBus

Item {
    id: root

    height: 104
    Layout.fillWidth: true

    signal desktopSelected(var desktopId)
    signal currentDesktopClicked()

    property string highlightedDesktopId: ""

    function extractGeom(g) {
        if (!g) return null;
        if (typeof g === "object") {
            const x = Number(g.x !== undefined ? g.x : 0);
            const y = Number(g.y !== undefined ? g.y : 0);
            const w = Number(g.width !== undefined ? g.width : (g.w !== undefined ? g.w : 0));
            const h = Number(g.height !== undefined ? g.height : (g.h !== undefined ? g.h : 0));
            if (w > 0 && h > 0) return { x: x, y: y, width: w, height: h };
        }
        return null;
    }

    function getDesktopAt(globalX, globalY) {
        if (!cardRow || !cardRow.children) return null;
        for (let i = 0; i < cardRow.children.length; i++) {
            const item = cardRow.children[i];
            if (item && item.modelData !== undefined) {
                const mapped = item.mapFromItem(null, globalX, globalY);
                if (mapped.x >= 0 && mapped.x <= item.width && mapped.y >= 0 && mapped.y <= item.height) {
                    return { desktopId: item.modelData, index: item.index };
                }
            }
        }
        return null;
    }

    // Accurate screen aspect ratio from current display geometry
    readonly property real screenWidth: Screen.width > 0 ? Screen.width : 1920
    readonly property real screenHeight: Screen.height > 0 ? Screen.height : 1080
    readonly property real screenAspect: Math.max(1.0, root.screenWidth / root.screenHeight)

    // Preview canvas inside each card matches the physical screen aspect ratio exactly
    readonly property real previewHeight: 64
    readonly property real previewWidth: Math.round(previewHeight * screenAspect)

    TaskManager.VirtualDesktopInfo {
        id: desktopInfo
    }

    function switchDesktop(desktopId, index) {
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

        desktopSelected(desktopId);
    }

    // Centered horizontal row of workspace cards matching native KDE Plasma Pager
    RowLayout {
        id: cardRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: Kirigami.Units.largeSpacing

        Repeater {
            model: desktopInfo.desktopIds

            delegate: Rectangle {
                id: desktopCard
                required property var modelData
                required property int index

                readonly property bool isHighlighted: root.highlightedDesktopId === modelData
                readonly property bool isCurrent: desktopInfo.currentDesktop === modelData
                readonly property string desktopName: {
                    if (index < desktopInfo.desktopNames.length) {
                        return desktopInfo.desktopNames[index];
                    }
                    return i18n("Desktop %1", index + 1);
                }

                // Card framing matching KDE Plasma Pager style
                width: root.previewWidth + 10
                height: root.previewHeight + 26
                radius: 8
                scale: isHighlighted ? 1.06 : 1.0

                color: isHighlighted
                    ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.40)
                    : (isCurrent
                        ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.22)
                        : (cardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.45)))

                border.width: isHighlighted ? 2 : (isCurrent ? 2 : 1)
                border.color: isHighlighted
                    ? Kirigami.Theme.highlightColor
                    : (isCurrent
                        ? Kirigami.Theme.highlightColor
                        : (cardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.10)))

                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 3

                    // Workspace indicator header
                    RowLayout {
                        id: headerRow
                        Layout.fillWidth: true
                        Layout.preferredHeight: 14
                        Layout.maximumHeight: 14
                        Layout.leftMargin: 3
                        Layout.rightMargin: 3
                        spacing: 4

                        QQC2.Label {
                            text: desktopCard.desktopName
                            font.bold: desktopCard.isCurrent
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize - 2
                            color: desktopCard.isCurrent ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            width: 6
                            height: 6
                            radius: 3
                            color: Kirigami.Theme.highlightColor
                            visible: desktopCard.isCurrent
                        }
                    }

                    // Mini Desktop Preview Canvas (KDE Pager geometry and mini-window styling)
                    Rectangle {
                        id: miniCanvas
                        Layout.preferredWidth: root.previewWidth
                        Layout.preferredHeight: root.previewHeight
                        Layout.alignment: Qt.AlignHCenter
                        width: root.previewWidth
                        height: root.previewHeight
                        radius: 5
                        clip: true
                        color: desktopCard.isCurrent ? Qt.rgba(0.08, 0.11, 0.18, 0.95) : Qt.rgba(0.05, 0.06, 0.09, 0.95)
                        border.width: 1
                        border.color: desktopCard.isCurrent
                            ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.35)
                            : Qt.rgba(1, 1, 1, 0.08)

                        // Scaled miniature window rectangles matching KDE Plasma Pager
                        Item {
                            anchors.fill: parent
                            anchors.margins: 2

                            TaskManager.ActivityInfo {
                                id: stripActivityInfo
                            }

                            TaskManager.TasksModel {
                                id: wsTasks
                                filterByVirtualDesktop: true
                                virtualDesktop: desktopCard.modelData
                                filterByActivity: true
                                activity: stripActivityInfo.currentActivity
                                filterHidden: false
                                filterMinimized: false
                                filterNotMinimized: false
                                groupMode: TaskManager.TasksModel.GroupDisabled
                                sortMode: TaskManager.TasksModel.SortDisabled
                            }

                            Repeater {
                                model: wsTasks

                                delegate: Rectangle {
                                    id: miniWin
                                    required property var model
                                    required property int index

                                    readonly property string winTitle: model.display ? String(model.display).trim() : ""
                                    readonly property string winAppId: model.AppId ? String(model.AppId).trim() : ""
                                    readonly property bool isSelf: winTitle === "Veronica Overview" || winAppId === "stakillion.veronica.overview" || Boolean(model.SkipTaskbar) || Boolean(model.SkipPager)

                                    visible: !isSelf

                                    readonly property var geom: root.extractGeom(model.Geometry)
                                    readonly property bool isWinActive: Boolean(model.IsActive)
                                    readonly property bool isWinMinimized: Boolean(model.IsMinimized)
                                    readonly property var winIcon: model.decoration ? model.decoration : "application-x-executable"
                                    readonly property int stackOrder: model.StackingOrder !== undefined ? Number(model.StackingOrder) : index

                                    z: isWinActive ? 10000 : (stackOrder >= 0 ? stackOrder : index)

                                    x: geom ? Math.max(0, Math.min(parent.width - width, (geom.x / root.screenWidth) * parent.width)) : (index * 8)
                                    y: geom ? Math.max(0, Math.min(parent.height - height, (geom.y / root.screenHeight) * parent.height)) : (index * 6)
                                    width: geom ? Math.max(12, Math.min(parent.width, (geom.width / root.screenWidth) * parent.width)) : 22
                                    height: geom ? Math.max(10, Math.min(parent.height, (geom.height / root.screenHeight) * parent.height)) : 16

                                    radius: 2
                                    opacity: isWinMinimized ? 0.45 : 1.0

                                    // Active window vs standard window fill matching Plasma Pager
                                    color: isWinActive
                                        ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.80)
                                        : Qt.rgba(0.24, 0.26, 0.32, 0.88)

                                    border.width: isWinActive ? 1.5 : 1
                                    border.color: isWinActive
                                        ? Kirigami.Theme.highlightColor
                                        : Qt.rgba(1, 1, 1, 0.22)

                                    // Centered miniature application icon
                                    Kirigami.Icon {
                                        anchors.centerIn: parent
                                        source: miniWin.winIcon
                                        implicitWidth: Math.min(miniWin.height - 2, Math.min(miniWin.width - 2, 12))
                                        implicitHeight: implicitWidth
                                    }
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (desktopCard.isCurrent) {
                            root.currentDesktopClicked();
                        } else {
                            root.switchDesktop(desktopCard.modelData, desktopCard.index);
                        }
                    }
                }
            }
        }
    }
}

