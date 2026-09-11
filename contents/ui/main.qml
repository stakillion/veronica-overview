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

    property int targetLauncherId: -1
    property real lastOverviewOpenTime: 0
    property bool isLauncherOpenOnOverview: false
    readonly property int doubleSuperThreshold: 380

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

    property int dynamicPanelTop: (Plasmoid.location === PlasmaCore.Types.TopEdge) ? 40 : 0
    property int dynamicPanelBottom: (Plasmoid.location === PlasmaCore.Types.BottomEdge) ? 48 : 0
    property int dynamicPanelLeft: (Plasmoid.location === PlasmaCore.Types.LeftEdge) ? 48 : 0
    property int dynamicPanelRight: (Plasmoid.location === PlasmaCore.Types.RightEdge) ? 48 : 0

    function updatePanelMargins() {
        const script = "var pans = panels(); var top = 0, bottom = 0, left = 0, right = 0; " +
            "for (var i = 0; i < pans.length; i++) { " +
            "  var p = pans[i]; " +
            "  var hMode = p.readConfig('OriginalHiding') || p.hiding; " +
            "  if (hMode === 'autohide') continue; " +
            "  var thickness = p.height || 0; " +
            "  if (p.floating) thickness += 16; " +
            "  if (p.location === 'top') top = Math.max(top, thickness); " +
            "  else if (p.location === 'bottom') bottom = Math.max(bottom, thickness); " +
            "  else if (p.location === 'left') left = Math.max(left, thickness); " +
            "  else if (p.location === 'right') right = Math.max(right, thickness); " +
            "} " +
            "print(JSON.stringify({top: top, bottom: bottom, left: left, right: right}));";

        DBus.SessionBus.asyncCall({
            service: "org.kde.plasmashell",
            path: "/PlasmaShell",
            iface: "org.kde.PlasmaShell",
            member: "evaluateScript",
            arguments: [script]
        }, function(reply) {
            try {
                var raw = "";
                if (reply && reply.value && reply.value.value) {
                    raw = reply.value.value;
                } else if (reply && reply.value) {
                    raw = String(reply.value);
                }
                if (raw && raw.length > 0) {
                    var data = JSON.parse(raw);
                    if (data && typeof data === "object") {
                        root.dynamicPanelTop = (typeof data.top === "number") ? data.top : 0;
                        root.dynamicPanelBottom = (typeof data.bottom === "number") ? data.bottom : 0;
                        root.dynamicPanelLeft = (typeof data.left === "number") ? data.left : 0;
                        root.dynamicPanelRight = (typeof data.right === "number") ? data.right : 0;
                    }
                }
            } catch (e) {}
        }, function(err) {});
    }

    Component.onCompleted: {
        root.ensureKWinScriptLoaded();
        root.updatePanelMargins();
        root.discoverAndPrimeLauncher();
    }

    Connections {
        target: Plasmoid.configuration
        function onDoubleSuperOpenLauncherChanged() {
            if (Plasmoid.configuration.doubleSuperOpenLauncher) {
                root.discoverAndPrimeLauncher();
            }
        }
    }

    function discoverAndPrimeLauncher() {
        if (Plasmoid.configuration.doubleSuperOpenLauncher !== true) return;

        const script =
            "var pans = panels(); " +
            "var targetId = -1; " +
            "for (var i = 0; i < pans.length; i++) { " +
            "  var w = pans[i].widgets(); " +
            "  for (var j = 0; j < w.length; j++) { " +
            "    var type = w[j].type; " +
            "    if (type === 'stakillion.veronica.overview') continue; " +
            "    if (type === 'org.kde.plasma.kickoff' || " +
            "        type === 'org.kde.plasma.kicker' || " +
            "        type === 'org.kde.plasma.kickerdash' || " +
            "        type === 'org.kde.plasma.simplemenu' || " +
            "        type.indexOf('launcher') !== -1 || " +
            "        type.indexOf('kickoff') !== -1 || " +
            "        type.indexOf('kicker') !== -1 || " +
            "        type.indexOf('menu') !== -1 || " +
            "        type.indexOf('start') !== -1) { " +
            "      targetId = w[j].id; " +
            "      if (!w[j].globalShortcut || w[j].globalShortcut === '') { " +
            "        w[j].globalShortcut = 'Meta+Ctrl+Alt+Shift+F11'; " +
            "      } " +
            "      break; " +
            "    } " +
            "  } " +
            "  if (targetId !== -1) break; " +
            "} " +
            "print(targetId);";

        DBus.SessionBus.asyncCall({
            service: "org.kde.plasmashell",
            path: "/PlasmaShell",
            iface: "org.kde.PlasmaShell",
            member: "evaluateScript",
            arguments: [script]
        }, function(reply) {
            try {
                var raw = "";
                if (reply && reply.value && reply.value.value) raw = reply.value.value;
                else if (reply && reply.value) raw = String(reply.value);
                var id = parseInt(raw, 10);
                if (!isNaN(id) && id > 0) {
                    root.targetLauncherId = id;
                }
            } catch (_) {}
        }, function(_) {});
    }

    function toggleApplicationLauncher() {
        if (root.targetLauncherId <= 0) return;
        DBus.SessionBus.asyncCall({
            service: "org.kde.kglobalaccel",
            path: "/component/plasmashell",
            iface: "org.kde.kglobalaccel.Component",
            member: "invokeShortcut",
            arguments: ["activate widget " + root.targetLauncherId]
        });
    }

    function toggleOverview() {
        if (isOverviewOpen) {
            closeOverview();
        } else {
            openOverview();
        }
    }

    function openOverview() {
        root.discoverAndPrimeLauncher();
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

        // Save original hiding mode ONLY if not already in temporary state, set dodge-windows panels to 'windowsgobelow', and compute dynamic panel margins across all edges
        const script = "var pans = panels(); var top = 0, bottom = 0, left = 0, right = 0; " +
            "for (var i = 0; i < pans.length; i++) { " +
            "  var p = pans[i]; " +
            "  p.currentConfigGroup = ['General']; " +
            "  if (p.hiding === 'dodgewindows') { " +
            "    p.writeConfig('OriginalHiding', 'dodgewindows'); " +
            "    p.hiding = 'windowsgobelow'; " +
            "  } " +
            "  var hMode = p.readConfig('OriginalHiding') || p.hiding; " +
            "  if (hMode !== 'autohide') { " +
            "    var thickness = p.height || 0; " +
            "    if (p.floating) thickness += 16; " +
            "    if (p.location === 'top') top = Math.max(top, thickness); " +
            "    else if (p.location === 'bottom') bottom = Math.max(bottom, thickness); " +
            "    else if (p.location === 'left') left = Math.max(left, thickness); " +
            "    else if (p.location === 'right') right = Math.max(right, thickness); " +
            "  } " +
            "} " +
            "print(JSON.stringify({top: top, bottom: bottom, left: left, right: right}));";

        DBus.SessionBus.asyncCall({
            service: "org.kde.plasmashell",
            path: "/PlasmaShell",
            iface: "org.kde.PlasmaShell",
            member: "evaluateScript",
            arguments: [script]
        }, function(reply) {
            try {
                var raw = "";
                if (reply && reply.value && reply.value.value) {
                    raw = reply.value.value;
                } else if (reply && reply.value) {
                    raw = String(reply.value);
                }
                if (raw && raw.length > 0) {
                    var data = JSON.parse(raw);
                    if (data && typeof data === "object") {
                        root.dynamicPanelTop = (typeof data.top === "number") ? data.top : 0;
                        root.dynamicPanelBottom = (typeof data.bottom === "number") ? data.bottom : 0;
                        root.dynamicPanelLeft = (typeof data.left === "number") ? data.left : 0;
                        root.dynamicPanelRight = (typeof data.right === "number") ? data.right : 0;
                    }
                }
            } catch (e) {}
        }, function(err) {});
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
        if (root.isLauncherOpenOnOverview) {
            root.toggleApplicationLauncher();
            root.isLauncherOpenOnOverview = false;
        }

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
        const now = Date.now();
        const doubleSuperEnabled = Plasmoid.configuration.doubleSuperOpenLauncher === true;

        if (!root.isOverviewOpen) {
            root.lastOverviewOpenTime = now;
            root.isLauncherOpenOnOverview = false;
            root.openOverview();
            return;
        }

        // If launcher is open on top of overview: close launcher, keep overview open
        if (root.isLauncherOpenOnOverview) {
            root.isLauncherOpenOnOverview = false;
            root.toggleApplicationLauncher();
            root.grabOverviewFocus();
            return;
        }

        // If overview is open and Meta is pressed quickly (< 380ms): open launcher
        if (doubleSuperEnabled && root.targetLauncherId > 0 && (now - root.lastOverviewOpenTime < root.doubleSuperThreshold)) {
            root.isLauncherOpenOnOverview = true;
            root.toggleApplicationLauncher();
            return;
        }

        root.closeOverview();
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

        onActiveChanged: {
            if (active && root.isLauncherOpenOnOverview) {
                root.isLauncherOpenOnOverview = false;
            }
        }

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

            panelMarginTop: root.dynamicPanelTop
            panelMarginBottom: root.dynamicPanelBottom
            panelMarginLeft: root.dynamicPanelLeft
            panelMarginRight: root.dynamicPanelRight

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
