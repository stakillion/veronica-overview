/**
 * Veronica Overview - KWin Desktop & Compositor Controller
 * 
 * 1. Ensures the Veronica Overview window is present on all virtual desktops.
 * 2. Directly drives the window opacity animation inside KWin's compositor (Kirigami longDuration: 200ms),
 *    allowing the entire window — including KWin background blur and theme
 *    decorations — to smoothly fade in and out with zero snapping.
 * 3. Immediately closes without animation when a window is focused.
 */

var overviewWindow = null;
var currentAnimationTimer = null;
var FADE_DURATION = 200;

function animateWindowOpacity(w, targetOpacity, duration) {
    if (!w) return;
    if (currentAnimationTimer) {
        currentAnimationTimer.stop();
        currentAnimationTimer = null;
    }

    var startOpacity = (typeof w.opacity === "number" && !isNaN(w.opacity)) ? w.opacity : 0.0;
    if (Math.abs(startOpacity - targetOpacity) < 0.01) {
        w.opacity = targetOpacity;
        return;
    }

    var startTime = Date.now();
    var timer = new QTimer();
    currentAnimationTimer = timer;
    timer.interval = 16;
    timer.timeout.connect(function() {
        var elapsed = Date.now() - startTime;
        var progress = Math.min(1.0, elapsed / duration);
        // OutCubic easing
        var eased = 1.0 - Math.pow(1.0 - progress, 3);
        w.opacity = startOpacity + (targetOpacity - startOpacity) * eased;
        if (progress >= 1.0) {
            timer.stop();
            if (currentAnimationTimer === timer) {
                currentAnimationTimer = null;
            }
            w.opacity = targetOpacity;
        }
    });
    timer.start();
}

function setupOverviewWindow(window) {
    if (!window) return;
    var cap = window.caption || "";
    if (cap.indexOf("Veronica Overview") !== -1 && (window.resourceClass === "plasmashell" || window.resourceName === "plasmashell")) {
        overviewWindow = window;
        if (!window.onAllDesktops) {
            window.onAllDesktops = true;
        }
        window.skipsCloseAnimation = true;

        if (cap.indexOf(":instant-close") !== -1) {
            if (currentAnimationTimer) {
                currentAnimationTimer.stop();
                currentAnimationTimer = null;
            }
            window.opacity = 0.0;
        } else {
            var dur = FADE_DURATION;
            var parts = cap.split(":");
            if (parts.length >= 3) {
                var parsed = parseInt(parts[2], 10);
                if (!isNaN(parsed) && parsed >= 0) {
                    dur = parsed;
                }
            }

            if (cap.indexOf(":close") !== -1) {
                animateWindowOpacity(window, 0.0, dur);
            } else {
                animateWindowOpacity(window, 1.0, dur);
            }
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

workspace.windowAdded.connect(function(window) {
    if (!window) return;
    var cap = window.caption || "";
    if (cap.indexOf("Veronica Overview") !== -1 && (window.resourceClass === "plasmashell" || window.resourceName === "plasmashell")) {
        window.opacity = 0.0;
    }
    monitorWindow(window);
});

workspace.windowList().forEach(monitorWindow);
console.info("[Veronica Overview] KWin desktop controller active");
