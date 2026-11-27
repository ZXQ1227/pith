#!/bin/bash
set -euo pipefail

# Build Pith.app, optionally as a universal binary, and bundle the app icon.
#
# Usage:
#   bash build-app.sh [/abs/path/Pith.app]
#
# Environment:
#   PITH_ARCHS        Space-separated architectures to build. Defaults to the
#                     host architecture (fast local builds). Release builds set
#                     "arm64 x86_64" to produce a universal binary.
#   PITH_SIGN_IDENTITY
#                     "Developer ID Application: ..." to sign for distribution
#                     (adds hardened runtime + secure timestamp). When unset the
#                     bundle is signed ad-hoc, which is enough to run locally but
#                     leaves new downloads blocked by Gatekeeper.
#   PITH_ENTITLEMENTS Optional path to an entitlements plist; only used when
#                     PITH_SIGN_IDENTITY is set.
#   PITH_DISABLE_SANDBOX
#                     Set to 1 in sandboxed environments (CI) where swift-build's
#                     sandbox-exec is unavailable.
#
# Note: SwiftPM cannot build multiple --arch values in one invocation when the
# package uses macros (@Observable and friends resolve through the macro plugin
# server and fail with "produced malformed response"). We therefore build each
# architecture separately and merge with lipo.

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="${1:-$ROOT_DIR/dist/Pith.app}"
if [[ "$APP_DIR" != /* || "$APP_DIR" != *.app ]]; then
    printf 'App output must be an absolute path ending in .app\n' >&2
    exit 1
fi

ARCHS="${PITH_ARCHS:-$(uname -m)}"
SIGN_IDENTITY="${PITH_SIGN_IDENTITY:-}"
ENTITLEMENTS="${PITH_ENTITLEMENTS:-}"

# Kept as a string for macOS bash 3.2 compat: "set -u" breaks empty-array
# expansion there.
SWIFT_SANDBOX_FLAGS=""
if [[ "${PITH_DISABLE_SANDBOX:-0}" == "1" ]]; then
    SWIFT_SANDBOX_FLAGS="--disable-sandbox"
fi

printf 'Building for architecture(s): %s\n' "$ARCHS"

SLICES=""
for ARCH in $ARCHS; do
    swift build --package-path "$ROOT_DIR" --scratch-path "$BUILD_DIR" --cache-path "$ROOT_DIR/.cache" --manifest-cache local $SWIFT_SANDBOX_FLAGS -c release --arch "$ARCH"
    BIN_DIR="$(swift build --package-path "$ROOT_DIR" --scratch-path "$BUILD_DIR" --cache-path "$ROOT_DIR/.cache" --manifest-cache local $SWIFT_SANDBOX_FLAGS -c release --arch "$ARCH" --show-bin-path)"
    if [[ ! -f "$BIN_DIR/Pith" ]]; then
        printf 'Missing build product for %s at %s/Pith\n' "$ARCH" "$BIN_DIR" >&2
        exit 1
    fi
    SLICES="$SLICES $BIN_DIR/Pith"
done

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# Merge the per-architecture products into one binary. lipo accepts a single
# input and still emits a valid file, so the shared path covers both cases.
# shellcheck disable=SC2086
lipo -create $SLICES -output "$APP_DIR/Contents/MacOS/Pith"

# Fail loudly if the shipped binary is missing a requested slice: a silent
# arm64-only DMG is exactly the bug this build script exists to prevent.
FAT_INFO="$(lipo -info "$APP_DIR/Contents/MacOS/Pith")"
for ARCH in $ARCHS; do
    if [[ "$FAT_INFO" != *"$ARCH"* ]]; then
        printf 'Built binary is missing %s slice: %s\n' "$ARCH" "$FAT_INFO" >&2
        exit 1
    fi
done
printf '%s\n' "$FAT_INFO"

cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Finder and synced folders can attach metadata that codesign rejects, even to a new bundle.
# Only remove the two forbidden attributes from this generated artifact.
while IFS= read -r -d '' BUNDLE_ITEM; do
    for ATTRIBUTE in com.apple.FinderInfo com.apple.ResourceFork; do
        if xattr -p "$ATTRIBUTE" "$BUNDLE_ITEM" >/dev/null 2>&1; then
            xattr -d "$ATTRIBUTE" "$BUNDLE_ITEM"
        fi
    done
done < <(find "$APP_DIR" -print0)

if [[ -n "$SIGN_IDENTITY" ]]; then
    printf 'Signing with identity: %s\n' "$SIGN_IDENTITY"
    # Hardened runtime + timestamp are both required for notarization.
    SIGN_ARGS=(--force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY")
    if [[ -n "$ENTITLEMENTS" && -f "$ENTITLEMENTS" ]]; then
        SIGN_ARGS+=(--entitlements "$ENTITLEMENTS")
    fi
    codesign "${SIGN_ARGS[@]}" "$APP_DIR"
else
    printf 'No PITH_SIGN_IDENTITY set; signing ad-hoc (Gatekeeper will block fresh downloads).\n'
    codesign --force --deep --sign - "$APP_DIR"
fi

codesign --verify --deep --strict "$APP_DIR"
printf 'Built %s\n' "$APP_DIR"
