import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import org.kde.plasma.private.mpris as Mpris

Item {
    id: pageRoot

    required property var desktopId
    required property int pageIndex
    required property bool isCurrentPage

    property int desktopCount: 1
    property var desktopIds: []
    property var pulseAudio: null

    Mpris.Mpris2Model {
        id: gridMprisSource
    }
    readonly property var mprisSource: gridMprisSource

    property bool showCloseButtons: true
    property bool alternateCardStyle: false
    property int alternateCardIconSize: 64
    property int cardRadius: 14
    property bool overviewOpen: false
    property int draggedTaskIndex: -1
    property int layoutRefreshTick: 0
    property var lastActiveWinId: null

    signal taskActivated(var activationCallback)
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
            const targetIndex = pageTasksModel.makeModelIndex(taskRow);
            pageRoot.taskActivated(() => {
                if (targetIndex && targetIndex.valid) {
                    pageTasksModel.requestActivate(targetIndex);
                } else if (taskRow >= 0 && taskRow < pageTasksModel.count) {
                    pageTasksModel.requestActivate(pageTasksModel.makeModelIndex(taskRow));
                }
            });
        } else {
            pageRoot.taskActivated(null);
        }
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

    // Standard grid spacing
    readonly property real spacing: Math.max(12, Math.min(20, Math.round(pageRoot.width / 100)))
    readonly property real colSpacing: pageRoot.spacing

    // Dynamic aspect-ratio-aware grid solver:
    // - Based completely on actual available viewport space (width & height)
    // - Maximizes card size while filling both horizontal and vertical space
    // - Special constraint: 3 cards are always 2 rows, 1.5 columns (Row 0: 2, Row 1: 1)
    readonly property int cols: {
        if (windowCount <= 1) return 1;
        if (windowCount === 2) return (pageRoot.width >= pageRoot.height) ? 2 : 1;
        if (windowCount === 3) return 2; // Always 2 rows, 1.5 columns (2 on top, 1 on bottom)

        const W = Math.max(200, pageRoot.width - 32);
        const H = Math.max(200, pageRoot.height - 32);

        // Determine average aspect ratio of windows on this workspace
        let sumAsp = 0;
        let validAspCount = 0;
        for (let i = 0; i < pageRoot.windowCount; i++) {
            const a = pageRoot.getAspectAtIndex(i);
            if (a > 0.5 && a < 3.5) {
                sumAsp += a;
                validAspCount++;
            }
        }
        const avgAspect = validAspCount > 0 ? (sumAsp / validAspCount) : ((Screen.width > 0 && Screen.height > 0) ? (Screen.width / Screen.height) : 1.65);

        let bestScore = -1;
        let bestCols = 2;

        // Evaluate all possible row counts R and select the (R, C) layout that
        // maximizes card area while filling as much vertical and horizontal space as possible
        const maxRows = Math.min(pageRoot.windowCount, 8);
        for (let R = 1; R <= maxRows; R++) {
            const C = Math.ceil(pageRoot.windowCount / R);
            if (C < 1) continue;
            // Prevent single-row ribbon on non-ultrawide viewports for N >= 4
            if (R === 1 && pageRoot.windowCount >= 4 && W < H * 2.8) continue;

            const maxColW = (W - (C - 1) * pageRoot.colSpacing) / C;
            const maxRowH = (H - (R - 1) * pageRoot.spacing) / R;
            if (maxColW < 90 || maxRowH < 70) continue;

            const pH_h = maxRowH - pageRoot.nonPreviewH;
            const pH_w = (maxColW - pageRoot.nonPreviewW) / avgAspect;
            const pH = Math.min(pH_h, pH_w);
            if (pH < 20) continue;

            const cardH = pH + pageRoot.nonPreviewH;
            const cardW = pH * avgAspect + pageRoot.nonPreviewW;

            const usedH = R * cardH + (R - 1) * pageRoot.spacing;
            const widestK = Math.min(C, pageRoot.windowCount);
            const usedW = widestK * cardW + (widestK - 1) * pageRoot.colSpacing;

            const fillH = Math.min(1.0, usedH / H);
            const fillW = Math.min(1.0, usedW / W);

            // Objective function: maximize card size while strongly rewarding full screen coverage (both vertical & horizontal)
            const totalCardSpace = pageRoot.windowCount * cardW * cardH;
            const score = totalCardSpace * Math.pow(fillH, 1.8) * Math.pow(fillW, 0.6);

            if (score > bestScore) {
                bestScore = score;
                bestCols = C;
            }
        }

        return Math.max(1, Math.min(pageRoot.windowCount, bestCols));
    }

    readonly property int rowCount: Math.max(1, Math.ceil(windowCount / cols))

    readonly property real availW: Math.max(100, pageRoot.width - (pageRoot.colSpacing * (cols - 1)) - 32)
    readonly property real availH: Math.max(100, pageRoot.height - (pageRoot.spacing * (rowCount - 1)) - 32)

    // Slot bounds fill the entire available grid space across all columns and rows
    readonly property real slotWidth: {
        const base = availW / cols;
        if (windowCount === 1) return Math.min(base, pageRoot.width * 0.70);
        return base;
    }

    readonly property real slotHeight: {
        const base = availH / rowCount;
        if (windowCount === 1) return Math.min(base, pageRoot.height * 0.80);
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

    function getAspectAtIndex(i) {
        if (cardsRepeater && i >= 0 && i < cardsRepeater.count) {
            const it = cardsRepeater.itemAt(i);
            if (it && it.effectiveAspect > 0) return it.effectiveAspect;
        }
        if (pageTasksModel && i >= 0 && i < pageTasksModel.count) {
            const idx = pageTasksModel.makeModelIndex(i);
            const geom = pageTasksModel.data(idx, TaskManager.AbstractTasksModel.Geometry);
            const s = pageRoot.extractSize(geom);
            if (s && s.height > 0) return s.width / s.height;
        }
        return (Screen.width > 0 && Screen.height > 0) ? (Screen.width / Screen.height) : 1.6;
    }

    function getCardWidthForHeightAndAspect(cardH, aspect) {
        const a = (aspect > 0) ? aspect : ((Screen.width > 0 && Screen.height > 0) ? (Screen.width / Screen.height) : 1.6);
        const maxPH = Math.max(16, cardH - pageRoot.nonPreviewH);
        const pW = Math.round(maxPH * a);
        return Math.max(24, Math.round(pW + pageRoot.nonPreviewW));
    }

    function isRowOutlier(rIndex, aspect) {
        const startIdx = rIndex * pageRoot.cols;
        const endIdx = Math.min(pageRoot.windowCount, (rIndex + 1) * pageRoot.cols);
        const K = endIdx - startIdx;
        if (K <= 1) return false;

        const rowAvailW = Math.max(100, pageRoot.width - 32 - ((K - 1) * pageRoot.colSpacing));
        const baseSlotW = (pageRoot.width - 32 - ((pageRoot.cols - 1) * pageRoot.colSpacing)) / pageRoot.cols;
        const maxCardW = Math.min(rowAvailW * (1.5 / K), baseSlotW * 1.45);

        const slotH = (pageRoot.windowCount === 1) ? Math.min(pageRoot.slotHeight, pageRoot.height * 0.80) : pageRoot.slotHeight;
        const maxPH = Math.max(16, slotH - pageRoot.nonPreviewH);
        const naturalW = maxPH * aspect + pageRoot.nonPreviewW;

        return (aspect > 2.2) || (naturalW > maxCardW * 1.15);
    }

    function getRowHeight(rIndex) {
        const _tick = pageRoot.layoutRefreshTick;
        const startIdx = rIndex * pageRoot.cols;
        const endIdx = Math.min(pageRoot.windowCount, (rIndex + 1) * pageRoot.cols);
        const K = endIdx - startIdx;
        if (K <= 0) return pageRoot.slotHeight;

        let rowAvailW = Math.max(100, pageRoot.width - 32 - ((K - 1) * pageRoot.colSpacing));
        let maxSlotH = pageRoot.slotHeight;
        if (pageRoot.windowCount === 1) {
            rowAvailW = Math.max(100, pageRoot.width * 0.70);
            maxSlotH = Math.max(100, pageRoot.height * 0.80);
        }

        const maxPH_from_height = Math.max(16, maxSlotH - pageRoot.nonPreviewH);
        const baseSlotW = (pageRoot.width - 32 - ((pageRoot.cols - 1) * pageRoot.colSpacing)) / pageRoot.cols;
        const maxCardW = (K > 1) ? Math.min(rowAvailW * (1.5 / K), baseSlotW * 1.45) : rowAvailW;

        let normalAspectSum = 0;
        let normalCount = 0;
        let usedOutlierWidth = 0;

        for (let i = startIdx; i < endIdx; i++) {
            const a = pageRoot.getAspectAtIndex(i);
            if (pageRoot.isRowOutlier(rIndex, a)) {
                usedOutlierWidth += maxCardW;
            } else {
                normalAspectSum += a;
                normalCount++;
            }
        }

        if (normalCount === 0) {
            return Math.max(24, Math.round(maxSlotH));
        }

        const remainingWidth = Math.max(100, rowAvailW - usedOutlierWidth);
        const maxPH_from_width = (remainingWidth - normalCount * pageRoot.nonPreviewW) / normalAspectSum;
        const uniformPH = Math.max(16, Math.min(maxPH_from_height, maxPH_from_width));

        return Math.max(24, Math.round(uniformPH + pageRoot.nonPreviewH));
    }

    readonly property real actualGridHeight: {
        const _tick = pageRoot.layoutRefreshTick;
        if (pageRoot.windowCount <= 0) return 0;
        let totalH = 0;
        for (let r = 0; r < pageRoot.rowCount; r++) {
            totalH += pageRoot.getRowHeight(r);
        }
        totalH += Math.max(0, pageRoot.rowCount - 1) * pageRoot.spacing;
        return totalH;
    }

    readonly property real gridStartY: Math.max(16, (pageRoot.height - actualGridHeight) / 2)

    function getRowY(rIndex) {
        let y = pageRoot.gridStartY;
        for (let r = 0; r < rIndex; r++) {
            y += pageRoot.getRowHeight(r) + pageRoot.spacing;
        }
        return y;
    }

    function getCardHeight(rIndex, aspect) {
        const a = (aspect > 0) ? aspect : 1.6;
        const rowH = pageRoot.getRowHeight(rIndex);

        if (pageRoot.isRowOutlier(rIndex, a)) {
            const startIdx = rIndex * pageRoot.cols;
            const endIdx = Math.min(pageRoot.windowCount, (rIndex + 1) * pageRoot.cols);
            const K = Math.max(1, endIdx - startIdx);
            const rowAvailW = Math.max(100, pageRoot.width - 32 - ((K - 1) * pageRoot.colSpacing));
            const baseSlotW = (pageRoot.width - 32 - ((pageRoot.cols - 1) * pageRoot.colSpacing)) / pageRoot.cols;
            const maxCardW = (K > 1) ? Math.min(rowAvailW * (1.5 / K), baseSlotW * 1.45) : rowAvailW;
            const pH = (maxCardW - pageRoot.nonPreviewW) / a;
            return Math.max(24, Math.min(rowH, Math.round(pH + pageRoot.nonPreviewH)));
        }

        return rowH;
    }

    function getCardWidth(rIndex, aspect) {
        const a = (aspect > 0) ? aspect : 1.6;
        const cardH = pageRoot.getCardHeight(rIndex, a);
        const pH = Math.max(16, cardH - pageRoot.nonPreviewH);
        const pW = Math.round(pH * a);
        return Math.max(24, Math.round(pW + pageRoot.nonPreviewW));
    }

    function getCardWidthAtIndex(i) {
        if (cardsRepeater && i >= 0 && i < cardsRepeater.count) {
            const it = cardsRepeater.itemAt(i);
            if (it && it.cardW > 0) return it.cardW;
        }
        const rIndex = Math.floor(i / pageRoot.cols);
        const asp = pageRoot.getAspectAtIndex(i);
        return pageRoot.getCardWidth(rIndex, asp);
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
        const totalW = sumW + ((count - 1) * pageRoot.colSpacing);
        const startX = Math.max(16, (pageRoot.width - totalW) / 2);

        const offsets = [];
        let curX = startX;
        for (let j = 0; j < count; j++) {
            offsets.push(curX);
            curX += widths[j] + pageRoot.colSpacing;
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

        readonly property real totalGridHeight: pageRoot.actualGridHeight
        readonly property real gridStartY: pageRoot.gridStartY

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
                readonly property var itemLauncherUrl: model.LauncherUrlWithoutIcon !== undefined ? model.LauncherUrlWithoutIcon : (model.LauncherUrl !== undefined ? model.LauncherUrl : "")
                readonly property var itemWinIds: model.WinIdList ? model.WinIdList : []
                readonly property int itemAppPid: model.AppPid !== undefined ? model.AppPid : 0
                readonly property int paVersion: pageRoot.pulseAudio ? pageRoot.pulseAudio.streamsVersion : 0

                property var audioStreams: []
                readonly property bool hasAudioStream: {
                    const _v = paVersion;
                    return audioStreams && audioStreams.length > 0;
                }
                readonly property bool playingAudio: {
                    const _v = paVersion;
                    return hasAudioStream && audioStreams.some(item => !item.corked);
                }
                readonly property bool isAudioMuted: {
                    const _v = paVersion;
                    return hasAudioStream && audioStreams.every(item => item.muted);
                }
                readonly property bool shouldDisplayAudioIndicator: hasAudioStream && (playingAudio || isAudioMuted)

                function setAssignedAudioStreams(s) {
                    cellItem.audioStreams = s || [];
                }

                function toggleMuted() {
                    if (!cellItem.audioStreams || cellItem.audioStreams.length === 0) return;
                    const currentlyMuted = cellItem.audioStreams.every(item => item.muted);
                    if (currentlyMuted) {
                        cellItem.audioStreams.forEach(item => item.unmute());
                    } else {
                        cellItem.audioStreams.forEach(item => item.mute());
                    }
                    if (pageRoot.pulseAudio) pageRoot.pulseAudio.notifyChanged();
                }

                property var micStreams: []
                readonly property bool hasMicStream: {
                    const _v = paVersion;
                    return micStreams && micStreams.length > 0;
                }
                readonly property bool recordingMic: {
                    const _v = paVersion;
                    return hasMicStream && micStreams.some(item => !item.corked);
                }
                readonly property bool isMicMuted: {
                    const _v = paVersion;
                    return hasMicStream && micStreams.every(item => item.muted);
                }
                readonly property bool shouldDisplayMicIndicator: hasMicStream && (recordingMic || isMicMuted)

                function setAssignedMicStreams(s) {
                    cellItem.micStreams = s || [];
                }

                function toggleMicMuted() {
                    if (!cellItem.micStreams || cellItem.micStreams.length === 0) return;
                    const currentlyMuted = cellItem.micStreams.every(item => item.muted);
                    if (currentlyMuted) {
                        cellItem.micStreams.forEach(item => item.unmute());
                    } else {
                        cellItem.micStreams.forEach(item => item.mute());
                    }
                    if (pageRoot.pulseAudio) pageRoot.pulseAudio.notifyChanged();
                }

                property bool hasMediaControl: false
                property bool isMediaPlaying: false
                property bool canMediaPause: true
                property bool canMediaPlay: true
                property bool canMediaGoPrevious: false
                property bool canMediaGoNext: false
                property var activePlayer: null
                property int assignedPlayerIndex: -1

                function setAssignedPlayer(p, pIdx) {
                    if (p && p.canControl) {
                        const st = p.playbackStatus;
                        const isPl = st === Mpris.PlaybackStatus.Playing;
                        const isPa = st === Mpris.PlaybackStatus.Paused;
                        if (isPl || isPa) {
                            cellItem.activePlayer = p;
                            cellItem.assignedPlayerIndex = (pIdx !== undefined) ? pIdx : -1;
                            cellItem.hasMediaControl = true;
                            cellItem.isMediaPlaying = isPl;
                            cellItem.canMediaPause = Boolean(p.canPause);
                            cellItem.canMediaPlay = Boolean(p.canPlay);
                            cellItem.canMediaGoPrevious = Boolean(p.canGoPrevious);
                            cellItem.canMediaGoNext = Boolean(p.canGoNext);
                            return;
                        }
                    }
                    cellItem.activePlayer = null;
                    cellItem.assignedPlayerIndex = -1;
                    cellItem.hasMediaControl = false;
                    cellItem.isMediaPlaying = false;
                }

                Component.onCompleted: {
                    pageRoot.updateAllMediaControls();
                    pageRoot.updateAllAudioStreams();
                }
                onItemAppPidChanged: {
                    pageRoot.updateAllMediaControls();
                    pageRoot.updateAllAudioStreams();
                }
                onItemAppIdChanged: {
                    pageRoot.updateAllMediaControls();
                    pageRoot.updateAllAudioStreams();
                }
                onItemTitleChanged: {
                    pageRoot.updateAllMediaControls();
                    pageRoot.updateAllAudioStreams();
                }
                readonly property bool itemIsActive: Boolean(model.IsActive)
                readonly property bool itemIsMinimized: Boolean(model.IsMinimized)
                readonly property bool itemIsMaximized: Boolean(model.IsMaximized)
                readonly property bool itemIsKeepAbove: Boolean(model.IsKeepAbove)
                readonly property bool itemIsKeepBelow: Boolean(model.IsKeepBelow)
                readonly property bool itemIsFullScreen: Boolean(model.IsFullScreen)
                readonly property bool itemIsShaded: Boolean(model.IsShaded)
                readonly property bool itemIsOnAllDesktops: Boolean(model.IsOnAllVirtualDesktops)
                readonly property bool itemIsVirtualDesktopsChangeable: model.IsVirtualDesktopsChangeable !== undefined ? Boolean(model.IsVirtualDesktopsChangeable) : true
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

                readonly property int rowIndex: Math.floor(cellItem.index / pageRoot.cols)
                readonly property int colIndex: cellItem.index % pageRoot.cols

                readonly property real effectiveAspect: {
                    if (customAspect > 0) return customAspect;
                    const s = pageRoot.extractSize(cellItem.itemGeom);
                    if (s) return s.width / s.height;
                    return (Screen.width > 0 && Screen.height > 0) ? (Screen.width / Screen.height) : 1.6;
                }

                onEffectiveAspectChanged: pageRoot.layoutRefreshTick++

                readonly property real cardH: pageRoot.getCardHeight(rowIndex, effectiveAspect)
                readonly property real cardW: pageRoot.getCardWidth(rowIndex, effectiveAspect)

                function publishGeometry() {
                    if (pageRoot.overviewOpen && pageRoot.isCurrentPage && cardW > 0 && cardH > 0) {
                        const mIdx = pageTasksModel.makeModelIndex(cellItem.index);
                        if (mIdx.valid) {
                            const globalPos = cellItem.mapToItem(null, 0, 0);
                            pageTasksModel.requestPublishDelegateGeometry(mIdx, Qt.rect(globalPos.x, globalPos.y, cardW, cardH), cellItem);
                        }
                    }
                }

                onCardWChanged: publishGeometry()
                onCardHChanged: publishGeometry()

                readonly property var rowMetrics: pageRoot.getRowMetrics(rowIndex)

                x: (rowMetrics && Array.isArray(rowMetrics.offsets) && colIndex < rowMetrics.offsets.length && rowMetrics.offsets[colIndex] !== undefined) ? rowMetrics.offsets[colIndex] : Math.max(16, (pageRoot.width - cardW) / 2)
                y: pageRoot.getRowY(rowIndex) + (pageRoot.getRowHeight(rowIndex) - cardH) / 2
                width: cardW
                height: cardH

                z: (cellItem.index === pageRoot.draggedTaskIndex) ? 200 : (windowCard.isHovered ? 100 : (cellItem.index === pageRoot.selectedIndex ? 10 : 1))

                WindowCard {
                    id: windowCard
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
                    alternateCardStyle: pageRoot.alternateCardStyle
                    alternateCardIconSize: pageRoot.alternateCardIconSize
                    hasAudioStream: cellItem.shouldDisplayAudioIndicator
                    playingAudio: cellItem.playingAudio
                    isAudioMuted: cellItem.isAudioMuted

                    hasMicStream: cellItem.shouldDisplayMicIndicator
                    recordingMic: cellItem.recordingMic
                    isMicMuted: cellItem.isMicMuted
                    onMicMuteToggled: cellItem.toggleMicMuted()
                    hasMediaControl: cellItem.hasMediaControl
                    isMediaPlaying: cellItem.isMediaPlaying
                    canMediaPause: cellItem.canMediaPause
                    canMediaPlay: cellItem.canMediaPlay
                    canMediaGoPrevious: cellItem.canMediaGoPrevious
                    canMediaGoNext: cellItem.canMediaGoNext

                    onAudioMuteToggled: cellItem.toggleMuted()
                    onMediaPreviousClicked: {
                        if (cellItem.activePlayer) cellItem.activePlayer.Previous();
                    }
                    onMediaPlayPauseClicked: {
                        if (cellItem.activePlayer) {
                            if (typeof cellItem.activePlayer.PlayPause === "function") {
                                cellItem.activePlayer.PlayPause();
                            } else if (cellItem.isMediaPlaying) {
                                cellItem.activePlayer.Pause();
                            } else {
                                cellItem.activePlayer.Play();
                            }
                        }
                    }
                    onMediaNextClicked: {
                        if (cellItem.activePlayer) cellItem.activePlayer.Next();
                    }

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

    Connections {
        target: pageRoot.pulseAudio
        function onStreamsChanged() {
            pageRoot.updateAllAudioStreams();
        }
    }

    function getAllMprisPlayers() {
        if (!pageRoot.mprisSource) return [];
        const count = pageRoot.mprisSource.rowCount();
        const rawPlayers = [];
        for (let i = 0; i < count; ++i) {
            const idx = pageRoot.mprisSource.index(i, 0);
            const p = pageRoot.mprisSource.data(idx, 257);
            if (p && typeof p === "object" && p.canControl) {
                const st = p.playbackStatus;
                const isPl = st === Mpris.PlaybackStatus.Playing;
                const isPa = st === Mpris.PlaybackStatus.Paused;
                if (!isPl && !isPa) continue;

                rawPlayers.push(p);
            }
        }

        // Deduplicate multiple interfaces representing the same playback session
        // (e.g. plasma-browser-integration and brave.instance for the same browser)
        const uniquePlayers = [];
        for (let j = 0; j < rawPlayers.length; ++j) {
            const cur = rawPlayers[j];
            const curTrack = (cur.track || "").toLowerCase().trim();
            const curIdentity = (cur.identity || "").toLowerCase().trim();

            let isDup = false;
            if (curTrack.length > 0) {
                for (let k = 0; k < uniquePlayers.length; ++k) {
                    const ex = uniquePlayers[k];
                    const exTrack = (ex.track || "").toLowerCase().trim();
                    const exIdentity = (ex.identity || "").toLowerCase().trim();

                    if (exTrack.length > 0 && (curTrack === exTrack || curTrack.indexOf(exTrack) === 0 || exTrack.indexOf(curTrack) === 0)) {
                        if (curIdentity === exIdentity || cur.instancePid === ex.instancePid || (cur.desktopEntry && cur.desktopEntry === ex.desktopEntry)) {
                            isDup = true;
                            if (!ex.desktopEntry && cur.desktopEntry) {
                                uniquePlayers[k] = cur;
                            }
                            break;
                        }
                    }
                }
            }
            if (!isDup) {
                uniquePlayers.push(cur);
            }
        }

        return uniquePlayers;
    }

    function calculateMatchScore(cell, p, siblingCount) {
        if (!cell || !p) return -1;
        let score = 0;

        const pEntry = (p.desktopEntry || "").toLowerCase().trim();
        const pIdent = (p.identity || "").toLowerCase().trim();
        const cAppId = (cell.itemAppId || "").toLowerCase().trim().replace(/\.desktop$/, "");
        const cAppName = (cell.itemAppName || "").toLowerCase().trim();
        const cLauncher = String(cell.itemLauncherUrl || "").toLowerCase();

        let appMatches = false;
        if (pEntry && (pEntry === cAppId || cLauncher.indexOf(pEntry) !== -1 || cAppId.indexOf(pEntry) !== -1)) {
            appMatches = true;
            score += 20;
        } else if (pIdent && (pIdent === cAppName || pIdent.indexOf(cAppName) !== -1 || cAppName.indexOf(pIdent) !== -1)) {
            appMatches = true;
            score += 15;
        } else if (cell.itemAppPid > 0 && p.instancePid > 0 && p.instancePid === cell.itemAppPid) {
            appMatches = true;
            score += 20;
        }

        if (!appMatches) {
            return -1;
        }

        if (cell.itemAppPid > 0 && (p.instancePid === cell.itemAppPid || p.kdePid === cell.itemAppPid)) {
            score += 10;
        }

        const cardTitle = (cell.itemTitle || "").toLowerCase();
        const track = (p.track || "").toLowerCase().trim();
        const artist = (p.artist || "").toLowerCase().trim();

        // Clean strings for robust matching across dashes/brackets/formatting
        const cleanStr = (s) => (s || "").replace(/[^a-z0-9]/g, " ").trim();
        const cTitle = cleanStr(cardTitle);
        const cTrack = cleanStr(track);
        const cArtist = cleanStr(artist);

        let titleMatched = false;
        if (cTrack.length > 2 && (cTitle.indexOf(cTrack) !== -1 || cTrack.indexOf(cTitle) !== -1)) {
            score += 100;
            titleMatched = true;
        } else if (track.length > 1 && (cardTitle.indexOf(track) !== -1 || track.indexOf(cardTitle) !== -1)) {
            score += 100;
            titleMatched = true;
        }

        if (cArtist.length > 2 && cTitle.indexOf(cArtist) !== -1) {
            score += 40;
            titleMatched = true;
        }

        // When multiple windows of the same application are open,
        // require the window title to match the media track/artist.
        // This strictly prevents a sibling window from claiming media it is not playing.
        if (siblingCount > 1 && !titleMatched) {
            return -1;
        }

        if (p.playbackStatus === Mpris.PlaybackStatus.Playing) {
            score += 10;
        } else if (p.playbackStatus === Mpris.PlaybackStatus.Paused) {
            score += 5;
        }

        return score;
    }

    function updateAllMediaControls() {
        const players = pageRoot.getAllMprisPlayers();
        if (players.length === 0) {
            for (let i = 0; i < cardsRepeater.count; ++i) {
                const it = cardsRepeater.itemAt(i);
                if (it && it.setAssignedPlayer) it.setAssignedPlayer(null);
            }
            return;
        }

        // Count sibling windows per application
        const appCounts = {};
        for (let a = 0; a < cardsRepeater.count; ++a) {
            const c = cardsRepeater.itemAt(a);
            if (!c || c.isSelf) continue;
            const key = (c.itemAppId || c.itemAppName || "app").toLowerCase();
            appCounts[key] = (appCounts[key] || 0) + 1;
        }

        const pairs = [];
        for (let i = 0; i < cardsRepeater.count; ++i) {
            const cell = cardsRepeater.itemAt(i);
            if (!cell || cell.isSelf) continue;
            const key = (cell.itemAppId || cell.itemAppName || "app").toLowerCase();
            const sibCount = appCounts[key] || 1;

            for (let j = 0; j < players.length; ++j) {
                const p = players[j];
                const sc = pageRoot.calculateMatchScore(cell, p, sibCount);
                if (sc >= 0) {
                    pairs.push({ cell: cell, cellIndex: cell.index, player: p, playerIndex: j, score: sc });
                }
            }
        }

        pairs.sort((a, b) => b.score - a.score);

        const assignedCellIndices = new Set();
        const assignedPlayerIndices = new Set();

        for (let k = 0; k < pairs.length; ++k) {
            const pair = pairs[k];
            if (!assignedCellIndices.has(pair.cellIndex) && !assignedPlayerIndices.has(pair.playerIndex)) {
                assignedCellIndices.add(pair.cellIndex);
                assignedPlayerIndices.add(pair.playerIndex);
                pair.cell.setAssignedPlayer(pair.player, pair.playerIndex);
            }
        }

        for (let m = 0; m < cardsRepeater.count; ++m) {
            const it = cardsRepeater.itemAt(m);
            if (it && !assignedCellIndices.has(it.index) && it.setAssignedPlayer) {
                it.setAssignedPlayer(null, -1);
            }
        }

        pageRoot.updateAllAudioStreams();
    }

    function updateAllAudioStreams() {
        if (!pageRoot.pulseAudio) {
            for (let i = 0; i < cardsRepeater.count; ++i) {
                const it = cardsRepeater.itemAt(i);
                if (it) {
                    if (it.setAssignedAudioStreams) it.setAssignedAudioStreams([]);
                    if (it && it.setAssignedMicStreams) it.setAssignedMicStreams([]);
                }
            }
            return;
        }

        const pa = pageRoot.pulseAudio;

        const appGroups = {};
        for (let i = 0; i < cardsRepeater.count; ++i) {
            const cell = cardsRepeater.itemAt(i);
            if (!cell) continue;
            if (cell.isSelf) {
                if (cell.setAssignedAudioStreams) cell.setAssignedAudioStreams([]);
                if (cell.setAssignedMicStreams) cell.setAssignedMicStreams([]);
                continue;
            }
            const key = (cell.itemAppId || cell.itemAppName || "app").toLowerCase();
            if (!appGroups[key]) appGroups[key] = [];
            appGroups[key].push(cell);
        }

        for (let key in appGroups) {
            const cells = appGroups[key];
            const firstCell = cells[0];

            let allStreams = [];
            if (firstCell.itemAppId) {
                allStreams = pa.streamsForAppId(firstCell.itemAppId);
            }
            if (!allStreams.length && firstCell.itemAppPid > 0) {
                allStreams = pa.streamsForPid(firstCell.itemAppPid);
            }
            if (!allStreams.length && firstCell.itemAppName) {
                allStreams = pa.streamsForAppName(firstCell.itemAppName);
            }

            for (let c of cells) {
                if (c && c.setAssignedAudioStreams) {
                    c.setAssignedAudioStreams(allStreams);
                }
            }

            let allMicStreams = [];
            if (firstCell.itemAppId) {
                allMicStreams = pa.micStreamsForAppId(firstCell.itemAppId);
            }
            if (!allMicStreams.length && firstCell.itemAppPid > 0) {
                allMicStreams = pa.micStreamsForPid(firstCell.itemAppPid);
            }
            if (!allMicStreams.length && firstCell.itemAppName) {
                allMicStreams = pa.micStreamsForAppName(firstCell.itemAppName);
            }

            for (let c of cells) {
                if (c && c.setAssignedMicStreams) {
                    c.setAssignedMicStreams(allMicStreams);
                }
            }
        }
    }

    Connections {
        target: pageRoot.mprisSource
        function onDataChanged() {
            pageRoot.updateAllMediaControls();
        }
        function onRowsInserted() {
            pageRoot.updateAllMediaControls();
        }
        function onRowsRemoved() {
            pageRoot.updateAllMediaControls();
        }
    }

    // Shared context menu instance for all cards on this page
    property int contextMenuTaskIndex: -1

    WindowContextMenu {
        id: windowContextMenu

        onRequestDismissOverview: {
            pageRoot.taskActivated(null);
        }

        onRequestToggleMuted: {
            if (contextMenuTaskIndex >= 0) {
                const item = cardsRepeater.itemAt(contextMenuTaskIndex);
                if (item && item.toggleMuted) {
                    item.toggleMuted();
                }
            }
        }

        onRequestToggleMicMuted: {
            if (contextMenuTaskIndex >= 0) {
                const item = cardsRepeater.itemAt(contextMenuTaskIndex);
                if (item && item.toggleMicMuted) {
                    item.toggleMicMuted();
                }
            }
        }

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
        windowContextMenu.launcherUrl = (cell.itemLauncherUrl !== undefined && cell.itemLauncherUrl !== null) ? cell.itemLauncherUrl : "";
        windowContextMenu.appId = cell.itemAppId || "";
        windowContextMenu.appPid = cell.itemAppPid || 0;
        windowContextMenu.winIdList = cell.itemWinIds || [];
        windowContextMenu.targetPlayer = cell.activePlayer || null;
        windowContextMenu.hasAudioStream = cell.shouldDisplayAudioIndicator;
        windowContextMenu.playingAudio = cell.playingAudio;
        windowContextMenu.isAudioMuted = cell.isAudioMuted;
        windowContextMenu.hasMicStream = cell.shouldDisplayMicIndicator;
        windowContextMenu.recordingMic = cell.recordingMic;
        windowContextMenu.isMicMuted = cell.isMicMuted;
        windowContextMenu.canLaunchNewInstance = cell.itemCanLaunchNewInstance;
        windowContextMenu.isOnAllDesktops = cell.itemIsOnAllDesktops;
        windowContextMenu.isVirtualDesktopsChangeable = cell.itemIsVirtualDesktopsChangeable;
        windowContextMenu.virtualDesktops = cell.itemVirtualDesktops;
        windowContextMenu.activities = cell.itemActivities;
        windowContextMenu.desktopCount = pageRoot.desktopCount;
        windowContextMenu.desktopIds = pageRoot.desktopIds;
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
                color: Kirigami.Theme.textColor
                opacity: 0.75
                Layout.alignment: Qt.AlignHCenter
            }

            QQC2.Label {
                text: i18n("Start typing to search and launch apps")
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: Kirigami.Theme.disabledTextColor
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
