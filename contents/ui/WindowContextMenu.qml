import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras
import org.kde.taskmanager as TaskManager
import org.kde.plasma.private.mpris as Mpris
import plasma.applet.org.kde.plasma.taskmanager as TaskManagerApplet

Item {
    id: wrapper

    property bool canLaunchNewInstance: false
    property bool isOnAllDesktops: false
    property bool isVirtualDesktopsChangeable: true
    property var virtualDesktops: []
    property var activities: []
    property int desktopCount: 0
    property var desktopIds: []
    property bool isMovable: false
    property bool isResizable: false
    property bool isMaximizable: true
    property bool isMaximized: false
    property bool isMinimizable: true
    property bool isMinimized: false
    property bool isKeepAbove: false
    property bool isKeepBelow: false
    property bool isFullScreenable: true
    property bool isFullScreen: false
    property bool isShadeable: false
    property bool isShaded: false
    property bool canSetNoBorder: false
    property bool hasNoBorder: false
    property bool isExcludedFromCapture: false
    property bool isClosable: true

    property var launcherUrl: ""
    property string appId: ""
    property int appPid: 0
    property var winIdList: []
    property var targetPlayer: null
    property bool hasAudioStream: false
    property bool playingAudio: false
    property bool isAudioMuted: false
    property bool hasMicStream: false
    property bool recordingMic: false
    property bool isMicMuted: false
    property bool hasDuplicateNewWindow: false
    property var dynamicItems: []
    property bool showAllPlaces: false
    property var currentVisualParent: null
    property real currentX: 0
    property real currentY: 0
    property bool hasExplicitPos: false

    Component.onCompleted: {
        try {
            backend.showAllPlaces.connect(wrapper.handleShowAllPlaces);
        } catch (e) {
            console.warn("[Veronica Overview] Failed to connect backend.showAllPlaces:", e);
        }
    }

    Component.onDestruction: {
        try {
            backend.showAllPlaces.disconnect(wrapper.handleShowAllPlaces);
        } catch (_) {}
    }

    function handleShowAllPlaces() {
        wrapper.showAllPlaces = true;
        wrapper.loadDynamicActions();
        if (wrapper.currentVisualParent) {
            menu.visualParent = wrapper.currentVisualParent;
        }
        Qt.callLater(() => {
            if (wrapper.hasExplicitPos) {
                menu.open(Math.round(wrapper.currentX), Math.round(wrapper.currentY));
            } else {
                menu.openRelative();
            }
        });
    }

    signal requestDismissOverview()
    signal requestToggleMuted()
    signal requestToggleMicMuted()
    signal requestNewInstance()
    signal requestMove()
    signal requestResize()
    signal requestToggleMinimized()
    signal requestToggleMaximized()
    signal requestToggleKeepAbove()
    signal requestToggleKeepBelow()
    signal requestToggleFullScreen()
    signal requestToggleShaded()
    signal requestToggleNoBorder()
    signal requestToggleExcludeFromCapture()
    signal requestVirtualDesktops(var desktops)
    signal requestNewVirtualDesktop()
    signal requestActivities(var activities)
    signal requestClose()

    TaskManager.VirtualDesktopInfo {
        id: desktopInfo
    }

    TaskManager.ActivityInfo {
        id: activityInfo
    }

    TaskManagerApplet.Backend {
        id: backend
    }

    Mpris.Mpris2Model {
        id: mpris2Source
    }

    TextMetrics {
        id: textMetrics
        elide: Qt.ElideRight
        elideWidth: Kirigami.Units.gridUnit * 22
    }

    function newMenuItem(parentObj) {
        return Qt.createQmlObject('import org.kde.plasma.extras as PlasmaExtras; PlasmaExtras.MenuItem {}', parentObj);
    }

    function newSeparator(parentObj) {
        return Qt.createQmlObject('import org.kde.plasma.extras as PlasmaExtras; PlasmaExtras.MenuItem { separator: true }', parentObj);
    }

    function clearDynamicItems() {
        for (let i = 0; i < dynamicItems.length; ++i) {
            if (dynamicItems[i]) {
                try {
                    menu.removeMenuItem(dynamicItems[i]);
                    dynamicItems[i].destroy();
                } catch (e) {
                    console.warn("[Veronica Overview] Failed to clean up dynamic item:", e);
                }
            }
        }
        wrapper.dynamicItems = [];
        wrapper.hasDuplicateNewWindow = false;
    }

    function loadDynamicActions() {
        wrapper.clearDynamicItems();

        let effectiveUrl = wrapper.launcherUrl;
        if (!effectiveUrl || String(effectiveUrl).length === 0) {
            if (wrapper.appId && wrapper.appId.length > 0) {
                let id = wrapper.appId;
                if (!id.endsWith(".desktop")) {
                    id += ".desktop";
                }
                effectiveUrl = "applications:" + id;
            }
        }

        if (!effectiveUrl || String(effectiveUrl).length === 0) {
            return;
        }

        let sections = [];

        // 1. Places (e.g. Dolphin) or Recent Files (e.g. Brave, Kate)
        try {
            const placesActions = backend.placesActions(effectiveUrl, wrapper.showAllPlaces, menu);
            if (placesActions && placesActions.length > 0) {
                sections.push({
                    title: i18nc("@title:group for section of menu items", "Places"),
                    group: "places",
                    actions: placesActions
                });
            } else {
                const recents = backend.recentDocumentActions(effectiveUrl, menu);
                if (recents && recents.length > 0) {
                    sections.push({
                        title: i18nc("@title:group for section of menu items", "Recent Files"),
                        group: "recents",
                        actions: recents
                    });
                }
            }
        } catch (e) {
            console.warn("[Veronica Overview] Error querying places/recent actions:", e);
        }

        // We always have actions category in KDE Plasma. Filter only non-actions first.
        sections = sections.filter(section => section.actions && section.actions.length > 0);

        // 2. JumpList Actions (e.g. Brave "New Window", "New Incognito Window", Konsole "Open New Window", "Open New Tab")
        try {
            const jumpList = backend.jumpListActions(effectiveUrl, menu);
            sections.push({
                title: i18nc("@title:group for section of menu items", "Actions"),
                group: "actions",
                actions: jumpList || []
            });
        } catch (e) {
            console.warn("[Veronica Overview] Error querying jump list actions:", e);
            sections.push({
                title: i18nc("@title:group for section of menu items", "Actions"),
                group: "actions",
                actions: []
            });
        }

        // C++ backend can override section heading if first element is a QString
        sections.forEach(section => {
            if (typeof section.actions[0] === "string") {
                section.title = section.actions.shift();
            }
        });

        let hasNewWindowAction = false;
        let createdItems = [];

        sections.forEach(section => {
            if (section.actions.length > 0 || section.group === "actions") {
                // Don't add the "Actions" header if the menu has nothing but actions in it (sections.length === 1),
                // but DO add it if there are prior sections (e.g. Places or Recent Files, sections.length > 1)
                if (section.group !== "actions" || sections.length > 1) {
                    let header = wrapper.newMenuItem(menu);
                    header.text = section.title;
                    header.section = true;
                    menu.addMenuItem(header, startNewInstanceItem);
                    createdItems.push(header);
                }

                for (let i = 0; i < section.actions.length; ++i) {
                    const act = section.actions[i];
                    if (!act) continue;

                    let item;
                    if (act.separator || (typeof act.isSeparator === "function" && act.isSeparator())) {
                        item = wrapper.newSeparator(menu);
                    } else {
                        item = wrapper.newMenuItem(menu);
                        item.action = act;

                        if (act.text) {
                            textMetrics.text = act.text.replace("&", "&&");
                            act.text = textMetrics.elidedText;

                            const lower = act.text.toLowerCase();
                            if (lower.indexOf("new window") !== -1 || lower.indexOf("new instance") !== -1) {
                                hasNewWindowAction = true;
                            }
                        }

                        const isMorePlacesAction = (act.icon && String(act.icon).indexOf("view-more") !== -1)
                            || (act.text && act.text.indexOf("more Place") !== -1);

                        const isForgetRecentAction = (act.icon && String(act.icon).indexOf("edit-clear") !== -1)
                            || (act.text && act.text.indexOf("Forget Recent") !== -1);

                        if (!isMorePlacesAction && !isForgetRecentAction) {
                            item.clicked.connect(() => {
                                wrapper.requestDismissOverview();
                            });
                            try {
                                act.triggered.connect(() => {
                                    wrapper.requestDismissOverview();
                                });
                            } catch (_) {}
                        }
                    }

                    menu.addMenuItem(item, startNewInstanceItem);
                    createdItems.push(item);
                }
            }
        });

        // 3. Media Player Controls (shown whenever media is actively playing or paused)
        let playerData = wrapper.targetPlayer;
        if (!playerData) {
            let urlsToTry = [];
            if (wrapper.launcherUrl && String(wrapper.launcherUrl).length > 0) {
                urlsToTry.push(wrapper.launcherUrl);
            }
            if (effectiveUrl && String(effectiveUrl).length > 0 && urlsToTry.indexOf(effectiveUrl) === -1) {
                urlsToTry.push(effectiveUrl);
            }
            try {
                const dec = backend.tryDecodeApplicationsUrl(effectiveUrl);
                if (dec && String(dec).length > 0 && urlsToTry.indexOf(dec) === -1) {
                    urlsToTry.push(dec);
                }
            } catch (_) {}

            for (let u of urlsToTry) {
                if (!u) continue;
                if (wrapper.appPid > 0) {
                    try {
                        playerData = mpris2Source.playerForLauncherUrl(u, wrapper.appPid);
                        if (playerData) break;
                    } catch (_) {}
                }
                try {
                    playerData = mpris2Source.playerForLauncherUrl(u, 0);
                    if (playerData) break;
                } catch (_) {}
            }
        }

        const hasAudioStreamToDisplay = wrapper.hasAudioStream && (wrapper.playingAudio || wrapper.isAudioMuted);
        const hasMicStreamToDisplay = wrapper.hasMicStream && (wrapper.recordingMic || wrapper.isMicMuted);

        if (playerData && playerData.canControl && !(wrapper.winIdList && wrapper.winIdList.length > 1)) {
            const status = playerData.playbackStatus;
            const isPlaying = status === Mpris.PlaybackStatus.Playing;
            const isPaused = status === Mpris.PlaybackStatus.Paused;

            if (isPlaying || isPaused) {
                let prevItem = wrapper.newMenuItem(menu);
                prevItem.text = i18nc("Play previous track", "Previous Track");
                prevItem.icon = "media-skip-backward";
                prevItem.enabled = Boolean(playerData.canGoPrevious);
                prevItem.clicked.connect(() => {
                    playerData.Previous();
                });
                menu.addMenuItem(prevItem, startNewInstanceItem);
                createdItems.push(prevItem);

                let playPauseItem = wrapper.newMenuItem(menu);
                playPauseItem.text = (isPlaying && playerData.canPause)
                    ? i18nc("Pause playback", "Pause")
                    : i18nc("Start playback", "Play");
                playPauseItem.icon = (isPlaying && playerData.canPause)
                    ? "media-playback-pause"
                    : "media-playback-start";
                playPauseItem.enabled = isPlaying ? Boolean(playerData.canPause) : Boolean(playerData.canPlay);
                playPauseItem.clicked.connect(() => {
                    if (playerData.playbackStatus === Mpris.PlaybackStatus.Playing) {
                        playerData.Pause();
                    } else {
                        playerData.Play();
                    }
                });
                menu.addMenuItem(playPauseItem, startNewInstanceItem);
                createdItems.push(playPauseItem);

                let nextItem = wrapper.newMenuItem(menu);
                nextItem.text = i18nc("Play next track", "Next Track");
                nextItem.icon = "media-skip-forward";
                nextItem.enabled = Boolean(playerData.canGoNext);
                nextItem.clicked.connect(() => {
                    playerData.Next();
                });
                menu.addMenuItem(nextItem, startNewInstanceItem);
                createdItems.push(nextItem);

                let stopItem = wrapper.newMenuItem(menu);
                stopItem.text = i18nc("Stop playback", "Stop");
                stopItem.icon = "media-playback-stop";
                stopItem.enabled = Boolean(playerData.canStop);
                stopItem.clicked.connect(() => {
                    playerData.Stop();
                });
                menu.addMenuItem(stopItem, startNewInstanceItem);
                createdItems.push(stopItem);

                // If no audio or microphone stream follows, add separator after media player controls
                if (!hasAudioStreamToDisplay && !hasMicStreamToDisplay) {
                    let mediaSep = wrapper.newSeparator(menu);
                    menu.addMenuItem(mediaSep, startNewInstanceItem);
                    createdItems.push(mediaSep);
                }
            }
        }

        // 4. Audio Stream Mute/Unmute Control (matches KDE Task Manager ContextMenu.qml)
        if (hasAudioStreamToDisplay) {
            let muteItem = wrapper.newMenuItem(menu);
            muteItem.checkable = true;
            muteItem.checked = wrapper.isAudioMuted;
            muteItem.clicked.connect(() => {
                wrapper.requestToggleMuted();
            });
            muteItem.text = i18nc("@option:check inmenu, no separate unmute action", "Mute Playback");
            muteItem.icon = "audio-volume-muted" + (Qt.application.layoutDirection === Qt.RightToLeft ? "-rtl" : "");
            menu.addMenuItem(muteItem, startNewInstanceItem);
            createdItems.push(muteItem);
        }

        // 5. Microphone Stream Mute/Unmute Control
        if (hasMicStreamToDisplay) {
            let micItem = wrapper.newMenuItem(menu);
            micItem.checkable = true;
            micItem.checked = wrapper.isMicMuted;
            micItem.clicked.connect(() => {
                wrapper.requestToggleMicMuted();
            });
            micItem.text = i18nc("@option:check inmenu, no separate unmute action", "Mute Microphone");
            micItem.icon = "microphone-sensitivity-muted" + (Qt.application.layoutDirection === Qt.RightToLeft ? "-rtl" : "");
            menu.addMenuItem(micItem, startNewInstanceItem);
            createdItems.push(micItem);
        }

        if (hasAudioStreamToDisplay || hasMicStreamToDisplay) {
            let muteSep = wrapper.newSeparator(menu);
            menu.addMenuItem(muteSep, startNewInstanceItem);
            createdItems.push(muteSep);
        }

        wrapper.dynamicItems = createdItems;
        wrapper.hasDuplicateNewWindow = hasNewWindowAction;
    }

    function prepareMenu() {
        wrapper.loadDynamicActions();
        // Query desktops count
        const ids = (desktopInfo.desktopIds && desktopInfo.desktopIds.length > 0)
            ? desktopInfo.desktopIds
            : (wrapper.desktopIds || []);
        const names = (desktopInfo.desktopNames && desktopInfo.desktopNames.length > 0)
            ? desktopInfo.desktopNames
            : [];
        const numDesktops = Math.max(
            desktopInfo.numberOfDesktops || 0,
            ids.length,
            names.length,
            wrapper.desktopCount || 0
        );

        // Decide whether to display "Move to Desktop"
        const canMoveDesktops = wrapper.isVirtualDesktopsChangeable && numDesktops > 1;
        virtualDesktopsMenuItem.visible = canMoveDesktops;

        // Query activities count
        const running = (activityInfo.runningActivities ? activityInfo.runningActivities() : []) || [];
        const numActivities = Math.max(
            activityInfo.numberOfRunningActivities || 0,
            running.length
        );

        // Decide whether to display "Show in Activities"
        const canShowActivities = numActivities > 1;
        activitiesMenuItem.visible = canShowActivities;

        // Immediately populate or clear submenus
        if (canMoveDesktops) {
            virtualDesktopsMenuItem._virtualDesktopsMenu.refresh(ids, names);
        } else {
            virtualDesktopsMenuItem._virtualDesktopsMenu.clearMenuItems();
        }

        if (canShowActivities) {
            activitiesMenuItem._activitiesMenu.refresh(running);
        } else {
            activitiesMenuItem._activitiesMenu.clearMenuItems();
        }
    }

    function popup(visualParentItem, x, y) {
        menu.visualParent = visualParentItem;
        wrapper.currentVisualParent = visualParentItem;

        if (x !== undefined && y !== undefined) {
            wrapper.hasExplicitPos = true;
            wrapper.currentX = x;
            wrapper.currentY = y;
        } else {
            wrapper.hasExplicitPos = false;
        }

        wrapper.showAllPlaces = false;

        // The moment before the context menu appears: decide whether to show submenus
        wrapper.prepareMenu();

        if (wrapper.hasExplicitPos) {
            menu.open(Math.round(x), Math.round(y));
        } else {
            menu.openRelative();
        }
    }

    function closeMenu() {
        menu.close();
    }

    PlasmaExtras.Menu {
        id: menu
        minimumWidth: Kirigami.Units.gridUnit * 12

        onStatusChanged: {
            if (status === PlasmaExtras.Menu.Open) {
                if (virtualDesktopsMenuItem.visible) {
                    virtualDesktopsMenuItem._virtualDesktopsMenu.refresh();
                }
                if (activitiesMenuItem.visible) {
                    activitiesMenuItem._activitiesMenu.refresh();
                }
            } else if (status === PlasmaExtras.Menu.Closed) {
                wrapper.clearDynamicItems();
                wrapper.showAllPlaces = false;
            }
        }

        // 1. Open New Window / Start New Instance (if supported and not already in jump list)
        PlasmaExtras.MenuItem {
            id: startNewInstanceItem
            visible: wrapper.canLaunchNewInstance && !wrapper.hasDuplicateNewWindow
            text: i18n("Open New Window")
            icon: "window-new"
            onClicked: {
                wrapper.requestNewInstance();
                wrapper.requestDismissOverview();
            }
        }

        // 2. Move to Desktop Submenu
        PlasmaExtras.MenuItem {
            id: virtualDesktopsMenuItem
            text: i18n("Move to &Desktop")
            icon: "virtual-desktops"
            visible: desktopInfo.numberOfDesktops > 1

            readonly property PlasmaExtras.Menu _virtualDesktopsMenu: PlasmaExtras.Menu {
                id: virtualDesktopsMenu
                visualParent: virtualDesktopsMenuItem.action
                minimumWidth: Kirigami.Units.gridUnit * 12

                function refresh(desks, deskNames) {
                    clearMenuItems();
                    if (!virtualDesktopsMenuItem.visible) return;

                    // Move To Current Desktop
                    const currentDesk = desktopInfo.currentDesktop;
                    const isCurrent = currentDesk && (wrapper.virtualDesktops || []).map(String).indexOf(String(currentDesk)) > -1;
                    let item = wrapper.newMenuItem(virtualDesktopsMenu);
                    item.text = i18n("Move &To Current Desktop");
                    item.enabled = currentDesk && !isCurrent;
                    item.clicked.connect(() => {
                        if (desktopInfo.currentDesktop) {
                            wrapper.requestVirtualDesktops([desktopInfo.currentDesktop]);
                        }
                    });
                    virtualDesktopsMenu.addMenuItem(item);

                    // All Desktops
                    item = wrapper.newMenuItem(virtualDesktopsMenu);
                    item.text = i18n("&All Desktops");
                    item.checkable = true;
                    item.checked = wrapper.isOnAllDesktops;
                    item.clicked.connect(() => {
                        wrapper.requestVirtualDesktops([]);
                    });
                    virtualDesktopsMenu.addMenuItem(item);

                    virtualDesktopsMenu.addMenuItem(wrapper.newSeparator(virtualDesktopsMenu));

                    // Individual Desktops
                    const ids = (desks && desks.length > 0) ? desks : (desktopInfo.desktopIds || []);
                    const names = (deskNames && deskNames.length > 0) ? deskNames : (desktopInfo.desktopNames || []);
                    for (let i = 0; i < ids.length; ++i) {
                        const deskId = ids[i];
                        const deskName = (names && names[i]) || i18n("Desktop %1", i + 1);
                        item = wrapper.newMenuItem(virtualDesktopsMenu);
                        item.text = deskName;
                        item.checkable = true;
                        item.checked = !wrapper.isOnAllDesktops && (wrapper.virtualDesktops || []).map(String).indexOf(String(deskId)) > -1;
                        item.clicked.connect(() => {
                            wrapper.requestVirtualDesktops([deskId]);
                        });
                        virtualDesktopsMenu.addMenuItem(item);
                    }

                    virtualDesktopsMenu.addMenuItem(wrapper.newSeparator(virtualDesktopsMenu));

                    // New Desktop
                    item = wrapper.newMenuItem(virtualDesktopsMenu);
                    item.text = i18n("&New Desktop");
                    item.icon = "list-add";
                    item.clicked.connect(() => {
                        wrapper.requestNewVirtualDesktop();
                    });
                    virtualDesktopsMenu.addMenuItem(item);
                }
            }
        }

        // 3. Show in Activities Submenu (strictly only when more than 1 activity exists)
        PlasmaExtras.MenuItem {
            id: activitiesMenuItem
            text: i18n("Show in &Activities")
            icon: "activities"
            visible: activityInfo.numberOfRunningActivities > 1

            readonly property PlasmaExtras.Menu _activitiesMenu: PlasmaExtras.Menu {
                id: activitiesMenu
                visualParent: activitiesMenuItem.action
                minimumWidth: Kirigami.Units.gridUnit * 12

                function refresh(runningParam) {
                    clearMenuItems();
                    if (!activitiesMenuItem.visible) return;

                    const curAct = activityInfo.currentActivity;
                    const acts = wrapper.activities || [];

                    // Add to Current Activity
                    let item = wrapper.newMenuItem(activitiesMenu);
                    item.text = i18n("Add To Current Activity");
                    item.enabled = acts.length > 0 && acts.map(String).indexOf(String(curAct)) < 0;
                    item.clicked.connect(() => {
                        const current = (wrapper.activities || []).slice();
                        current.push(curAct);
                        wrapper.requestActivities(current);
                    });
                    activitiesMenu.addMenuItem(item);

                    // All Activities
                    item = wrapper.newMenuItem(activitiesMenu);
                    item.text = i18n("All Activities");
                    item.checkable = true;
                    item.checked = acts.length === 0;
                    item.clicked.connect(() => {
                        if (acts.length === 0) {
                            wrapper.requestActivities([curAct]);
                        } else {
                            wrapper.requestActivities([]);
                        }
                    });
                    activitiesMenu.addMenuItem(item);

                    activitiesMenu.addMenuItem(wrapper.newSeparator(activitiesMenu));

                    // Running Activities
                    const running = (runningParam && runningParam.length > 0)
                        ? runningParam
                        : ((activityInfo.runningActivities ? activityInfo.runningActivities() : []) || []);
                    for (let i = 0; i < running.length; ++i) {
                        const actId = running[i];
                        item = wrapper.newMenuItem(activitiesMenu);
                        item.text = activityInfo.activityName(actId) || i18n("Activity %1", i + 1);
                        item.icon = activityInfo.activityIcon(actId) || "activities";
                        item.checkable = true;
                        item.checked = acts.length === 0 || acts.map(String).indexOf(String(actId)) >= 0;
                        item.clicked.connect(() => {
                            let current = (wrapper.activities || []).slice();
                            const sId = String(actId);
                            const idx = current.map(String).indexOf(sId);
                            if (idx >= 0) {
                                current.splice(idx, 1);
                            } else {
                                current.push(actId);
                            }
                            wrapper.requestActivities(current);
                        });
                        activitiesMenu.addMenuItem(item);
                    }

                    activitiesMenu.addMenuItem(wrapper.newSeparator(activitiesMenu));

                    // Move to Activity
                    for (let j = 0; j < running.length; ++j) {
                        const actId = running[j];
                        if (acts.length === 1 && String(acts[0]) === String(actId)) {
                            continue;
                        }
                        item = wrapper.newMenuItem(activitiesMenu);
                        item.text = i18n("Move to %1", activityInfo.activityName(actId) || i18n("Activity %1", j + 1));
                        item.icon = activityInfo.activityIcon(actId) || "activities";
                        item.clicked.connect(() => {
                            wrapper.requestActivities([actId]);
                        });
                        activitiesMenu.addMenuItem(item);
                    }
                }
            }
        }

        // 4. More Submenu (Matches KDE Plasma "More")
        PlasmaExtras.MenuItem {
            id: moreMenuItem
            text: i18n("More")
            icon: "view-more-symbolic"

            readonly property PlasmaExtras.Menu _moreMenu: PlasmaExtras.Menu {
                id: moreMenu
                visualParent: moreMenuItem.action
                minimumWidth: Kirigami.Units.gridUnit * 12

                PlasmaExtras.MenuItem {
                    enabled: wrapper.isMovable
                    text: i18n("&Move")
                    icon: "transform-move"
                    onClicked: wrapper.requestMove()
                }

                PlasmaExtras.MenuItem {
                    enabled: wrapper.isResizable
                    text: i18n("Re&size")
                    icon: "transform-scale"
                    onClicked: wrapper.requestResize()
                }

                PlasmaExtras.MenuItem {
                    enabled: wrapper.isMaximizable
                    checkable: true
                    checked: wrapper.isMaximized
                    text: i18n("Ma&ximize")
                    icon: "window-maximize"
                    onClicked: wrapper.requestToggleMaximized()
                }

                PlasmaExtras.MenuItem {
                    enabled: wrapper.isMinimizable
                    checkable: true
                    checked: wrapper.isMinimized
                    text: i18n("Mi&nimize")
                    icon: "window-minimize"
                    onClicked: wrapper.requestToggleMinimized()
                }

                PlasmaExtras.MenuItem {
                    checkable: true
                    checked: wrapper.isKeepAbove
                    text: i18n("Keep &Above Others")
                    icon: "window-keep-above"
                    onClicked: wrapper.requestToggleKeepAbove()
                }

                PlasmaExtras.MenuItem {
                    checkable: true
                    checked: wrapper.isKeepBelow
                    text: i18n("Keep &Below Others")
                    icon: "window-keep-below"
                    onClicked: wrapper.requestToggleKeepBelow()
                }

                PlasmaExtras.MenuItem {
                    enabled: wrapper.isFullScreenable
                    checkable: true
                    checked: wrapper.isFullScreen
                    text: i18n("&Fullscreen")
                    icon: "view-fullscreen"
                    onClicked: wrapper.requestToggleFullScreen()
                }

                PlasmaExtras.MenuItem {
                    enabled: wrapper.isShadeable
                    visible: Qt.platform.pluginName !== "wayland"
                    checkable: true
                    checked: wrapper.isShaded
                    text: i18n("&Shade")
                    icon: "window-shade"
                    onClicked: wrapper.requestToggleShaded()
                }

                PlasmaExtras.MenuItem {
                    enabled: wrapper.canSetNoBorder
                    checkable: true
                    checked: wrapper.hasNoBorder
                    text: i18n("&No Titlebar and Frame")
                    icon: "edit-none-border"
                    onClicked: wrapper.requestToggleNoBorder()
                }

                PlasmaExtras.MenuItem {
                    visible: Qt.platform.pluginName === "wayland"
                    checkable: true
                    checked: wrapper.isExcludedFromCapture
                    text: i18n("&Hide from Screencast")
                    icon: "view-private"
                    onClicked: wrapper.requestToggleExcludeFromCapture()
                }
            }
        }

        PlasmaExtras.MenuItem {
            separator: true
        }

        // 5. Close Window
        PlasmaExtras.MenuItem {
            enabled: wrapper.isClosable
            text: i18n("&Close")
            icon: "window-close"
            onClicked: wrapper.requestClose()
        }
    }
}
