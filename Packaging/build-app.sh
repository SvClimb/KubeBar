#!/bin/zsh
# Builds a release binary, assembles it into KubeBar.app, and installs it to
# /Applications. Quit KubeBar first if it's currently running.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${(%):-%x}")/.." && pwd)"
APP_NAME="KubeBar"
STAGING_BUNDLE="$PROJECT_DIR/dist/$APP_NAME.app"
INSTALLED_BUNDLE="/Applications/$APP_NAME.app"

echo "Building release binary..."
swift build -c release --package-path "$PROJECT_DIR"

echo "Assembling $APP_NAME.app..."
rm -rf "$STAGING_BUNDLE"
mkdir -p "$STAGING_BUNDLE/Contents/MacOS" "$STAGING_BUNDLE/Contents/Resources"
cp "$PROJECT_DIR/.build/release/$APP_NAME" "$STAGING_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Packaging/Info.plist" "$STAGING_BUNDLE/Contents/Info.plist"
cp "$PROJECT_DIR/Packaging/AppIcon.icns" "$STAGING_BUNDLE/Contents/Resources/AppIcon.icns"

echo "Installing to $INSTALLED_BUNDLE..."
rm -rf "$INSTALLED_BUNDLE"
mv "$STAGING_BUNDLE" "$INSTALLED_BUNDLE"

echo "Done: $INSTALLED_BUNDLE"
