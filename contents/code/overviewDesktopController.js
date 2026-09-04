/**
 * Veronica Overview - KWin Desktop Controller
 * 
 * Automatically ensures the Veronica Overview window is present on all virtual
 * desktops so that desktop switching animations and pager interactions work seamlessly
 * without requiring the user to manually configure a window rule in KDE System Settings.
 */

function setupOverviewWindow(window) {
    if (!window) return;
    var cap = window.caption || "";
    if (cap === "Veronica Overview" && (window.resourceClass === "plasmashell" || window.resourceName === "plasmashell")) {
        if (!window.onAllDesktops) {
            window.onAllDesktops = true;
            console.info("[Veronica Overview] Configured onAllDesktops = true for overview window");
        }
    }
}

function monitorWindow(window) {
    if (!window) return;
    if (window.resourceClass === "plasmashell" || window.resourceName === "plasmashell") {
        setupOverviewWindow(window);
        try {
            window.captionChanged.connect(function() {
                setupOverviewWindow(window);
            });
        } catch (e) {}
    }
}

workspace.windowAdded.connect(monitorWindow);
workspace.windowList().forEach(monitorWindow);
console.info("[Veronica Overview] KWin desktop controller active");
