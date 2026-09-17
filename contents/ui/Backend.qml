import QtQuick

QtObject {
    id: root

    enum MiddleClickAction {
        None = 0,
        Close = 1,
        NewInstance = 2,
        ToggleMinimized = 3,
        ToggleGrouping = 4,
        BringToCurrentDesktop = 5
    }

    signal showAllPlaces()
    signal addLauncher(url url)

    function globalRect(item) {
        if (!item) {
            return Qt.rect(0, 0, 0, 0);
        }
        try {
            const pos = item.mapToGlobal(0, 0);
            return Qt.rect(pos.x, pos.y, item.width, item.height);
        } catch (e) {
            return Qt.rect(0, 0, item.width || 0, item.height || 0);
        }
    }

    function isApplication(url) {
        if (!url) return false;
        const s = url.toString();
        return s.startsWith("applications:") || s.endsWith(".desktop");
    }

    function tryDecodeApplicationsUrl(url) {
        return url;
    }

    function applicationCategories(launcherUrl) {
        return [];
    }

    function placesActions(launcherUrl, showAll, parent) {
        return [];
    }

    function recentDocumentActions(launcherUrl, parent) {
        return [];
    }

    function jumpListActions(launcherUrl, parent) {
        return [];
    }

    function setActionGroup(action) {
        // no-op
    }

    function parentPid(pid) {
        return 0;
    }
}
