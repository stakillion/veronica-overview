# Veronica Overview

A GNOME-style desktop overview widget for KDE Plasma 6 that keeps your desktop panels completely visible, clickable, and interactive.

---

## Features

- **Visible & Interactive Panels**: Panels, docks, system trays, and applets remain fully accessible and interactive while in the overview.
- **Dynamic Window Grid**: Window cards with live PipeWire previews dynamically scaled to match actual window aspect ratios with tight, centered row layouts.
- **Drag-and-Drop to Workspaces**: Drag window cards directly onto the workspace pager bar to move windows between virtual desktops, featuring smooth snap-back animation on invalid drops.
- **Type-Anywhere Search**: Instant application and file search powered by KRunner/Milou. Simply start typing while the overview is open.
- **Virtual Desktop Pager**: Screen-proportional workspace strip at the top. Scroll anywhere to switch desktops or click the active desktop to close the overview.
- **Customizable Panel Button**: Configurable icon, custom label, font family, and font size.

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
