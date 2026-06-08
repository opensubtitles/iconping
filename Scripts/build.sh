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
# Universal build strategy: build per arch separately then lipo, because
# SwiftPM's `--arch arm64 --arch x86_64` mode delegates to xcbuild and can
# silently produce a single-arch binary at the show-bin-path location.
# Doing it ourselves is verifiable and the same on CI and locally with Xcode.
HAS_XCODE=0
if [ -d "/Applications/Xcode.app" ] || [ -x "/Library/Developer/SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild" ]; then
    HAS_XCODE=1
fi

if [ "$HAS_XCODE" = "1" ]; then
    echo "  building arm64..."
    swift build -c "$CONFIGURATION" --arch arm64
    BIN_ARM64="$(swift build -c "$CONFIGURATION" --arch arm64 --show-bin-path)/IconPing"

    echo "  building x86_64..."
    swift build -c "$CONFIGURATION" --arch x86_64
    BIN_X86="$(swift build -c "$CONFIGURATION" --arch x86_64 --show-bin-path)/IconPing"

    echo "  lipo → universal binary..."
    UNIVERSAL_BIN="$BUILD_DIR/IconPing.universal"
    lipo -create -output "$UNIVERSAL_BIN" "$BIN_ARM64" "$BIN_X86"

    ARCHS="$(lipo -archs "$UNIVERSAL_BIN")"
    echo "  archs: $ARCHS"
    case "$ARCHS" in
        *arm64*x86_64*|*x86_64*arm64*) : ;;
        *) echo "❌ universal binary missing expected archs (got: $ARCHS)"; exit 1 ;;
    esac

    cp "$UNIVERSAL_BIN" "$MACOS_DIR/IconPing"
    BIN_PATH="$(swift build -c "$CONFIGURATION" --arch arm64 --show-bin-path)"  # for resource bundles
else
    echo "  CLT-only environment detected — building host-native (use CI for universal)"
    swift build -c "$CONFIGURATION"
    BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"
    cp "$BIN_PATH/IconPing" "$MACOS_DIR/IconPing"
fi
chmod +x "$MACOS_DIR/IconPing"

echo "  binary archs: $(lipo -archs "$MACOS_DIR/IconPing" 2>/dev/null || file -b "$MACOS_DIR/IconPing")"

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
    RW_DMG="$BUILD_DIR/IconPing.rw.dmg"
    STAGING="$BUILD_DIR/dmg-staging"
    rm -rf "$STAGING" "$DMG" "$RW_DMG"
    mkdir -p "$STAGING"
    cp -R "$APP_DIR" "$STAGING/"
    # NOTE: deliberately NOT putting `ln -s /Applications` here. On macOS Tahoe
    # (26.x), Finder no longer renders a bare symlink with the target's folder
    # icon in dark mode — it shows up transparent/blank. Instead we create a
    # real Mac alias inside the mounted DMG via AppleScript below, which
    # carries its own icon resource and renders correctly on every macOS.

    # Create a writable DMG sized to fit + headroom for alias file and .DS_Store
    SIZE_MB=$(( $(du -smc "$STAGING" | tail -1 | awk '{print $1}') + 20 ))
    hdiutil create -volname "IconPing" -srcfolder "$STAGING" -ov \
        -format UDRW -size ${SIZE_MB}m -fs HFS+ "$RW_DMG" >/dev/null

    # Mount writable and apply: (a) a real Mac alias to /Applications,
    # (b) Finder layout (icon view, positioned icons).
    MOUNT_OUT=$(hdiutil attach -nobrowse -readwrite -noverify "$RW_DMG")
    MOUNT_POINT=$(echo "$MOUNT_OUT" | grep "/Volumes/IconPing" | awk '{for(i=3;i<=NF;i++)printf "%s%s",$i,(i<NF?" ":"")}')
    echo "  mounted RW at: $MOUNT_POINT"

    osascript <<APPLESCRIPT 2>&1 | sed 's/^/  applescript: /' || echo "  (AppleScript step failed — DMG will ship without layout)"
tell application "Finder"
    tell disk "IconPing"
        -- Create a real Mac alias to /Applications (icon resource embedded)
        try
            set appsFolder to POSIX file "/Applications" as alias
            make new alias file at it to appsFolder
            -- New alias is named "Applications alias"; rename to plain "Applications"
            try
                set name of file "Applications alias" to "Applications"
            end try
        end try

        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 200, 740, 520}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 110
        try
            set position of item "IconPing.app" of container window to {140, 160}
        end try
        try
            set position of item "Applications" of container window to {400, 160}
        end try
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

    # Some macOS versions still leave the original "Applications alias" name.
    # Force-rename via the shell if so. Use null-delim find for safety.
    if [ -e "$MOUNT_POINT/Applications alias" ] && [ ! -e "$MOUNT_POINT/Applications" ]; then
        mv "$MOUNT_POINT/Applications alias" "$MOUNT_POINT/Applications"
    fi
    echo "  DMG contents:"
    ls -la "$MOUNT_POINT" | grep -vE "^total|^\.\." | sed 's/^/    /'

    sync
    hdiutil detach "$MOUNT_POINT" -quiet || hdiutil detach "$MOUNT_POINT" -force

    # Convert RW → compressed read-only UDZO
    hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
    rm -f "$RW_DMG"
    rm -rf "$STAGING"
    echo "  DMG: $DMG"
fi

echo "Done."
