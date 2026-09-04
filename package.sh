#!/usr/bin/env bash
set -e

PLUGIN_ID="stakillion.veronica.overview"
OUTPUT_FILE="${PLUGIN_ID}.plasmoid"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "${SCRIPT_DIR}"

echo "==> Packaging Veronica Overview into ${OUTPUT_FILE}..."

# Remove old package if it exists
rm -f "${OUTPUT_FILE}"

# Create zip archive of the plasmoid contents
zip -r "${OUTPUT_FILE}" contents/ metadata.json LICENSE.md README.md preview.png

echo ""
echo "==> Successfully packaged! Created: ${OUTPUT_FILE}"
echo "You can distribute this file, or install it using:"
echo "    kpackagetool6 -t Plasma/Applet --install ${OUTPUT_FILE}"
