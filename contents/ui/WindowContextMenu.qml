import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras
import org.kde.taskmanager as TaskManager

Item {
    id: wrapper

    property bool canLaunchNewInstance: false
    property bool isOnAllDesktops: false
    property var virtualDesktops: []
    property var activities: []
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

    function newMenuItem(parentObj) {
        return Qt.createQmlObject('import org.kde.plasma.extras as PlasmaExtras; PlasmaExtras.MenuItem {}', parentObj);
    }

    function newSeparator(parentObj) {
        return Qt.createQmlObject('import org.kde.plasma.extras as PlasmaExtras; PlasmaExtras.MenuItem { separator: true }', parentObj);
    }

    function popup(visualParentItem, x, y) {
        menu.visualParent = visualParentItem;
        if (virtualDesktopsMenuItem.visible) {
            virtualDesktopsMenuItem._virtualDesktopsMenu.refresh();
        }
        if (activitiesMenuItem.visible) {
            activitiesMenuItem._activitiesMenu.refresh();
        }
        if (x !== undefined && y !== undefined) {
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
            }
        }

        // 1. Open New Window / Start New Instance (if supported)
        PlasmaExtras.MenuItem {
            visible: wrapper.canLaunchNewInstance
            text: i18n("Open New Window")
            icon: "window-new"
            onClicked: wrapper.requestNewInstance()
        }

        PlasmaExtras.MenuItem {
            separator: true
            visible: wrapper.canLaunchNewInstance
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

                function refresh() {
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
                    const ids = desktopInfo.desktopIds || [];
                    const names = desktopInfo.desktopNames || [];
                    for (let i = 0; i < ids.length; ++i) {
                        const deskId = ids[i];
                        const deskName = names[i] || i18n("Desktop %1", i + 1);
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

                function refresh() {
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
                    const running = activityInfo.runningActivities() || [];
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
                }
            }
        }

        PlasmaExtras.MenuItem {
            separator: true
            visible: virtualDesktopsMenuItem.visible || activitiesMenuItem.visible
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
