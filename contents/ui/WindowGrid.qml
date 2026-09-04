import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

Item {
    id: pageRoot

    required property var desktopId
    required property int pageIndex
    required property bool isCurrentPage

    property bool showCloseButtons: true
    property int cardRadius: 14
    property bool overviewOpen: false
    property int draggedTaskIndex: -1
    property int layoutRefreshTick: 0
    property var lastActiveWinId: null

    signal taskActivated()
    signal taskClosed()
    signal emptyAreaClicked()
    signal windowDragStarted(int pageIndex, int taskRow, var winIds, string title, var icon, string appName, real cardW, real cardH, real aspect, real globalOriginX, real globalOriginY, real grabX, real grabY)
    signal windowDragMoved(real globalX, real globalY)
    signal windowDragEnded(real globalX, real globalY)
    signal windowDragCanceled()

    function moveTaskToDesktop(taskRow, targetDesktopId) {
        if (taskRow >= 0 && taskRow < pageTasksModel.count) {
            pageTasksModel.requestVirtualDesktops(pageTasksModel.makeModelIndex(taskRow), [targetDesktopId]);
        }
        pageRoot.draggedTaskIndex = -1;
    }

    function cancelDrag() {
        pageRoot.draggedTaskIndex = -1;
    }

    function activateTask(taskRow) {
        if (taskRow >= 0 && taskRow < pageTasksModel.count) {
            pageTasksModel.requestActivate(pageTasksModel.makeModelIndex(taskRow));
        }
        pageRoot.taskActivated();
    }

    function closeTask(taskRow) {
        if (taskRow >= 0 && taskRow < pageTasksModel.count) {
            pageTasksModel.requestClose(pageTasksModel.makeModelIndex(taskRow));
        }
        pageRoot.taskClosed();
    }

    TaskManager.ActivityInfo {
        id: pageActivityInfo
    }

    TaskManager.TasksModel {
        id: pageTasksModel
        filterByVirtualDesktop: true
        virtualDesktop: pageRoot.desktopId
        filterByCurrentVirtualDesktop: false
        filterByActivity: true
        activity: pageActivityInfo.currentActivity
        filterByScreen: false
        filterHidden: false
        filterMinimized: false
        filterNotMinimized: false
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortLastActivated

        onCountChanged: {
            if (pageRoot.isCurrentPage) {
                pageRoot.updateDefaultSelection();
            }
        }
    }

    property int selectedIndex: -1

    onIsCurrentPageChanged: {
        if (isCurrentPage) {
            updateDefaultSelection();
        } else {
            windowContextMenu.closeMenu();
        }
    }

    onOverviewOpenChanged: {
        if (overviewOpen && isCurrentPage) {
            updateDefaultSelection();
        } else if (!overviewOpen) {
            windowContextMenu.closeMenu();
        }
    }

    onLastActiveWinIdChanged: {
        if (isCurrentPage) {
            updateDefaultSelection();
        }
    }

    function updateDefaultSelection() {
        if (pageTasksModel.count <= 0) {
            selectedIndex = -1;
            return;
        }
        selectedIndex = 0;
    }

    function clearSelection() {
        selectedIndex = -1;
    }

    function navigateSelection(dx, dy) {
        if (windowCount <= 0) return "no_windows";
        if (selectedIndex < 0) {
            updateDefaultSelection();
            return "selected";
        }

        if (dx !== 0) {
            let target = selectedIndex + dx;
            if (target >= 0 && target < windowCount) {
                selectedIndex = target;
                return "moved";
            }
        } else if (dy !== 0) {
            const r = Math.floor(selectedIndex / cols);
            const c = selectedIndex % cols;

            if (dy < 0 && r === 0) {
                return "above_top";
            }

            let newR = r + dy;
            if (newR >= 0 && newR < rowCount) {
                let target = (newR * cols) + c;
                if (target >= windowCount) {
                    target = windowCount - 1;
                }
                selectedIndex = target;
                return "moved";
            }
        }
        return "at_boundary";
    }

    function activateSelected() {
        if (selectedIndex >= 0 && selectedIndex < windowCount) {
            activateTask(selectedIndex);
        }
    }

    readonly property int windowCount: pageTasksModel.count
    readonly property real spacing: Math.max(12, Math.min(20, (pageRoot.width / 100)))

    // Dynamic aspect-ratio-aware column calculation - NO hardcoded column limit!
    readonly property int cols: {
        if (windowCount <= 1) return 1;
        if (windowCount === 2) return 2;
        if (windowCount <= 4) return 2;
        if (windowCount <= 6) return 3;

        // For N >= 7: calculate optimal columns to fill the viewport aspect ratio
        const vAspect = Math.max(1.0, (pageRoot.width - 48) / Math.max(100, pageRoot.height - 36));
        const targetAspect = vAspect / 1.55;
        const optCols = Math.round(Math.sqrt(windowCount * targetAspect));
        return Math.max(2, optCols);
    }

    readonly property int rowCount: Math.max(1, Math.ceil(windowCount / cols))

    readonly property real availW: Math.max(100, pageRoot.width - (spacing * (cols + 1)) - 32)
    readonly property real availH: Math.max(100, pageRoot.height - (spacing * (rowCount + 1)) - 24)

    // Slot bounds fill the entire available grid space across all columns and rows
    readonly property real slotWidth: {
        const base = (availW - (spacing * (cols - 1))) / cols;
        if (windowCount === 1) return Math.min(base, pageRoot.width * 0.70);
        return base;
    }

    readonly property real slotHeight: {
        const base = (availH - (spacing * (rowCount - 1))) / rowCount;
        if (windowCount === 1) return Math.min(base, pageRoot.height * 0.75);
        return base;
    }

    // Exact non-preview dimensions inside WindowCard:
    // Horizontal: 6px left margin + 6px right margin = 12px
    // Vertical: 6px top margin + 24px header + 4px spacing + 6px bottom margin = 40px
    readonly property real nonPreviewW: 12
    readonly property real nonPreviewH: 40

    function extractSize(geom) {
        if (!geom) return null;
        try {
            if (typeof geom.width === "number" && typeof geom.height === "number" && geom.width > 10 && geom.height > 10) {
                return { width: geom.width, height: geom.height };
            }
            if (typeof geom.width === "function" && typeof geom.height === "function") {
                const w = geom.width();
                const h = geom.height();
                if (w > 10 && h > 10) return { width: w, height: h };
            }
            if (typeof geom === "string") {
                const m = geom.match(/(\d+)\s*[x,]\s*(\d+)/);
                if (m && m.length >= 3) {
                    const w = parseInt(m[1]);
                    const h = parseInt(m[2]);
                    if (w > 10 && h > 10) return { width: w, height: h };
                }
            }
        } catch (e) {}
        return null;
    }

    function getCardWidthForAspect(aspect) {
        const a = (aspect > 0) ? aspect : ((Screen.width > 0 && Screen.height > 0) ? (Screen.width / Screen.height) : 1.6);
        const maxPW = Math.max(16, pageRoot.slotWidth - pageRoot.nonPreviewW);
        const maxPH = Math.max(16, pageRoot.slotHeight - pageRoot.nonPreviewH);
        const slotAspect = maxPW / maxPH;

        if (a >= slotAspect) {
            return Math.max(24, Math.round(maxPW + pageRoot.nonPreviewW));
        } else {
            const pW = Math.round(maxPH * a);
            return Math.max(24, Math.round(pW + pageRoot.nonPreviewW));
        }
    }

    function getCardHeightForAspect(aspect) {
        const a = (aspect > 0) ? aspect : ((Screen.width > 0 && Screen.height > 0) ? (Screen.width / Screen.height) : 1.6);
        const maxPW = Math.max(16, pageRoot.slotWidth - pageRoot.nonPreviewW);
        const maxPH = Math.max(16, pageRoot.slotHeight - pageRoot.nonPreviewH);
        const slotAspect = maxPW / maxPH;

        if (a >= slotAspect) {
            const pH = Math.round(maxPW / a);
            return Math.max(24, Math.round(pH + pageRoot.nonPreviewH));
        } else {
            return Math.max(24, Math.round(maxPH + pageRoot.nonPreviewH));
        }
    }

    function getCardWidthAtIndex(i) {
        if (cardsRepeater && i >= 0 && i < cardsRepeater.count) {
            const it = cardsRepeater.itemAt(i);
            if (it && it.cardW > 0) return it.cardW;
        }
        return pageRoot.slotWidth;
    }

    function getRowMetrics(rIndex) {
        const _tick = pageRoot.layoutRefreshTick;
        const startIdx = rIndex * pageRoot.cols;
        const endIdx = Math.min(pageRoot.windowCount, (rIndex + 1) * pageRoot.cols);
        const count = Math.max(0, endIdx - startIdx);
        if (count === 0) return { totalWidth: 0, startX: pageRoot.width / 2, offsets: [] };

        const widths = [];
        let sumW = 0;
        for (let i = startIdx; i < endIdx; i++) {
            const w = pageRoot.getCardWidthAtIndex(i);
            widths.push(w);
            sumW += w;
        }
        const totalW = sumW + ((count - 1) * pageRoot.spacing);
        const startX = Math.max(16, (pageRoot.width - totalW) / 2);

        const offsets = [];
        let curX = startX;
        for (let j = 0; j < count; j++) {
            offsets.push(curX);
            curX += widths[j] + pageRoot.spacing;
        }
        return { totalWidth: totalW, startX: startX, offsets: offsets };
    }

    // Dismiss click area covering entire background of the page
    MouseArea {
        id: pageBgClickArea
        anchors.fill: parent
        z: -1
        onClicked: pageRoot.emptyAreaClicked()
        onWheel: wheel => {
            wheel.accepted = false;
        }
    }

    // Centered window cards container
    Item {
        id: cardsContainer
        anchors.fill: parent
        visible: pageRoot.windowCount > 0

        readonly property real totalGridHeight: (pageRoot.rowCount * pageRoot.slotHeight) + ((pageRoot.rowCount - 1) * pageRoot.spacing)
        readonly property real gridStartY: Math.max(0, (pageRoot.height - totalGridHeight) / 2)

        Repeater {
            id: cardsRepeater
            model: pageTasksModel

            delegate: Item {
                id: cellItem
                required property int index
                required property var model

                property real customAspect: 0

                readonly property string itemTitle: model.display ? String(model.display).trim() : ""
                readonly property string itemAppId: model.AppId ? String(model.AppId).trim() : ""
                readonly property bool isSelf: itemTitle === "Veronica Overview" || itemAppId === "stakillion.veronica.overview" || Boolean(model.SkipTaskbar) || Boolean(model.SkipPager)
                readonly property var itemIcon: model.decoration ? model.decoration : "application-x-executable"
                readonly property string itemAppName: model.AppName ? String(model.AppName).trim() : (model.GenericName ? String(model.GenericName).trim() : "")
                readonly property var itemWinIds: model.WinIdList ? model.WinIdList : []
                readonly property bool itemIsActive: Boolean(model.IsActive)
                readonly property bool itemIsMinimized: Boolean(model.IsMinimized)
                readonly property bool itemIsMaximized: Boolean(model.IsMaximized)
                readonly property bool itemIsKeepAbove: Boolean(model.IsKeepAbove)
                readonly property bool itemIsKeepBelow: Boolean(model.IsKeepBelow)
                readonly property bool itemIsFullScreen: Boolean(model.IsFullScreen)
                readonly property bool itemIsShaded: Boolean(model.IsShaded)
                readonly property bool itemIsOnAllDesktops: Boolean(model.IsOnAllVirtualDesktops)
                readonly property bool itemCanLaunchNewInstance: Boolean(model.CanLaunchNewInstance)
                readonly property bool itemIsClosable: model.IsClosable !== undefined ? Boolean(model.IsClosable) : true
                readonly property bool itemIsMovable: Boolean(model.IsMovable)
                readonly property bool itemIsResizable: Boolean(model.IsResizable)
                readonly property bool itemIsMaximizable: model.IsMaximizable !== undefined ? Boolean(model.IsMaximizable) : true
                readonly property bool itemIsMinimizable: model.IsMinimizable !== undefined ? Boolean(model.IsMinimizable) : true
                readonly property bool itemIsFullScreenable: model.IsFullScreenable !== undefined ? Boolean(model.IsFullScreenable) : true
                readonly property bool itemIsShadeable: Boolean(model.IsShadeable)
                readonly property bool itemHasNoBorder: Boolean(model.HasNoBorder)
                readonly property bool itemCanSetNoBorder: Boolean(model.CanSetNoBorder)
                readonly property bool itemIsExcludedFromCapture: Boolean(model.IsExcludedFromCapture)
                readonly property var itemVirtualDesktops: model.VirtualDesktops || []
                readonly property var itemActivities: model.Activities || []
                readonly property var itemGeom: model.Geometry

                visible: !isSelf

                readonly property real effectiveAspect: {
                    if (customAspect > 0) return customAspect;
                    const s = pageRoot.extractSize(cellItem.itemGeom);
                    if (s) return s.width / s.height;
                    return (Screen.width > 0 && Screen.height > 0) ? (Screen.width / Screen.height) : 1.6;
                }

                readonly property real cardW: pageRoot.getCardWidthForAspect(effectiveAspect)
                readonly property real cardH: pageRoot.getCardHeightForAspect(effectiveAspect)

                onCardWChanged: {
                    pageRoot.layoutRefreshTick++;
                    if (pageRoot.overviewOpen && pageRoot.isCurrentPage && cardW > 0 && cardH > 0) {
                        const mIdx = pageTasksModel.makeModelIndex(cellItem.index);
                        if (mIdx.valid) {
                            const globalPos = cellItem.mapToItem(null, 0, 0);
                            pageTasksModel.requestPublishDelegateGeometry(mIdx, Qt.rect(globalPos.x, globalPos.y, cardW, cardH), cellItem);
                        }
                    }
                }

                readonly property int rowIndex: Math.floor(cellItem.index / pageRoot.cols)
                readonly property int colIndex: cellItem.index % pageRoot.cols
                readonly property var rowMetrics: pageRoot.getRowMetrics(rowIndex)

                x: (rowMetrics && Array.isArray(rowMetrics.offsets) && colIndex < rowMetrics.offsets.length && rowMetrics.offsets[colIndex] !== undefined) ? rowMetrics.offsets[colIndex] : Math.max(16, (pageRoot.width - cardW) / 2)
                y: cardsContainer.gridStartY + (rowIndex * (pageRoot.slotHeight + pageRoot.spacing)) + (pageRoot.slotHeight - cardH) / 2
                width: cardW
                height: cardH

                WindowCard {
                    anchors.fill: parent

                    targetModelIndex: cellItem.index
                    itemIndex: cellItem.index
                    overviewOpen: pageRoot.overviewOpen && pageRoot.isCurrentPage
                    isMinimized: cellItem.itemIsMinimized
                    windowTitle: cellItem.itemTitle
                    windowIcon: cellItem.itemIcon
                    appLabel: cellItem.itemAppName
                    isActive: cellItem.index === pageRoot.selectedIndex
                    winIds: cellItem.itemWinIds
                    windowGeometry: cellItem.itemGeom

                    itemRadius: pageRoot.windowCount > 8 ? 8 : pageRoot.cardRadius
                    isBeingDragged: pageRoot.draggedTaskIndex === cellItem.index
                    showTitle: true
                    showCloseButton: pageRoot.showCloseButtons

                    onAspectDiscovered: asp => {
                        cellItem.customAspect = asp;
                    }

                    onActivated: pageRoot.activateTask(cellItem.index)
                    onSelected: pageRoot.selectedIndex = cellItem.index
                    onClosed: pageRoot.closeTask(cellItem.index)
                    onContextMenuRequested: (mx, my, visualParent) => {
                        pageRoot.showWindowContextMenu(cellItem, mx, my, visualParent);
                    }

                    onDragStarted: (originX, originY, grabX, grabY) => {
                        pageRoot.draggedTaskIndex = cellItem.index;
                        pageRoot.windowDragStarted(pageRoot.pageIndex, cellItem.index, cellItem.itemWinIds, cellItem.itemTitle, cellItem.itemIcon, cellItem.itemAppName, cellItem.width, cellItem.height, cellItem.effectiveAspect, originX, originY, grabX, grabY);
                    }
                    onDragMoved: (gx, gy) => pageRoot.windowDragMoved(gx, gy)
                    onDragEnded: (gx, gy) => pageRoot.windowDragEnded(gx, gy)
                    onDragCanceled: {
                        pageRoot.draggedTaskIndex = -1;
                        pageRoot.windowDragCanceled();
                    }
                }
            }
        }
    }

    // Shared context menu instance for all cards on this page
    property int contextMenuTaskIndex: -1

    WindowContextMenu {
        id: windowContextMenu

        onRequestNewInstance: {
            if (contextMenuTaskIndex >= 0) pageTasksModel.requestNewInstance(pageTasksModel.makeModelIndex(contextMenuTaskIndex));
        }
        onRequestMove: {
            if (contextMenuTaskIndex >= 0) pageTasksModel.requestMove(pageTasksModel.makeModelIndex(contextMenuTaskIndex));
        }
        onRequestResize: {
            if (contextMenuTaskIndex >= 0) pageTasksModel.requestResize(pageTasksModel.makeModelIndex(contextMenuTaskIndex));
        }
        onRequestToggleMaximized: {
            if (contextMenuTaskIndex >= 0) pageTasksModel.requestToggleMaximized(pageTasksModel.makeModelIndex(contextMenuTaskIndex));
        }
        onRequestToggleMinimized: {
            if (contextMenuTaskIndex >= 0) pageTasksModel.requestToggleMinimized(pageTasksModel.makeModelIndex(contextMenuTaskIndex));
        }
        onRequestToggleKeepAbove: {
            if (contextMenuTaskIndex >= 0) pageTasksModel.requestToggleKeepAbove(pageTasksModel.makeModelIndex(contextMenuTaskIndex));
        }
        onRequestToggleKeepBelow: {
            if (contextMenuTaskIndex >= 0) pageTasksModel.requestToggleKeepBelow(pageTasksModel.makeModelIndex(contextMenuTaskIndex));
        }
        onRequestToggleFullScreen: {
            if (contextMenuTaskIndex >= 0) pageTasksModel.requestToggleFullScreen(pageTasksModel.makeModelIndex(contextMenuTaskIndex));
        }
        onRequestToggleShaded: {
            if (contextMenuTaskIndex >= 0) pageTasksModel.requestToggleShaded(pageTasksModel.makeModelIndex(contextMenuTaskIndex));
        }
        onRequestToggleNoBorder: {
            if (contextMenuTaskIndex >= 0) pageTasksModel.requestToggleNoBorder(pageTasksModel.makeModelIndex(contextMenuTaskIndex));
        }
        onRequestToggleExcludeFromCapture: {
            if (contextMenuTaskIndex >= 0) pageTasksModel.requestToggleExcludeFromCapture(pageTasksModel.makeModelIndex(contextMenuTaskIndex));
        }
        onRequestVirtualDesktops: desks => {
            if (contextMenuTaskIndex >= 0) pageTasksModel.requestVirtualDesktops(pageTasksModel.makeModelIndex(contextMenuTaskIndex), desks);
        }
        onRequestNewVirtualDesktop: {
            if (contextMenuTaskIndex >= 0) pageTasksModel.requestNewVirtualDesktop(pageTasksModel.makeModelIndex(contextMenuTaskIndex));
        }
        onRequestActivities: acts => {
            if (contextMenuTaskIndex >= 0) pageTasksModel.requestActivities(pageTasksModel.makeModelIndex(contextMenuTaskIndex), acts);
        }
        onRequestClose: {
            if (contextMenuTaskIndex >= 0) pageRoot.closeTask(contextMenuTaskIndex);
        }
    }

    function showWindowContextMenu(cell, mouseX, mouseY, visualParent) {
        pageRoot.contextMenuTaskIndex = cell.index;
        windowContextMenu.canLaunchNewInstance = cell.itemCanLaunchNewInstance;
        windowContextMenu.isOnAllDesktops = cell.itemIsOnAllDesktops;
        windowContextMenu.virtualDesktops = cell.itemVirtualDesktops;
        windowContextMenu.activities = cell.itemActivities;
        windowContextMenu.isMovable = cell.itemIsMovable;
        windowContextMenu.isResizable = cell.itemIsResizable;
        windowContextMenu.isMaximizable = cell.itemIsMaximizable;
        windowContextMenu.isMaximized = cell.itemIsMaximized;
        windowContextMenu.isMinimizable = cell.itemIsMinimizable;
        windowContextMenu.isMinimized = cell.itemIsMinimized;
        windowContextMenu.isKeepAbove = cell.itemIsKeepAbove;
        windowContextMenu.isKeepBelow = cell.itemIsKeepBelow;
        windowContextMenu.isFullScreenable = cell.itemIsFullScreenable;
        windowContextMenu.isFullScreen = cell.itemIsFullScreen;
        windowContextMenu.isShadeable = cell.itemIsShadeable;
        windowContextMenu.isShaded = cell.itemIsShaded;
        windowContextMenu.canSetNoBorder = cell.itemCanSetNoBorder;
        windowContextMenu.hasNoBorder = cell.itemHasNoBorder;
        windowContextMenu.isExcludedFromCapture = cell.itemIsExcludedFromCapture;
        windowContextMenu.isClosable = cell.itemIsClosable;

        windowContextMenu.popup(visualParent, mouseX, mouseY);
    }

    // Empty state when workspace has no windows
    Item {
        anchors.centerIn: parent
        visible: pageRoot.windowCount === 0
        width: 320
        height: 180

        MouseArea {
            anchors.fill: parent
            onClicked: pageRoot.emptyAreaClicked()
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 12

            Kirigami.Icon {
                source: "preferences-system-windows"
                implicitWidth: 64
                implicitHeight: 64
                opacity: 0.35
                Layout.alignment: Qt.AlignHCenter
            }

            QQC2.Label {
                text: i18n("No open windows")
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize + 1
                color: Qt.rgba(1, 1, 1, 0.5)
                Layout.alignment: Qt.AlignHCenter
            }

            QQC2.Label {
                text: i18n("Start typing to search and launch apps")
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: Qt.rgba(1, 1, 1, 0.35)
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
