#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="${1:-$ROOT_DIR/dist/Pith.app}"
if [[ "$APP_DIR" != /* || "$APP_DIR" != *.app ]]; then
    printf 'App output must be an absolute path ending in .app\n' >&2
    exit 1
fi

# Sandboxed environments (CI jobs, restricted shells) block swift-build's
# sandbox-exec. Set PITH_DISABLE_SANDBOX=1 to build without it.
# Kept as a string for macOS bash 3.2 compat: "set -u" breaks empty-array
# expansion there.
SWIFT_SANDBOX_FLAGS=""
if [[ "${PITH_DISABLE_SANDBOX:-0}" == "1" ]]; then
    SWIFT_SANDBOX_FLAGS="--disable-sandbox"
fi

swift build --package-path "$ROOT_DIR" --scratch-path "$BUILD_DIR" --cache-path "$ROOT_DIR/.cache" --manifest-cache local $SWIFT_SANDBOX_FLAGS -c release
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
BIN_DIR="$(swift build --package-path "$ROOT_DIR" --scratch-path "$BUILD_DIR" --cache-path "$ROOT_DIR/.cache" --manifest-cache local $SWIFT_SANDBOX_FLAGS -c release --show-bin-path)"
cp "$BIN_DIR/Pith" "$APP_DIR/Contents/MacOS/Pith"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
# Finder and synced folders can attach metadata that codesign rejects, even to a new bundle.
# Only remove the two forbidden attributes from this generated artifact.
while IFS= read -r -d '' BUNDLE_ITEM; do
    for ATTRIBUTE in com.apple.FinderInfo com.apple.ResourceFork; do
        if xattr -p "$ATTRIBUTE" "$BUNDLE_ITEM" >/dev/null 2>&1; then
            xattr -d "$ATTRIBUTE" "$BUNDLE_ITEM"
        fi
    done
done < <(find "$APP_DIR" -print0)
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
printf 'Built %s\n' "$APP_DIR"
