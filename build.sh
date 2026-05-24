#!/usr/bin/env bash
# Build ScreenPen into a launchable .app bundle.
#
# macOS will only display a menu-bar status item and the overlay window when
# the program runs as a bundled app launched through LaunchServices. Running
# the bare binary directly from a shell does NOT get window-server privileges
# (setActivationPolicy returns 0 and nothing appears). So we always build into
# ScreenPen.app and launch with `open`.
set -euo pipefail
cd "$(dirname "$0")"

APP="ScreenPen.app"

echo "Building binary..."
go build -o screenpen .

echo "Assembling $APP ..."
mkdir -p "$APP/Contents/MacOS"
cp screenpen "$APP/Contents/MacOS/screenpen"
# Info.plist is committed under $APP/Contents/Info.plist (LSUIElement agent).

echo "Done. Launch with:  open $APP"
