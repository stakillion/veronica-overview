pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window

import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.workspace.dbus as DBus
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    readonly property bool inPanel: [
        PlasmaCore.Types.TopEdge,
        PlasmaCore.Types.RightEdge,
        PlasmaCore.Types.BottomEdge,
        PlasmaCore.Types.LeftEdge,
    ].includes(Plasmoid.location)

    readonly property string iconName: Plasmoid.configuration.icon || Plasmoid.configuration.buttonIconName || "search"

    Plasmoid.icon: iconName
    Plasmoid.title: i18n("Veronica Overview")
    Plasmoid.status: root.isOverviewOpen ? PlasmaCore.Types.AcceptingInputStatus : PlasmaCore.Types.ActiveStatus
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground
    Plasmoid.userBackgroundHints: PlasmaCore.Types.DefaultBackground

    activationTogglesExpanded: false
    hideOnWindowDeactivate: false

    property bool isOverviewOpen: false

    Timer {
        id: armFocusTrackingTimer
        interval: 350
        repeat: false
        onTriggered: {
            root.focusTrackingArmed = true;
        }
    }

    TaskManager.TasksModel {
        id: globalFocusMonitor
        filterByVirtualDesktop: false
        filterByActivity: false
        filterByScreen: false
        filterHidden: false
        filterMinimized: true
        filterNotMinimized: false
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortDisabled

        onActiveTaskChanged: {
            if (root.isOverviewOpen && !root.isSwitchingDesktop && root.focusTrackingArmed && activeTask && activeTask.valid) {
                // If the task is minimized, ignore it
                if (globalFocusMonitor.data(activeTask, 279) === true) {
                    return;
                }

                const display = String(globalFocusMonitor.data(activeTask, 0) || "").toLowerCase();
                const appId = String(globalFocusMonitor.data(activeTask, 257) || "").toLowerCase();
                const appName = String(globalFocusMonitor.data(activeTask, 258) || "").toLowerCase();

                // Exclude Yakuake, plasma applets, and background bridges
                if (display.includes("yakuake") || appId.includes("yakuake") || appName.includes("yakuake")) {
                    return;
                }
                if (appId.includes("plasmashell") || appName.includes("plasmashell")) {
                    return;
                }
                if (appId.includes("xwaylandvideobridge") || appName.includes("xwaylandvideobridge")) {
                    return;
                }

                // Regular unminimized application window was focused
                root.closeOverview();
            }
        }
    }

    function toggleOverview() {
        if (isOverviewOpen) {
            closeOverview();
        } else {
            openOverview();
        }
    }

    function openOverview() {
        isOverviewOpen = true;
        overviewDialog.visible = true;
        overviewOverlay.opacity = 1;

        // Save original hiding mode and set dodge-windows panels to 'none' (Always Visible) while overview is open
        DBus.SessionBus.asyncCall({
            service: "org.kde.plasmashell",
            path: "/PlasmaShell",
            iface: "org.kde.PlasmaShell",
            member: "evaluateScript",
            arguments: ["var pans = panels(); for (var i = 0; i < pans.length; i++) { pans[i].currentConfigGroup = ['General']; pans[i].writeConfig('OriginalHiding', pans[i].hiding); if (pans[i].hiding === 'dodgewindows') { pans[i].hiding = 'windowsgobelow'; } }"]
        });
    }

    function closeOverview() {
        isOverviewOpen = false;

        fadeAnim.to = 0;
        fadeAnim.start();

        // Restore panels back to their original hiding mode
        DBus.SessionBus.asyncCall({
            service: "org.kde.plasmashell",
            path: "/PlasmaShell",
            iface: "org.kde.PlasmaShell",
            member: "evaluateScript",
            arguments: ["var pans = panels(); for (var i = 0; i < pans.length; i++) { pans[i].currentConfigGroup = ['General']; var orig = pans[i].readConfig('OriginalHiding'); if (orig && orig !== '') { pans[i].hiding = orig; } }"]
        });
    }

    Plasmoid.onActivated: {
        root.toggleOverview();
    }

    PropertyAnimation {
        id: fadeAnim
        target: overviewOverlay
        property: "opacity"
        duration: Kirigami.Units.shortDuration
        easing.type: Easing.InOutQuad
        onFinished: {
            if (overviewOverlay.opacity === 0) {
                overviewDialog.visible = false;
            }
        }
    }

    implicitWidth: compactView.implicitWidth
    implicitHeight: compactView.implicitHeight

    Layout.minimumWidth: compactView.Layout.minimumWidth
    Layout.preferredWidth: compactView.Layout.preferredWidth
    Layout.minimumHeight: compactView.Layout.minimumHeight
    Layout.preferredHeight: compactView.Layout.preferredHeight
    Layout.fillWidth: compactView.Layout.fillWidth
    Layout.fillHeight: compactView.Layout.fillHeight

    CompactRepresentation {
        id: compactView
        anchors.fill: parent
        plasmoidItem: root
    }

    PlasmaCore.Dialog {
        id: overviewDialog

        title: "Veronica Overview"
        type: PlasmaCore.Dialog.Normal
        location: PlasmaCore.Types.Floating
        backgroundHints: PlasmaCore.Dialog.StandardBackground
        flags: Qt.FramelessWindowHint | Qt.Window | Qt.CustomizeWindowHint | Qt.MSWindowsFixedSizeDialogHint
        hideOnWindowDeactivate: false
        visible: false

        readonly property int lockedWidth: Math.round(Screen.width > 0 ? Screen.width : 1920)
        readonly property int lockedHeight: Math.round(Screen.height > 0 ? Screen.height : 1080)

        x: 0
        y: 0
        width: lockedWidth
        height: lockedHeight
        minimumWidth: lockedWidth
        maximumWidth: lockedWidth
        minimumHeight: lockedHeight
        maximumHeight: lockedHeight

        OverviewOverlay {
            id: overviewOverlay
            width: overviewDialog.lockedWidth
            height: overviewDialog.lockedHeight
            isOverviewOpen: root.isOverviewOpen
            opacity: 0

            onRequestClose: {
                root.closeOverview();
            }
        }
    }
}
