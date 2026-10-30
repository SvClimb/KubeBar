#!/bin/zsh
# Builds a universal (Apple Silicon + Intel) KubeBar.app.
#
#   Packaging/build-app.sh          build dist/KubeBar.app and run it in place of
#                                   the running KubeBar
#   Packaging/build-app.sh --zip    build dist/KubeBar-<version>.zip to share
#
# /Applications is never touched: the everyday copy there is managed by
# Homebrew (brew install --cask svclimb/tap/kubebar), and overwriting it
# would leave brew's records describing a different build. To go back to
# it after testing: quit the dev build and `open -a /Applications/KubeBar.app`.
#
# The app is ad-hoc signed (no Apple Developer ID), so on another Mac
# Gatekeeper blocks the first launch — see README.md for how to open it.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${(%):-%x}")/.." && pwd)"
APP_NAME="KubeBar"
DIST_DIR="$PROJECT_DIR/dist"
STAGING_BUNDLE="$DIST_DIR/$APP_NAME.app"
MIN_MACOS="14.0"

MODE=run
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

# Never leave the old version running next to the new one — whichever copy
# it is (the brew one or a previous dev build), it shares the same settings.
if [[ $MODE == run ]] && pgrep -xq "$APP_NAME"; then
    echo "Quitting running $APP_NAME..."
    osascript -e "tell application id \"com.svclimb.kubebar\" to quit" >/dev/null 2>&1 || true
    for _ in {1..20}; do pgrep -xq "$APP_NAME" || break; sleep 0.25; done
    pkill -x "$APP_NAME" || true
fi

echo "Assembling $APP_NAME.app..."
rm -rf "$STAGING_BUNDLE"
mkdir -p "$STAGING_BUNDLE/Contents/MacOS" "$STAGING_BUNDLE/Contents/Resources"
lipo -create -output "$STAGING_BUNDLE/Contents/MacOS/$APP_NAME" \
    "$PROJECT_DIR/.build/arm64-apple-macosx/release/$APP_NAME" \
    "$PROJECT_DIR/.build/x86_64-apple-macosx/release/$APP_NAME"
# Drop the debug symbol table: its entries embed absolute paths of the build
# machine's source and .o files (/Users/<name>/...).
strip -S "$STAGING_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Packaging/Info.plist" "$STAGING_BUNDLE/Contents/Info.plist"
cp "$PROJECT_DIR/Packaging/AppIcon.icns" "$STAGING_BUNDLE/Contents/Resources/AppIcon.icns"
# Copied straight into Contents/Resources (not SwiftPM resources, whose
# bundle would land in the .app root and break code signing) so SwiftUI and
# String(localized:) find them in Bundle.main.
cp -R "$PROJECT_DIR/Packaging/Localization/"*.lproj "$STAGING_BUNDLE/Contents/Resources/"
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

open "$STAGING_BUNDLE"

echo "Done: $STAGING_BUNDLE (running)"
