#!/usr/bin/env bash
set -e

PLUGIN_ID="stakillion.veronica.overview"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}/.local/share/plasma/plasmoids/${PLUGIN_ID}"

echo "==> Installing Veronica Overview Plasmoid for KDE Plasma 6..."

# Create target directory
mkdir -p "${HOME}/.local/share/plasma/plasmoids"

# Direct copy for reliable updates (kpackagetool6 --upgrade can leave stale files)
echo "Syncing plugin files..."
rm -rf "${TARGET_DIR}"
mkdir -p "${TARGET_DIR}"
cp -r "${SCRIPT_DIR}/contents" "${TARGET_DIR}/contents"
cp "${SCRIPT_DIR}/metadata.json" "${TARGET_DIR}/metadata.json"

echo ""
echo "==> Veronica Overview plugin successfully installed!"
echo "To use it:"
echo "1. Right-click on your panel -> 'Add Widgets...'"
echo "2. Drag 'Veronica Overview' onto your panel (it will display an 'Activities' button)"
echo "3. (Optional) Right-click the widget -> 'Configure Veronica Overview...' to customize shortcuts, appearance, and behavior."
echo "4. (Optional) To trigger via Meta / Super key, configure the widget shortcut in Plasma Settings -> Shortcuts."
