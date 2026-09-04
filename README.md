# Veronica Overview

A GNOME-style desktop overview widget for KDE Plasma 6 that keeps your desktop panels completely visible, clickable, and interactive.

---

## Features

- **Fully Available & Interactive Panels**: Desktop panels, docks, application launchers, and system tray applets remain on top, completely visible, and interactive while the overview is open.
- **Virtual Desktop Switching & Management**: Smooth multi-page workspace carousel with fluid slide animations, mouse-wheel scrolling, PageUp/PageDown switching, and an integrated desktop pager supporting drag-and-drop window organization.
- **Window Cards with Previews**: High-fidelity window preview cards featuring live PipeWire screencasts dynamically scaled to match the window's exact aspect ratio with zero letterboxing.
- **KRunner-Based Search**: Instant type-anywhere search for applications, documents, calculator expressions, and system actions powered by KRunner and Milou.
- **Keyboard Navigation**: Complete keyboard-driven workflow with directional arrow key navigation between window cards, instant type-to-search handoff, Enter/Space to activate, and Escape to dismiss.
- **Native Context Menus**: Full right-click context menu parity with KDE Plasma's Task Manager (Move to Desktop, Show in Activities, Minimize, Maximize, Fullscreen, Close) and pager actions (Add, Remove, and Configure Virtual Desktops).

---

## Installation

Run the installation script:

```bash
./install.sh
```

Restart plasmashell to load changes:

```bash
systemctl --user restart plasma-plasmashell.service
```

---

## Usage

1. Right-click your panel and select **Add Widgets...**
2. Drag **Veronica Overview** onto your panel.
3. (Optional) Right-click the widget and choose **Configure Veronica Overview...** to customize appearance and shortcuts.

---

## Author

- **stakillion** ([stakillion@gmail.com](mailto:stakillion@gmail.com))
- Website: [https://n3.pm](https://n3.pm)
