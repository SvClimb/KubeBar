#!/bin/zsh
# Builds a universal (Apple Silicon + Intel) KubeBar.app.
#
#   Packaging/build-app.sh          build, install to /Applications, restart KubeBar
#   Packaging/build-app.sh --zip    build dist/KubeBar-<version>.zip to share
#
# The app is ad-hoc signed (no Apple Developer ID), so on another Mac
# Gatekeeper blocks the first launch — see README.md for how to open it.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${(%):-%x}")/.." && pwd)"
APP_NAME="KubeBar"
DIST_DIR="$PROJECT_DIR/dist"
STAGING_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALLED_BUNDLE="/Applications/$APP_NAME.app"
MIN_MACOS="14.0"

MODE=install
case "${1:-}" in
    "") ;;
    --zip) MODE=zip ;;
    *) echo "usage: $0 [--zip]" >&2; exit 2 ;;
esac

# A universal `swift build --arch arm64 --arch x86_64` needs full Xcode;
# building each slice separately and merging with lipo works with just the
# Command Line Tools.
for arch in arm64 x86_64; do
    echo "Building release binary ($arch)..."
    swift build -c release --package-path "$PROJECT_DIR" --triple "$arch-apple-macosx$MIN_MACOS"
done

echo "Assembling $APP_NAME.app..."
rm -rf "$STAGING_BUNDLE"
mkdir -p "$STAGING_BUNDLE/Contents/MacOS" "$STAGING_BUNDLE/Contents/Resources"
lipo -create -output "$STAGING_BUNDLE/Contents/MacOS/$APP_NAME" \
    "$PROJECT_DIR/.build/arm64-apple-macosx/release/$APP_NAME" \
    "$PROJECT_DIR/.build/x86_64-apple-macosx/release/$APP_NAME"
cp "$PROJECT_DIR/Packaging/Info.plist" "$STAGING_BUNDLE/Contents/Info.plist"
cp "$PROJECT_DIR/Packaging/AppIcon.icns" "$STAGING_BUNDLE/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$STAGING_BUNDLE"

if [[ $MODE == zip ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_DIR/Packaging/Info.plist")
    ZIP="$DIST_DIR/$APP_NAME-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$STAGING_BUNDLE" "$ZIP"
    rm -rf "$STAGING_BUNDLE"
    echo "Done: $ZIP"
    exit 0
fi

# Never leave the old version running next to the new one.
if pgrep -xq "$APP_NAME"; then
    echo "Quitting running $APP_NAME..."
    osascript -e "tell application id \"com.svclimb.kubebar\" to quit" >/dev/null 2>&1 || true
    for _ in {1..20}; do pgrep -xq "$APP_NAME" || break; sleep 0.25; done
    pkill -x "$APP_NAME" || true
fi

echo "Installing to $INSTALLED_BUNDLE..."
rm -rf "$INSTALLED_BUNDLE"
mv "$STAGING_BUNDLE" "$INSTALLED_BUNDLE"
open "$INSTALLED_BUNDLE"

echo "Done: $INSTALLED_BUNDLE (running)"
