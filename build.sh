#!/usr/bin/env bash
# Build Kaki into a launchable .app bundle.
# macOS only shows the HUD/overlay when launched as a bundled app via LaunchServices
# (`open Kaki.app`). Running the bare binary from a shell gets no window-server access.
set -euo pipefail
cd "$(dirname "$0")"

APP="Kaki.app"
RES="$APP/Contents/Resources"

echo "Building binary..."
go build -o kaki .

echo "Assembling $APP ..."
mkdir -p "$APP/Contents/MacOS" "$RES"
cp kaki "$APP/Contents/MacOS/kaki"
cp Info.plist "$APP/Contents/Info.plist"
# Bundled wordmark font (added in a later task); copy if present.
if [ -f assets/fonts/ShipporiMincho-SemiBold.ttf ]; then
  cp assets/fonts/ShipporiMincho-SemiBold.ttf "$RES/"
fi

echo "Done. Launch with:  open $APP"
