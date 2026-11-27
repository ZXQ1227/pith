#!/bin/bash
set -euo pipefail

# Build Pith.app and package it into a distributable Pith.dmg.
#
# Usage:
#   bash build-dmg.sh /path/to/Pith.dmg
#
# The DMG contains Pith.app and an Applications symlink so users can
# drag-and-drop install. In sandboxed environments set PITH_DISABLE_SANDBOX=1.

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
DMG_PATH="${1:-$ROOT_DIR/dist/Pith.dmg}"
if [[ "$DMG_PATH" != /* || "$DMG_PATH" != *.dmg ]]; then
    printf 'DMG output must be an absolute path ending in .dmg\n' >&2
    exit 1
fi

WORK_DIR="$(mktemp -d /private/tmp/pith-dmg.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

bash "$ROOT_DIR/build-app.sh" "$WORK_DIR/Pith.app"
ln -s /Applications "$WORK_DIR/Applications"

hdiutil create \
    -volname "Pith" \
    -srcfolder "$WORK_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
hdiutil verify "$DMG_PATH"

printf 'Built %s\n' "$DMG_PATH"
