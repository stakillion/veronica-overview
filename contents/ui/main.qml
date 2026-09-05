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
    expanded: false

    activationTogglesExpanded: false
    hideOnWindowDeactivate: false

    property bool isOverviewOpen: false
    property bool ignoreWindowMoveActivation: false
    property var lastActiveWinId: null
    property var lastSwitchedDesktop: null
    property var lastSeenDesktop: desktopInfoMonitor.currentDesktop

    TaskManager.VirtualDesktopInfo {
        id: desktopInfoMonitor
        onCurrentDesktopChanged: {
            root.lastSeenDesktop = String(currentDesktop);
            if (root.isOverviewOpen) {
                overviewDialog.requestActivate();
                if (overviewOverlay) {
                    overviewOverlay.forceActiveFocus();
                }
            }
            if (root.lastSwitchedDesktop && String(root.lastSwitchedDesktop) === String(root.lastSeenDesktop)) {
                Qt.callLater(() => {
                    if (root.lastSwitchedDesktop && String(root.lastSwitchedDesktop) === String(root.lastSeenDesktop)) {
                        root.lastSwitchedDesktop = null;
                    }
                });
            }
        }
    }

    function recordDesktopSwitch(desktopId) {
        root.lastSwitchedDesktop = String(desktopId);
    }

    TaskManager.ActivityInfo {
        id: globalActivityInfo
    }

    TaskManager.TasksModel {
        id: globalFocusMonitor
        filterByVirtualDesktop: false
        filterByActivity: true
        activity: globalActivityInfo.currentActivity
        filterByScreen: false
        filterHidden: false
        filterMinimized: false
        filterNotMinimized: false
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortDisabled

        onActiveTaskChanged: {
            if (!root.isOverviewOpen && activeTask && activeTask.valid) {
                const winIds = globalFocusMonitor.data(activeTask, TaskManager.AbstractTasksModel.WinIdList);
                if (winIds && winIds.length > 0) {
                    root.lastActiveWinId = winIds[0];
                }
            }

            if (root.isOverviewOpen && activeTask && activeTask.valid) {
                if (root.ignoreWindowMoveActivation) {
                    root.ignoreWindowMoveActivation = false;
                    return;
                }
                // If a virtual desktop switch was initiated inside the overview, ignore active task changes during the switch
                if (root.lastSwitchedDesktop !== null) {
                    return;
                }
                // If the task is minimized, ignore it
                if (globalFocusMonitor.data(activeTask, TaskManager.AbstractTasksModel.IsMinimized) === true) {
                    return;
                }

                const display = String(globalFocusMonitor.data(activeTask, TaskManager.AbstractTasksModel.DisplayRole) || "").toLowerCase();
                const appId = String(globalFocusMonitor.data(activeTask, TaskManager.AbstractTasksModel.AppId) || "").toLowerCase();
                const appName = String(globalFocusMonitor.data(activeTask, TaskManager.AbstractTasksModel.AppName) || "").toLowerCase();

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

                // Regular unminimized application window was focused (e.g. from taskbar)
                root.closeImmediately();
            }
        }
    }

    readonly property string kwinScriptPath: {
        const url = Qt.resolvedUrl("../code/overviewDesktopController.js").toString();
        return url.replace(/^file:\/\//, "");
    }

    property bool kwinScriptLoaded: false

    function ensureKWinScriptLoaded() {
        if (root.kwinScriptLoaded) return;
        root.kwinScriptLoaded = true;
        DBus.SessionBus.asyncCall({
            service: "org.kde.KWin",
            path: "/Scripting",
            iface: "org.kde.kwin.Scripting",
            member: "unloadScript",
            arguments: [root.kwinScriptPath]
        });
        DBus.SessionBus.asyncCall({
            service: "org.kde.KWin",
            path: "/Scripting",
            iface: "org.kde.kwin.Scripting",
            member: "loadScript",
            arguments: [root.kwinScriptPath]
        });
        DBus.SessionBus.asyncCall({
            service: "org.kde.KWin",
            path: "/Scripting",
            iface: "org.kde.kwin.Scripting",
            member: "start",
            arguments: []
        });
    }

    Component.onCompleted: {
        root.ensureKWinScriptLoaded();
    }

    function toggleOverview() {
        if (isOverviewOpen) {
            closeOverview();
        } else {
            openOverview();
        }
    }

    function openOverview() {
        root.ensureKWinScriptLoaded();
        root.ignoreWindowMoveActivation = false;
        root.lastSwitchedDesktop = null;
        root.pendingWindowActivation = null;
        closeTimer.stop();
        if (globalFocusMonitor.activeTask && globalFocusMonitor.activeTask.valid) {
            const winIds = globalFocusMonitor.data(globalFocusMonitor.activeTask, TaskManager.AbstractTasksModel.WinIdList);
            if (winIds && winIds.length > 0) {
                root.lastActiveWinId = winIds[0];
            }
        }

        isOverviewOpen = true;
        
        if (overviewOverlay) {
            overviewOverlay.openOverview();
        }

        overviewDialog.title = "Veronica Overview:open:" + root.fadeDuration;
        overviewDialog.visible = true;

        // Save original hiding mode ONLY if not already in temporary state, then set dodge-windows panels to 'windowsgobelow'
        DBus.SessionBus.asyncCall({
            service: "org.kde.plasmashell",
            path: "/PlasmaShell",
            iface: "org.kde.PlasmaShell",
            member: "evaluateScript",
            arguments: ["var pans = panels(); for (var i = 0; i < pans.length; i++) { pans[i].currentConfigGroup = ['General']; if (pans[i].hiding === 'dodgewindows') { pans[i].writeConfig('OriginalHiding', 'dodgewindows'); pans[i].hiding = 'windowsgobelow'; } }"]
        });
    }

    property var pendingWindowActivation: null

    function closeImmediately(callback) {
        if (!isOverviewOpen) return;

        closeTimer.stop();
        overviewDialog.title = "Veronica Overview:instant-close";
        root.pendingWindowActivation = callback || null;
        root.finalizeClose();
    }

    function closeOverview() {
        if (!isOverviewOpen) return;

        overviewDialog.title = "Veronica Overview:close:" + root.fadeDuration;
        closeTimer.restart();
    }

    function grabOverviewFocus() {
        if (isOverviewOpen && overviewDialog.visible) {
            overviewDialog.requestActivate();
            if (overviewOverlay) {
                overviewOverlay.forceActiveFocus();
            }
        }
    }

    function finalizeClose() {
        isOverviewOpen = false;
        overviewDialog.visible = false;
        overviewDialog.title = "Veronica Overview";

        // Restore panels back to their original hiding mode and clear temporary config key
        DBus.SessionBus.asyncCall({
            service: "org.kde.plasmashell",
            path: "/PlasmaShell",
            iface: "org.kde.PlasmaShell",
            member: "evaluateScript",
            arguments: ["var pans = panels(); for (var i = 0; i < pans.length; i++) { pans[i].currentConfigGroup = ['General']; var orig = pans[i].readConfig('OriginalHiding'); if (orig && orig === 'dodgewindows') { pans[i].hiding = 'dodgewindows'; pans[i].writeConfig('OriginalHiding', ''); } }"]
        });

        if (root.pendingWindowActivation) {
            const activateFn = root.pendingWindowActivation;
            root.pendingWindowActivation = null;
            activateFn();
        }
    }

    Plasmoid.onActivated: {
        root.toggleOverview();
    }

    readonly property int fadeDuration: Kirigami.Units.longDuration

    Timer {
        id: closeTimer
        interval: root.fadeDuration
        repeat: false
        onTriggered: {
            root.finalizeClose();
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
        type: PlasmaCore.Dialog.FullScreen
        location: PlasmaCore.Types.Floating
        visualParent: compactView
        backgroundHints: PlasmaCore.Dialog.StandardBackground
        flags: Qt.FramelessWindowHint | Qt.Window | Qt.CustomizeWindowHint
        hideOnWindowDeactivate: false
        opacity: 0
        visible: false

        property bool _needsFocusGrab: false

        onVisibleChanged: {
            if (visible) {
                _needsFocusGrab = true;
            } else {
                _needsFocusGrab = false;
            }
        }

        onFrameSwapped: {
            if (_needsFocusGrab) {
                _needsFocusGrab = false;
                root.grabOverviewFocus();
            }
        }

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

        mainItem: OverviewOverlay {
            id: overviewOverlay
            width: overviewDialog.lockedWidth
            height: overviewDialog.lockedHeight
            isOverviewOpen: root.isOverviewOpen
            lastActiveWinId: root.lastActiveWinId

            onRequestDesktopSwitch: desktopId => root.recordDesktopSwitch(desktopId)
            onRequestTaskMoved: targetDesktopId => {
                root.ignoreWindowMoveActivation = true;
            }
            onRequestClose: {
                root.closeOverview();
            }
            onRequestCloseImmediately: callback => {
                root.closeImmediately(callback);
            }
        }
    }
}
