#!/bin/bash
# build.sh — compiles via SwiftPM, assembles a proper .app bundle,
# generates the procedural icon, ad-hoc signs, and optionally builds a DMG.
#
# Usage:
#   ./Scripts/build.sh                 # build the .app
#   ./Scripts/build.sh --dmg           # also produce build/IconPing.dmg
#   ./Scripts/build.sh --release       # release optimization (default)
#   ./Scripts/build.sh --debug         # debug build
#
# Requires only macOS Command Line Tools.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="release"
MAKE_DMG=0
for arg in "$@"; do
    case "$arg" in
        --dmg)     MAKE_DMG=1 ;;
        --debug)   CONFIGURATION="debug" ;;
        --release) CONFIGURATION="release" ;;
    esac
done

BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/IconPing.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "▸ Cleaning..."
rm -rf "$APP_DIR" "$BUILD_DIR/IconPing.dmg"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "▸ Building Swift Package ($CONFIGURATION)..."
# Universal build (arm64 + x86_64) requires full Xcode (xcbuild). On a CLT-only
# system we fall back to a host-native build.
UNIVERSAL_ARGS=(--arch arm64 --arch x86_64)
if [ -d "/Applications/Xcode.app" ] || [ -x "/Library/Developer/SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild" ]; then
    echo "  attempting universal build (arm64 + x86_64)..."
    if ! swift build -c "$CONFIGURATION" "${UNIVERSAL_ARGS[@]}"; then
        echo "  universal build failed — falling back to host-native"
        UNIVERSAL_ARGS=()
        swift build -c "$CONFIGURATION"
    fi
else
    echo "  CLT-only environment detected — building host-native (CI will build universal)"
    UNIVERSAL_ARGS=()
    swift build -c "$CONFIGURATION"
fi

if [ ${#UNIVERSAL_ARGS[@]} -gt 0 ]; then
    BIN_PATH="$(swift build -c "$CONFIGURATION" "${UNIVERSAL_ARGS[@]}" --show-bin-path)"
else
    BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"
fi
echo "  bin path: $BIN_PATH"

cp "$BIN_PATH/IconPing" "$MACOS_DIR/IconPing"
chmod +x "$MACOS_DIR/IconPing"

echo "▸ Generating procedural app icon..."
bash "$ROOT/Scripts/make-icon.sh"
cp "$BUILD_DIR/IconPing.icns" "$RESOURCES_DIR/IconPing.icns"

echo "▸ Copying Info.plist..."
cp "$ROOT/Scripts/Info.plist" "$CONTENTS/Info.plist"

echo "▸ Copying localized resources..."
for lang in en it es sk fr; do
    src="$ROOT/Sources/IconPingApp/Resources/${lang}.lproj"
    dst="$RESOURCES_DIR/${lang}.lproj"
    if [ -d "$src" ]; then
        mkdir -p "$dst"
        cp "$src/Localizable.strings" "$dst/"
    fi
done

# SwiftPM may also stage the resources next to the binary as IconPingApp_IconPingApp.bundle.
# Copy that too so resource lookup via Bundle.module works inside the app bundle.
RES_BUNDLE_SRC="$BIN_PATH/IconPing_IconPingApp.bundle"
if [ -d "$RES_BUNDLE_SRC" ]; then
    echo "▸ Copying SwiftPM resource bundle..."
    cp -R "$RES_BUNDLE_SRC" "$RESOURCES_DIR/"
fi
# Also handle the older naming pattern
RES_BUNDLE_SRC2="$BIN_PATH/IconPingApp_IconPingApp.bundle"
if [ -d "$RES_BUNDLE_SRC2" ]; then
    cp -R "$RES_BUNDLE_SRC2" "$RESOURCES_DIR/"
fi

echo "▸ Ad-hoc code signing (no Developer ID yet)..."
codesign --force --sign - \
    --entitlements "$ROOT/Scripts/IconPing.entitlements" \
    --options runtime \
    "$APP_DIR" 2>/dev/null || codesign --force --sign - "$APP_DIR"

echo "▸ Verifying signature..."
codesign --verify --deep --strict "$APP_DIR" && echo "  signature OK (ad-hoc)"

echo "▸ Build complete: $APP_DIR"

if [ "$MAKE_DMG" = "1" ]; then
    echo "▸ Building DMG..."
    DMG="$BUILD_DIR/IconPing.dmg"
    STAGING="$BUILD_DIR/dmg-staging"
    rm -rf "$STAGING"
    mkdir -p "$STAGING"
    cp -R "$APP_DIR" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "IconPing" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
    rm -rf "$STAGING"
    echo "  DMG: $DMG"
fi

echo "Done."
