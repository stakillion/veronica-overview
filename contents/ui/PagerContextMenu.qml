import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras
import org.kde.taskmanager as TaskManager
import org.kde.plasma.workspace.dbus as DBus
import org.kde.kcmutils as KCMUtils

Item {
    id: wrapper

    signal desktopAdded()
    signal desktopRemoved()

    TaskManager.VirtualDesktopInfo {
        id: desktopInfo
    }

    function popup(visualParentItem, x, y) {
        menu.visualParent = visualParentItem;
        if (x !== undefined && y !== undefined) {
            menu.open(Math.round(x), Math.round(y));
        } else {
            menu.openRelative();
        }
    }

    function closeMenu() {
        menu.close();
    }

    function addDesktop() {
        const nextIdx = desktopInfo.numberOfDesktops;
        const name = i18n("Desktop %1", nextIdx + 1);
        DBus.SessionBus.asyncCall({
            service: "org.kde.KWin",
            path: "/VirtualDesktopManager",
            iface: "org.kde.KWin.VirtualDesktopManager",
            member: "createDesktop",
            arguments: [nextIdx, name]
        });
        wrapper.desktopAdded();
    }

    function removeDesktop() {
        if (desktopInfo.numberOfDesktops <= 1) return;
        const ids = desktopInfo.desktopIds;
        if (ids && ids.length > 0) {
            const lastId = String(ids[ids.length - 1]);
            DBus.SessionBus.asyncCall({
                service: "org.kde.KWin",
                path: "/VirtualDesktopManager",
                iface: "org.kde.KWin.VirtualDesktopManager",
                member: "removeDesktop",
                arguments: [lastId]
            });
            wrapper.desktopRemoved();
        }
    }

    PlasmaExtras.Menu {
        id: menu
        minimumWidth: Kirigami.Units.gridUnit * 12

        // 1. Add Virtual Desktop
        PlasmaExtras.MenuItem {
            text: i18n("Add Virtual Desktop")
            icon: "list-add"
            onClicked: wrapper.addDesktop()
        }

        // 2. Remove Virtual Desktop (Disabled if only 1 desktop exists)
        PlasmaExtras.MenuItem {
            text: i18n("Remove Virtual Desktop")
            icon: "list-remove"
            enabled: desktopInfo.numberOfDesktops > 1
            onClicked: wrapper.removeDesktop()
        }

        PlasmaExtras.MenuItem {
            separator: true
        }

        // 3. Configure Virtual Desktops...
        PlasmaExtras.MenuItem {
            text: i18n("Configure Virtual Desktops…")
            onClicked: {
                KCMUtils.KCMLauncher.openSystemSettings("kcm_kwin_virtualdesktops");
            }
        }
    }
}
