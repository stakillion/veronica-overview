pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.taskmanager as TaskManager

Item {
    id: root

    property bool showTitles: true
    property bool showCloseButtons: Plasmoid.configuration.showCloseButtons !== undefined ? Plasmoid.configuration.showCloseButtons : true
    property bool filterOnlyCurrentDesktop: Plasmoid.configuration.filterOnlyCurrentDesktop !== undefined ? Plasmoid.configuration.filterOnlyCurrentDesktop : true
    property bool overviewOpen: false
    property int cardRadius: 14
    property var lastActiveWinId: null

    property int layoutRefreshTick: 0
    property bool readyToAnimate: false

    signal windowActivated()
    signal windowClosed()
    signal emptyAreaClicked()
    signal windowDragStarted(int pageIndex, int taskRow, var winIds, string title, var icon, string appName, real cardW, real cardH, real globalOriginX, real globalOriginY, real grabX, real grabY)
    signal windowDragMoved(real globalX, real globalY)
    signal windowDragEnded(real globalX, real globalY)
    signal windowDragCanceled()

    function clearSelection() {
        if (pageRepeater) {
            const page = pageRepeater.itemAt(root.currentDesktopIndex);
            if (page && page.clearSelection) {
                page.clearSelection();
            }
        }
    }

    function updateDefaultSelection() {
        if (pageRepeater) {
            const page = pageRepeater.itemAt(root.currentDesktopIndex);
            if (page && page.updateDefaultSelection) {
                page.updateDefaultSelection();
            }
        }
    }

    function navigateSelection(dx, dy) {
        if (pageRepeater) {
            const page = pageRepeater.itemAt(root.currentDesktopIndex);
            if (page && page.navigateSelection) {
                return page.navigateSelection(dx, dy);
            }
        }
        return "no_page";
    }

    function activateSelected() {
        if (pageRepeater) {
            const page = pageRepeater.itemAt(root.currentDesktopIndex);
            if (page && page.activateSelected) {
                page.activateSelected();
            }
        }
    }

    function moveTaskToDesktop(pageIndex, taskRow, targetDesktopId) {
        if (pageRepeater) {
            const page = pageRepeater.itemAt(pageIndex);
            if (page && page.moveTaskToDesktop) {
                page.moveTaskToDesktop(taskRow, targetDesktopId);
            }
        }
    }

    function cancelDrag() {
        if (pageRepeater) {
            for (let i = 0; i < pageRepeater.count; i++) {
                const page = pageRepeater.itemAt(i);
                if (page && page.cancelDrag) {
                    page.cancelDrag();
                }
            }
        }
    }

    clip: true

    function resetTracking() {
        root.layoutRefreshTick++;
    }

    TaskManager.VirtualDesktopInfo {
        id: desktopInfo
    }

    readonly property int pageCount: Math.max(1, desktopInfo.desktopIds ? desktopInfo.desktopIds.length : 1)
    readonly property int currentDesktopIndex: {
        const ids = desktopInfo.desktopIds;
        const cur = desktopInfo.currentDesktop;
        if (!ids || ids.length === 0) return 0;
        const idx = ids.indexOf(cur);
        return idx >= 0 ? idx : 0;
    }

    onCurrentDesktopIndexChanged: {
        root.layoutRefreshTick++;
    }

    onVisibleChanged: {
        if (visible) {
            readyToAnimate = false;
            pagesTrack.x = -root.currentDesktopIndex * root.width;
            Qt.callLater(() => {
                root.readyToAnimate = true;
                root.layoutRefreshTick++;
            });
        } else {
            readyToAnimate = false;
        }
    }

    Component.onCompleted: {
        readyToAnimate = false;
        pagesTrack.x = -root.currentDesktopIndex * root.width;
        Qt.callLater(() => {
            root.readyToAnimate = true;
            root.layoutRefreshTick++;
        });
    }

    function onPageTaskActivated() {
        root.windowActivated();
    }

    function onPageTaskClosed() {
        root.layoutRefreshTick++;
        root.windowClosed();
    }

    // Dismiss click area covering entire background
    MouseArea {
        id: bgClickArea
        anchors.fill: parent
        z: -1
        onClicked: root.emptyAreaClicked()
        onWheel: wheel => {
            wheel.accepted = false;
        }
    }

    // Multi-page sliding carousel track
    Item {
        id: pagesTrack

        width: root.width * root.pageCount
        height: root.height
        x: -root.currentDesktopIndex * root.width

        // Matches the speed, fluid momentum, and global animation scale of KDE's native virtual desktop slide
        Behavior on x {
            enabled: root.readyToAnimate
            NumberAnimation {
                duration: Kirigami.Units.longDuration > 0 ? Math.round(Kirigami.Units.longDuration * 1.5) : 380
                easing.type: Easing.OutCubic
            }
        }

        Repeater {
            id: pageRepeater
            model: desktopInfo.desktopIds

            delegate: WorkspacePage {
                id: pageDelegate
                required property var modelData
                required property int index

                x: pageDelegate.index * root.width
                y: 0
                width: root.width
                height: root.height

                desktopId: pageDelegate.modelData
                pageIndex: pageDelegate.index
                isCurrentPage: pageDelegate.index === root.currentDesktopIndex
                lastActiveWinId: root.lastActiveWinId

                showCloseButtons: root.showCloseButtons
                cardRadius: root.cardRadius
                overviewOpen: root.overviewOpen
                layoutRefreshTick: root.layoutRefreshTick

                onTaskActivated: root.onPageTaskActivated()
                onTaskClosed: root.onPageTaskClosed()
                onEmptyAreaClicked: root.emptyAreaClicked()

                onWindowDragStarted: (pageIdx, taskRow, winIds, title, icon, appName, cardW, cardH, ox, oy, gx, gy) => {
                    root.windowDragStarted(pageIdx, taskRow, winIds, title, icon, appName, cardW, cardH, ox, oy, gx, gy);
                }
                onWindowDragMoved: (gx, gy) => {
                    root.windowDragMoved(gx, gy);
                }
                onWindowDragEnded: (gx, gy) => {
                    root.windowDragEnded(gx, gy);
                }
                onWindowDragCanceled: {
                    root.windowDragCanceled();
                }
            }
        }
    }
}
